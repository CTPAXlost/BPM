import 'package:flutter/material.dart';

import '../core/vpn_core.dart';
import '../theme/app_theme.dart';

class StatusOrb extends StatefulWidget {
  const StatusOrb({
    required this.state,
    required this.onTap,
    super.key,
  });

  final VpnCoreState state;
  final VoidCallback onTap;

  @override
  State<StatusOrb> createState() => _StatusOrbState();
}

class _StatusOrbState extends State<StatusOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connected = widget.state == VpnCoreState.connected;
    final busy = widget.state == VpnCoreState.connecting ||
        widget.state == VpnCoreState.preparing ||
        widget.state == VpnCoreState.disconnecting;
    final color = connected ? AppColors.mint : AppColors.cyan;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final pulse = busy ? 0.75 + (_controller.value * 0.25) : 1.0;
        return Transform.scale(
          scale: pulse,
          child: GestureDetector(
            onTap: widget.onTap,
            child: Container(
              width: 126,
              height: 126,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: <Color>[
                    color.withValues(alpha: connected ? 0.42 : 0.25),
                    AppColors.surfaceStrong,
                  ],
                ),
                border: Border.all(color: color.withValues(alpha: 0.8), width: 2),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: color.withValues(alpha: connected ? 0.35 : 0.2),
                    blurRadius: 40,
                    spreadRadius: 6,
                  ),
                ],
              ),
              child: Icon(
                connected ? Icons.shield_rounded : Icons.power_settings_new_rounded,
                size: 48,
                color: color,
              ),
            ),
          ),
        );
      },
    );
  }
}
