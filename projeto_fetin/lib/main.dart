import 'package:flutter/material.dart';
import 'tema/app_tema.dart';
import 'telas/splash/tela_splash.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'servicos/servico_monitoramento.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();
  ServicoMonitoramento.configurar();

  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,

      systemNavigationBarColor: Colors.black,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const KeepCloseApp());
}

class KeepCloseApp extends StatelessWidget {
  const KeepCloseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      //raiz do app Flutter, ele controla tudo
      debugShowCheckedModeBanner: false,

      title: 'KeepClose',

      theme: AppTema.lightTheme,

      home: const TelaSplash(),
    );
  }
}
