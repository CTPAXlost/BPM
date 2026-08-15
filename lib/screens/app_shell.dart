import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_controller.dart';
import 'home_screen.dart';
import 'settings_screen.dart';
import 'warp_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int index = 0;
  String? _shownMessage;
  static const pages = <Widget>[HomeScreen(), WarpScreen(), SettingsScreen()];
  @override void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); }
  @override void dispose() { WidgetsBinding.instance.removeObserver(this); super.dispose(); }
  @override void didChangeAppLifecycleState(AppLifecycleState state) { if (state == AppLifecycleState.resumed && mounted) context.read<AppController>().onAppResumed(); }

  @override Widget build(BuildContext context) {
    return Consumer<AppController>(builder: (context, controller, _) {
      if (controller.message != null && controller.message != _shownMessage) {
        _shownMessage = controller.message;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(controller.message!)));
        });
      }
      if (controller.loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
      return Stack(children: <Widget>[
        Scaffold(
          body: IndexedStack(index: index, children: pages),
          bottomNavigationBar: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (value) => setState(() => index = value),
            destinations: const <NavigationDestination>[
              NavigationDestination(icon: Icon(Icons.shield_outlined), selectedIcon: Icon(Icons.shield), label: 'VPN'),
              NavigationDestination(icon: Icon(Icons.bolt_outlined), selectedIcon: Icon(Icons.bolt), label: 'WARP'),
              NavigationDestination(icon: Icon(Icons.tune_outlined), selectedIcon: Icon(Icons.tune), label: 'Настройки'),
            ],
          ),
        ),
        IgnorePointer(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            reverseDuration: const Duration(milliseconds: 280),
            transitionBuilder: (child, animation) => SlideTransition(
              position: Tween<Offset>(begin: const Offset(1.1, 0.2), end: Offset.zero).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutBack)),
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: controller.showToasty
                ? Align(
                    key: const ValueKey('toasty'),
                    alignment: Alignment.centerRight,
                    child: Image.asset('assets/images/toasty_face_cutout.png', width: MediaQuery.sizeOf(context).width.clamp(260, 390).toDouble() * .72),
                  )
                : const SizedBox(key: ValueKey('empty')),
          ),
        ),
      ]);
    });
  }
}
