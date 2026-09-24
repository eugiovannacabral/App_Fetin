import 'package:flutter_foreground_task/flutter_foreground_task.dart';

@pragma('vm:entry-point')
void iniciarCallbackMonitoramento() {
  FlutterForegroundTask.setTaskHandler(MonitoramentoTaskHandler());
}

class MonitoramentoTaskHandler extends TaskHandler {
  bool alarmeSilenciado = false;
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    print("SERVIÇO: monitoramento iniciado");
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // A notificação será atualizada quando a TelaHome
    // enviar uma nova leitura de distância.
  }

  @override
  void onReceiveData(Object data) {
    if (data is! Map) {
      return;
    }

    final tipo = data["tipo"];

    if (tipo == "silenciar_alarme") {
      alarmeSilenciado = true;

      FlutterForegroundTask.updateService(
        notificationTitle: "KeepClose",
        notificationText: "Alarme desativado pelo usuário",
        notificationButtons: const [],
      );

      return;
    }

    if (tipo != "status_tag") {
      return;
    }

    final nome = data["nome"]?.toString() ?? "Tag KeepClose";
    final proximidade = data["proximidade"]?.toString() ?? "Aguardando sinal";
    final distancia = data["distancia"]?.toString() ?? "--";
    final critico = data["critico"] == true;

    // Quando a tag deixa a região crítica,
    // o próximo alerta pode ser ativado novamente.
    if (!critico) {
      alarmeSilenciado = false;
    }

    final mostrarAlerta = critico && !alarmeSilenciado;

    FlutterForegroundTask.updateService(
      notificationTitle: mostrarAlerta
          ? "ALERTA: $nome está distante"
          : "KeepClose: $nome",
      notificationText: mostrarAlerta
          ? "Distância crítica. Toque em desativar."
          : alarmeSilenciado && critico
          ? "Alarme desativado • sinal ainda crítico"
          : "$proximidade • aproximadamente $distancia m",
      notificationButtons: mostrarAlerta
          ? const [
              NotificationButton(
                id: "desativar_alarme",
                text: "DESATIVAR ALARME",
              ),
            ]
          : const [],
    );
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id != "desativar_alarme") {
      return;
    }
    alarmeSilenciado = true;

    // Envia o comando para a tela que está reproduzindo
    // o som e a vibração.
    FlutterForegroundTask.sendDataToMain("desativar_alarme");

    // Mantém a mesma notificação, mas retira o botão.
    FlutterForegroundTask.updateService(
      notificationTitle: "KeepClose",
      notificationText: "Alarme desativado pelo usuário",
      notificationButtons: const [],
    );
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp();
  }

  @override
  void onNotificationDismissed() {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    print("SERVIÇO: monitoramento encerrado");
  }
}

class ServicoMonitoramento {
  static void configurar() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: "keepclose_monitoramento",
        channelName: "Monitoramento KeepClose",
        channelDescription: "Mantém o monitoramento da tag KeepClose ativo.",
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  static Future<void> solicitarPermissao() async {
    final permissao = await FlutterForegroundTask.checkNotificationPermission();

    if (permissao != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
  }

  static Future<ServiceRequestResult> iniciar() async {
    if (await FlutterForegroundTask.isRunningService) {
      return FlutterForegroundTask.restartService();
    }

    return FlutterForegroundTask.startService(
      serviceId: 200,
      notificationTitle: "KeepClose está monitorando",
      notificationText: "Aguardando leitura da tag",
      callback: iniciarCallbackMonitoramento,
    );
  }

  static void atualizarStatus({
    required String nome,
    required String proximidade,
    required double distancia,
    required bool critico,
  }) {
    FlutterForegroundTask.sendDataToTask({
      "tipo": "status_tag",
      "nome": nome,
      "proximidade": proximidade,
      "distancia": distancia.toStringAsFixed(2),
      "critico": critico,
    });
  }

  static Future<ServiceRequestResult> parar() {
    return FlutterForegroundTask.stopService();
  }

  static void silenciarAlarme() {
    FlutterForegroundTask.sendDataToTask({"tipo": "silenciar_alarme"});
  }
}
