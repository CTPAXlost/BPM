import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/app_shell.dart';
import 'services/app_controller.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PokolenieApp());
}

class PokolenieApp extends StatelessWidget {
  const PokolenieApp({super.key});
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppController>(
      create: (_) => AppController()..initialize(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Pokolenie WARP',
        theme: buildAppTheme(),
        home: const AppShell(),
      ),
    );
  }
}
