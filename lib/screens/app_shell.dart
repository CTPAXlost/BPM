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
        IgnorePointer(child: _ToastyEntrance(visible: controller.showToasty)),
      ]);
    });
  }
}

class _ToastyEntrance extends StatefulWidget {
  const _ToastyEntrance({required this.visible});
  final bool visible;

  @override
  State<_ToastyEntrance> createState() => _ToastyEntranceState();
}

class _ToastyEntranceState extends State<_ToastyEntrance> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2500),
  );
  late final Animation<Offset> _slide = TweenSequence<Offset>(<TweenSequenceItem<Offset>>[
    TweenSequenceItem(
      tween: Tween<Offset>(begin: const Offset(1.18, 0), end: Offset.zero)
          .chain(CurveTween(curve: Curves.easeOutBack)),
      weight: 12,
    ),
    TweenSequenceItem(tween: ConstantTween<Offset>(Offset.zero), weight: 72),
    TweenSequenceItem(
      tween: Tween<Offset>(begin: Offset.zero, end: const Offset(1.18, 0))
          .chain(CurveTween(curve: Curves.easeInCubic)),
      weight: 16,
    ),
  ]).animate(_controller);
  late final Animation<double> _opacity = TweenSequence<double>(<TweenSequenceItem<double>>[
    TweenSequenceItem(tween: Tween<double>(begin: 0, end: 1), weight: 8),
    TweenSequenceItem(tween: ConstantTween<double>(1), weight: 76),
    TweenSequenceItem(tween: Tween<double>(begin: 1, end: 0), weight: 16),
  ]).animate(_controller);
  late final Animation<double> _scale = TweenSequence<double>(<TweenSequenceItem<double>>[
    TweenSequenceItem(tween: Tween<double>(begin: .88, end: 1).chain(CurveTween(curve: Curves.easeOutBack)), weight: 12),
    TweenSequenceItem(tween: ConstantTween<double>(1), weight: 72),
    TweenSequenceItem(tween: Tween<double>(begin: 1, end: .96), weight: 16),
  ]).animate(_controller);
  late final Animation<double> _textScale = CurvedAnimation(
    parent: _controller,
    curve: const Interval(.05, .18, curve: Curves.elasticOut),
  );

  @override
  void initState() {
    super.initState();
    if (widget.visible) _controller.forward();
  }

  @override
  void didUpdateWidget(covariant _ToastyEntrance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible) {
      _controller.forward(from: 0);
    } else if (!widget.visible && oldWidget.visible && !_controller.isCompleted) {
      _controller.animateTo(1, duration: const Duration(milliseconds: 260), curve: Curves.easeInCubic);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final portraitWidth = (screenWidth * .34).clamp(150.0, 225.0).toDouble();
    final labelWidth = (screenWidth * .25).clamp(88.0, 145.0).toDouble();
    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: EdgeInsets.only(bottom: screenWidth < 600 ? 72 : 76),
        child: SlideTransition(
          position: _slide,
          child: FadeTransition(
            opacity: _opacity,
            child: ScaleTransition(
              scale: _scale,
              alignment: Alignment.bottomRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  ScaleTransition(
                    scale: _textScale,
                    alignment: Alignment.bottomRight,
                    child: Transform.rotate(
                      angle: -.07,
                      child: SizedBox(
                        width: labelWidth,
                        child: FittedBox(
                          fit: BoxFit.contain,
                          child: Text(
                            'TOASTY!',
                            style: TextStyle(
                              color: const Color(0xffffd84a),
                              fontSize: 38,
                              fontWeight: FontWeight.w900,
                              fontStyle: FontStyle.italic,
                              letterSpacing: -1.5,
                              shadows: const <Shadow>[
                                Shadow(color: Colors.black, offset: Offset(3, 3), blurRadius: 1),
                                Shadow(color: Color(0xffd12b12), offset: Offset(-1, -1), blurRadius: 0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Image.asset('assets/images/toasty_face_cutout.png', width: portraitWidth),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
