import 'package:flutter/material.dart';
import 'tela_adicionar_dispositivo.dart';
import '../modelo/dispositivo_modelo.dart';
import 'package:projeto_fetin/tema/app_cores.dart';
import '../../servicos/bluetooth_service.dart';
import 'dart:async';
import '../modelo/usuario_modelo.dart';
import '../../dados/banco_dados.dart';
import 'dart:math';
import '../alertas/tela_alerta_distancia.dart';
import '../configuracao/tela_configuracoes_alerta.dart';
import '../../servicos/servico_monitoramento.dart';

//alterando o construtor para receber um usuário
class TelaHome extends StatefulWidget {
  final UsuarioModelo usuario;

  const TelaHome({super.key, required this.usuario});

  @override
  State<TelaHome> createState() => _TelaHomeState();
}

class _TelaHomeState extends State<TelaHome> {
  static const int limiteRssiCritico = -92;
  final Map<String, List<int>> historicoRssi = {};
  // Conta quantas leituras críticas consecutivas cada dispositivo teve.
  final Map<String, int> contadorLeiturasCriticas = {};
  final Map<String, double> distancias = {};
  // Guarda quais dispositivos já dispararam o alerta.
  // Evita abrir várias telas de alerta ao mesmo tempo.
  final Set<String> alertasConfirmados = {};
  final List<DispositivoModelo> dispositivos =
      []; //guarda temporariamente os nomes adicionados
  final BluetoothServiceKeepClose bluetooth =
      BluetoothServiceKeepClose.instancia;
  // Guarda os dispositivos que já estão tentando reconectar.
  // Evita iniciar duas reconexões ao mesmo tempo.
  final Set<String> reconexoesEmAndamento = {};
  // Guarda os dispositivos que já possuem
  // um monitor de conexão ativo.
  final Set<String> dispositivosMonitorados = {};
  Future<void> carregarDispositivos() async {
    try {
      final usuarioId = widget.usuario.id;

      if (usuarioId == null) {
        return;
      }

      final dispositivosSalvos = await BancoDados.instancia
          .buscarDispositivosDoUsuario(usuarioId);

      for (final dispositivo in dispositivosSalvos) {
        dispositivo.conectado = false;
        dispositivo.rssi = null;
        dispositivo.proximidade = "Fora de alcance";
      }

      if (!mounted) {
        return;
      }

      setState(() {
        dispositivos
          ..clear()
          ..addAll(dispositivosSalvos);
      });

      for (final dispositivo in dispositivosSalvos) {
        try {
          await bluetooth.reconectarPorId(dispositivo.idBluetooth);
          monitorarConexao(dispositivo);
        } catch (erro) {
          debugPrint("Não foi possível reconectar ${dispositivo.nome}: $erro");
        }
      }
    } catch (erro) {
      debugPrint("Erro ao carregar dispositivos: $erro");

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Não foi possível carregar os dispositivos salvos."),
        ),
      );
    }
  }

  String classificarSinal(int rssi) {
    if (rssi >= -68) {
      return "Muito próximo";
    }

    if (rssi >= -78) {
      return "Próximo";
    }

    if (rssi >= limiteRssiCritico) {
      return "Distante";
    }

    return "Crítico";
  }

  void verificarSinalCritico(DispositivoModelo dispositivo, int rssi) {
    final idBluetooth = dispositivo.idBluetooth;

    // Quantidade de leituras críticas necessárias
    // para confirmar que o usuário está se afastando.
    const int limiteLeiturasCriticas = 3;

    // Abaixo de -85 dBm consideramos o sinal crítico.
    if (rssi < limiteRssiCritico) {
      contadorLeiturasCriticas[idBluetooth] =
          (contadorLeiturasCriticas[idBluetooth] ?? 0) + 1;

      final quantidade = contadorLeiturasCriticas[idBluetooth]!;

      print(
        "LEITURA CRÍTICA ${dispositivo.nome}: "
        "$quantidade/$limiteLeiturasCriticas | "
        "RSSI=$rssi dBm",
      );

      if (quantidade >= limiteLeiturasCriticas &&
          !alertasConfirmados.contains(idBluetooth)) {
        alertasConfirmados.add(idBluetooth);

        print(
          "ATENÇÃO: sinal crítico confirmado "
          "para ${dispositivo.nome}",
        );

        if (!mounted) {
          return;
        }

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                TelaAlertaDistancia(nomeDispositivo: dispositivo.nome),
          ),
        );
      }
    } else {
      contadorLeiturasCriticas[idBluetooth] = 0;

      alertasConfirmados.remove(idBluetooth);
    }
  }

  int suavizarRssi(String idBluetooth, int novoRssi) {
    final historico = historicoRssi.putIfAbsent(idBluetooth, () => []);

    historico.add(novoRssi);

    // Mantém somente as últimas 5 leituras.
    if (historico.length > 5) {
      historico.removeAt(0);
    }

    final soma = historico.reduce((a, b) => a + b);

    return (soma / historico.length).round();
  }

  double calcularDistancia(int rssi) {
    const double rssiReferencia = -72.0;
    const double fatorAmbiente = 2.1;

    final expoente = (rssiReferencia - rssi) / (10 * fatorAmbiente);

    final distancia = pow(10, expoente);

    return distancia.toDouble();
  }

  Future<void> atualizarRssi(DispositivoModelo dispositivo) async {
    if (!dispositivo.conectado) {
      return;
    }

    final rssi = await bluetooth.lerRssiPorId(dispositivo.idBluetooth);

    if (!mounted) {
      return;
    }

    if (rssi == null) {
      setState(() {
        dispositivo.rssi = null;
        dispositivo.proximidade = "Aguardando sinal";

        distancias.remove(dispositivo.idBluetooth);
      });

      return;
    }

    final rssiSuavizado = suavizarRssi(dispositivo.idBluetooth, rssi);

    final distancia = calcularDistancia(rssiSuavizado);

    final proximidadeAtual = classificarSinal(rssiSuavizado);

    final sinalCritico = rssiSuavizado < limiteRssiCritico;

    ServicoMonitoramento.atualizarStatus(
      nome: dispositivo.nome,
      proximidade: proximidadeAtual,
      distancia: distancia,
      critico: sinalCritico,
    );

    verificarSinalCritico(dispositivo, rssiSuavizado);

    print(
      "RSSI ${dispositivo.nome}: "
      "bruto=$rssi | "
      "suavizado=$rssiSuavizado dBm | "
      "distância=${distancia.toStringAsFixed(2)} m",
    );

    setState(() {
      dispositivo.rssi = rssiSuavizado;

      distancias[dispositivo.idBluetooth] = distancia;

      dispositivo.proximidade = proximidadeAtual;

      dispositivo.ultimaConexao = "Agora";
    });
  }

  void monitorarConexao(DispositivoModelo dispositivo) {
    final idBluetooth = dispositivo.idBluetooth;

    // Se já existe um monitor para este dispositivo,
    // não criamos outro listener.
    if (dispositivosMonitorados.contains(idBluetooth)) {
      return;
    }

    final stream = bluetooth.monitorarConexaoPorId(idBluetooth);

    // O dispositivo pode ainda não ter sido encontrado
    // pelo serviço Bluetooth.
    if (stream == null) {
      print("CONEXÃO: dispositivo ainda não disponível para monitoramento");

      return;
    }

    // Só marcamos como monitorado depois que
    // realmente conseguimos obter o stream.
    dispositivosMonitorados.add(idBluetooth);

    stream.listen((conectado) {
      print("CONEXÃO ${dispositivo.nome}: $conectado");

      if (!mounted) {
        return;
      }

      setState(() {
        dispositivo.conectado = conectado;

        if (!conectado) {
          dispositivo.rssi = null;
          dispositivo.proximidade = "Fora de alcance";

          historicoRssi.remove(dispositivo.idBluetooth);

          distancias.remove(dispositivo.idBluetooth);
        }
      });
    });
  }

  Timer? timerRssi;
  Timer? timerReconexao;
  void iniciarMonitoramentoRssi() {
    timerRssi = Timer.periodic(const Duration(seconds: 2), (timer) async {
      for (final dispositivo in dispositivos) {
        await atualizarRssi(dispositivo);
      }
    });
  }

  void iniciarMonitoramentoReconexao() {
    timerReconexao = Timer.periodic(const Duration(seconds: 5), (timer) async {
      for (final dispositivo in dispositivos) {
        final idBluetooth = dispositivo.idBluetooth;

        // Só tenta reconectar se:
        // 1. o dispositivo estiver desconectado;
        // 2. ainda não existir outra tentativa em andamento.
        if (!dispositivo.conectado &&
            !reconexoesEmAndamento.contains(idBluetooth)) {
          reconexoesEmAndamento.add(idBluetooth);

          print(
            "Tentando reconectar automaticamente: "
            "${dispositivo.nome}",
          );

          try {
            await bluetooth.reconectarPorId(idBluetooth);

            // Depois da tentativa de reconexão,
            // tenta iniciar o monitor da conexão.
            //
            // Se já existir um monitor, o método
            // simplesmente não cria outro.
            monitorarConexao(dispositivo);
          } finally {
            // Quando a tentativa terminar,
            // libera uma nova tentativa futura.
            reconexoesEmAndamento.remove(idBluetooth);
          }
        }
      }
    });
  }

  @override
  void initState() {
    super.initState();
    ServicoMonitoramento.solicitarPermissao();
    ServicoMonitoramento.iniciar();
    carregarDispositivos();

    iniciarMonitoramentoReconexao();
    iniciarMonitoramentoRssi();
  }

  @override
  void dispose() {
    timerRssi?.cancel();
    timerReconexao?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,

      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              Row(
                children: [
                  const Icon(
                    Icons.location_on,
                    color: AppCores.roxoMeioTermo,
                    size: 38,
                  ),

                  const SizedBox(width: 8),

                  const Text(
                    "KeepClose",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppCores.roxoMeioTermo,
                    ),
                  ),

                  const Spacer(),

                  // Abre a tela de configurações do alerta.
                  IconButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const TelaConfiguracoesAlerta(),
                        ),
                      );
                    },

                    icon: const Icon(
                      Icons.settings_outlined,
                      color: AppCores.roxoMeioTermo,
                      size: 28,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 35),
              Text(
                "Olá, ${widget.usuario.nome}!",
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 6),

              const Text(
                "Seus dispositivos",
                style: TextStyle(fontSize: 16, color: AppCores.cinza),
              ),
              const SizedBox(height: 30),

              Expanded(
                child: dispositivos.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.bluetooth_searching,
                              size: 80,
                              color: Colors.grey.shade400,
                            ),

                            const SizedBox(height: 20),

                            const Text(
                              "Nenhum dispositivo adicionado",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),

                            const SizedBox(height: 10),

                            Text(
                              "Toque no botão + para adicionar\nsua primeira tag.",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 15,
                                height: 1.4,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: dispositivos.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 16),

                        itemBuilder: (context, index) {
                          final dispositivo = dispositivos[index];

                          return Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),

                            decoration: BoxDecoration(
                              color: AppCores.branco,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: const [
                                BoxShadow(
                                  color: AppCores.berandoPreto,
                                  blurRadius: 10,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),

                            child: Row(
                              children: [
                                const Icon(
                                  Icons.bluetooth_connected,
                                  size: 38,
                                  color: AppCores.roxoMeioTermo,
                                ),

                                const SizedBox(width: 15),

                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,

                                    children: [
                                      Text(
                                        dispositivo.nome,
                                        style: const TextStyle(
                                          fontSize: 19,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),

                                      const SizedBox(height: 10),

                                      Row(
                                        children: [
                                          Icon(
                                            dispositivo.conectado
                                                ? Icons.circle
                                                : Icons.circle_outlined,
                                            color: dispositivo.conectado
                                                ? Colors.green
                                                : Colors.red,
                                            size: 12,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            dispositivo.conectado
                                                ? "Conectado"
                                                : "Fora de alcance",

                                            style: TextStyle(
                                              fontWeight: FontWeight.w500,
                                              color: dispositivo.conectado
                                                  ? Colors.green
                                                  : Colors.red,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),

                                      Text(
                                        dispositivo.conectado &&
                                                distancias[dispositivo
                                                        .idBluetooth] !=
                                                    null
                                            ? "Distância aproximada: "
                                                  "${distancias[dispositivo.idBluetooth]!.toStringAsFixed(2)} m"
                                            : "Distância aproximada: Fora de alcance",
                                      ),

                                      const SizedBox(height: 6),

                                      Text(
                                        "Última conexão: ${dispositivo.ultimaConexao}",
                                      ),
                                      const SizedBox(height: 6),

                                      Text(
                                        "Proximidade: ${dispositivo.proximidade}",
                                      ),
                                    ],
                                  ),
                                ),

                                PopupMenuButton<String>(
                                  icon: const Icon(
                                    Icons.more_vert,
                                    color: AppCores.cinza,
                                  ),

                                  onSelected: (valor) {
                                    if (valor == "renomear") {
                                      final controller = TextEditingController(
                                        text: dispositivo.nome,
                                      );

                                      showDialog(
                                        context: context,
                                        builder: (context) {
                                          return AlertDialog(
                                            title: const Text(
                                              "Renomear dispositivo",
                                            ),

                                            content: TextField(
                                              controller: controller,
                                              decoration: const InputDecoration(
                                                labelText: "Novo nome",
                                              ),
                                            ),

                                            actions: [
                                              TextButton(
                                                onPressed: () async {
                                                  final novoNome = controller
                                                      .text
                                                      .trim();

                                                  if (novoNome.isEmpty) {
                                                    return;
                                                  }

                                                  await BancoDados.instancia
                                                      .renomearDispositivo(
                                                        idBluetooth: dispositivo
                                                            .idBluetooth,
                                                        usuarioId: dispositivo
                                                            .usuarioId,
                                                        novoNome: novoNome,
                                                      );

                                                  if (!mounted ||
                                                      !context.mounted) {
                                                    return;
                                                  }

                                                  setState(() {
                                                    dispositivo.nome = novoNome;
                                                  });

                                                  Navigator.pop(context);
                                                },
                                                child: const Text("Cancelar"),
                                              ),

                                              TextButton(
                                                onPressed: () {
                                                  final novoNome = controller
                                                      .text
                                                      .trim();

                                                  if (novoNome.isNotEmpty) {
                                                    setState(() {
                                                      dispositivo.nome =
                                                          novoNome;
                                                    });
                                                  }

                                                  Navigator.pop(context);
                                                },
                                                child: const Text("Salvar"),
                                              ),
                                            ],
                                          );
                                        },
                                      );
                                    }

                                    if (valor == "remover") {
                                      showDialog(
                                        context: context,
                                        builder: (context) {
                                          return AlertDialog(
                                            title: const Text(
                                              "Remover dispositivo",
                                            ),
                                            content: Text(
                                              "Deseja realmente remover ${dispositivo.nome}?",
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () {
                                                  Navigator.pop(context);
                                                },
                                                child: const Text("Cancelar"),
                                              ),

                                              TextButton(
                                                onPressed: () async {
                                                  await BancoDados.instancia
                                                      .excluirDispositivo(
                                                        idBluetooth: dispositivo
                                                            .idBluetooth,
                                                        usuarioId: dispositivo
                                                            .usuarioId,
                                                      );
                                                  await bluetooth
                                                      .desconectarPorId(
                                                        dispositivo.idBluetooth,
                                                      );

                                                  if (!mounted ||
                                                      !context.mounted) {
                                                    return;
                                                  }

                                                  setState(() {
                                                    dispositivos.removeWhere(
                                                      (item) =>
                                                          item.idBluetooth ==
                                                          dispositivo
                                                              .idBluetooth,
                                                    );

                                                    historicoRssi.remove(
                                                      dispositivo.idBluetooth,
                                                    );
                                                    distancias.remove(
                                                      dispositivo.idBluetooth,
                                                    );
                                                  });

                                                  Navigator.pop(context);
                                                },
                                                child: const Text(
                                                  "Remover",
                                                  style: TextStyle(
                                                    color: Colors.red,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          );
                                        },
                                      );
                                    }
                                  },

                                  itemBuilder: (context) => const [
                                    PopupMenuItem(
                                      value: "renomear",
                                      child: Row(
                                        children: [
                                          Icon(Icons.edit_outlined),
                                          SizedBox(width: 10),
                                          Text("Renomear"),
                                        ],
                                      ),
                                    ),

                                    PopupMenuItem(
                                      value: "remover",
                                      child: Row(
                                        children: [
                                          Icon(Icons.delete_outline),
                                          SizedBox(width: 10),
                                          Text("Remover dispositivo"),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final dispositivo = await Navigator.push<DispositivoModelo>(
            context,
            MaterialPageRoute(
              builder: (context) => TelaAdicionarDispositivo(
                idsCadastrados: dispositivos
                    .map((dispositivo) => dispositivo.idBluetooth)
                    .toList(),
                usuarioId: widget.usuario.id!,
              ),
            ),
          );

          if (dispositivo != null) {
            await BancoDados.instancia.salvarDispositivo(dispositivo);
            if (!mounted) {
              return;
            }
            setState(() {
              dispositivos.add(dispositivo);
            });

            monitorarConexao(dispositivo);
            // await atualizarRssi(dispositivo);
          }
        },
        backgroundColor: AppCores.roxoMeioTermo,
        foregroundColor: AppCores.branco,
        child: const Icon(Icons.add),
      ),
    );
  }
}
