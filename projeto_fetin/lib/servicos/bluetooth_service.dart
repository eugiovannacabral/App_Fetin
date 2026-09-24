import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:async';

class BluetoothServiceKeepClose {
  static final BluetoothServiceKeepClose instancia =
      BluetoothServiceKeepClose._();

  BluetoothServiceKeepClose._();

  final Map<String, BluetoothDevice> dispositivosConectados = {};

  // UUID do serviço BLE da tag KeepClose
  final Guid serviceUuid = Guid("12345678-1234-1234-1234-123456789001");

  Stream<List<ScanResult>> get resultadosScan => FlutterBluePlus.scanResults;

  Future<void> iniciarBusca() async {
    print("TESTE 1: iniciarBusca foi chamado");

    final suportado = await FlutterBluePlus.isSupported;

    print("TESTE 2: Bluetooth suportado = $suportado");

    if (!suportado) {
      throw Exception("Bluetooth não suportado neste celular");
    }

    final estado = FlutterBluePlus.adapterStateNow;

    if (estado != BluetoothAdapterState.on) {
      throw Exception("Bluetooth desligado");
    }

    await FlutterBluePlus.stopScan();

    print("TESTE 3: iniciando scan");

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

    print("TESTE 4: startScan executado");
  }

  Future<void> pararBusca() async {
    await FlutterBluePlus.stopScan();
  }

  Future<void> conectar(BluetoothDevice device) async {
    if (!device.isConnected) {
      await device.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 10),
      );
    }

    dispositivosConectados[device.remoteId.str] = device;
  }

  Future<void> desconectarPorId(String idBluetooth) async {
    final dispositivo = dispositivosConectados.remove(idBluetooth);

    if (dispositivo != null && dispositivo.isConnected) {
      try {
        await dispositivo.disconnect();
        print("DESCONECTADO: $idBluetooth");
      } catch (erro) {
        print("ERRO AO DESCONECTAR: $erro");
      }
    }

    await FlutterBluePlus.stopScan();
    await Future.delayed(const Duration(seconds: 2));
  }

  Future<void> reconectarPorId(String idBluetooth) async {
    print("RECONEXÃO: procurando $idBluetooth");

    final estadoBluetooth = await FlutterBluePlus.adapterState
        .where((estado) => estado == BluetoothAdapterState.on)
        .first;

    print("RECONEXÃO: Bluetooth pronto = $estadoBluetooth");

    BluetoothDevice? dispositivoEncontrado;

    late StreamSubscription<List<ScanResult>> assinatura;

    assinatura = FlutterBluePlus.onScanResults.listen((resultados) {
      for (final resultado in resultados) {
        final idEncontrado = resultado.device.remoteId.str;

        if (idEncontrado == idBluetooth) {
          dispositivoEncontrado = resultado.device;

          print("RECONEXÃO: tag encontrada $idEncontrado");
        }
      }
    });

    try {
      await FlutterBluePlus.stopScan();

      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));

      // Dá tempo para a tag aparecer durante o scan.
      for (int tentativa = 0; tentativa < 16; tentativa++) {
        if (dispositivoEncontrado != null) {
          break;
        }

        await Future.delayed(const Duration(milliseconds: 500));
      }

      final device = dispositivoEncontrado;

      if (device == null) {
        print("RECONEXÃO: tag $idBluetooth não encontrada");
        return;
      }

      await FlutterBluePlus.stopScan();

      if (!device.isConnected) {
        print("RECONEXÃO: conectando...");

        await device.connect(
          license: License.nonprofit,
          timeout: const Duration(seconds: 10),
        );
      }

      dispositivosConectados[idBluetooth] = device;

      print("RECONEXÃO: conectado com sucesso");
    } catch (erro) {
      print("RECONEXÃO ERRO: $erro");
    } finally {
      await assinatura.cancel();
      await FlutterBluePlus.stopScan();
    }
  }

  Future<int?> lerRssiPorId(String idBluetooth) async {
    final device = dispositivosConectados[idBluetooth];

    if (device == null || !device.isConnected) {
      return null;
    }

    try {
      return await device.readRssi();
    } catch (erro) {
      print("Erro ao ler RSSI: $erro");
      return null;
    }
  }

  Stream<bool>? monitorarConexaoPorId(String idBluetooth) {
    final device = dispositivosConectados[idBluetooth];

    if (device == null) {
      return null;
    }

    return device.connectionState.map(
      (estado) => estado == BluetoothConnectionState.connected,
    );
  }
}
