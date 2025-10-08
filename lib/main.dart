import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'login_page.dart';
import 'background_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  initializeService();
  runApp(MyApp());
}

Future<void> initializeService() async {
  final backgroundHelper = BackgroundServiceHelper();
  await backgroundHelper.initializeService();
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Enhanced Polar Monitor',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: LoginPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}