import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_controller.dart';
import 'home_screen.dart';
import 'servers_screen.dart';
import 'settings_screen.dart';
import 'sources_screen.dart';
import 'warp_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int index = 0;
  String? _shownMessage;

  static const pages = <Widget>[
    HomeScreen(),
    ServersScreen(),
    WarpScreen(),
    SourcesScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    context.read<AppController>().onAppResumed();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppController>(
      builder: (context, controller, _) {
        final currentMessage = controller.message;
        if (currentMessage != null && currentMessage != _shownMessage) {
          _shownMessage = currentMessage;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(currentMessage)),
            );
          });
        }
        if (controller.loading) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: CircularProgressIndicator(),
                  ),
                  SizedBox(height: 18),
                  Text(
                    'Запуск Поколения…',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          );
        }
        return Scaffold(
          body: IndexedStack(index: index, children: pages),
          bottomNavigationBar: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (value) => setState(() => index = value),
            destinations: const <NavigationDestination>[
              NavigationDestination(
                icon: Icon(Icons.shield_outlined),
                selectedIcon: Icon(Icons.shield_rounded),
                label: 'VPN',
              ),
              NavigationDestination(
                icon: Icon(Icons.dns_outlined),
                selectedIcon: Icon(Icons.dns_rounded),
                label: 'Серверы',
              ),
              NavigationDestination(
                icon: Icon(Icons.bolt_outlined),
                selectedIcon: Icon(Icons.bolt_rounded),
                label: 'WARP',
              ),
              NavigationDestination(
                icon: Icon(Icons.sync_alt_outlined),
                selectedIcon: Icon(Icons.sync_alt_rounded),
                label: 'Источники',
              ),
              NavigationDestination(
                icon: Icon(Icons.tune_outlined),
                selectedIcon: Icon(Icons.tune_rounded),
                label: 'Ещё',
              ),
            ],
          ),
        );
      },
    );
  }
}
