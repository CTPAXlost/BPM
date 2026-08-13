import 'package:flutter/material.dart';

import '../models/vpn_protocol.dart';
import '../theme/app_theme.dart';

class ProtocolStrip extends StatelessWidget {
  const ProtocolStrip({
    required this.selected,
    required this.whitelistSelected,
    required this.favoritesSelected,
    required this.whitelistCount,
    required this.favoriteCount,
    required this.countFor,
    required this.onSelected,
    required this.onWhitelistSelected,
    required this.onFavoritesSelected,
    super.key,
  });

  final VpnProtocol? selected;
  final bool whitelistSelected;
  final bool favoritesSelected;
  final int whitelistCount;
  final int favoriteCount;
  final int Function(VpnProtocol protocol) countFor;
  final ValueChanged<VpnProtocol?> onSelected;
  final ValueChanged<bool> onWhitelistSelected;
  final ValueChanged<bool> onFavoritesSelected;

  @override
  Widget build(BuildContext context) {
    final allSelected = selected == null &&
        !whitelistSelected &&
        !favoritesSelected;
    return SizedBox(
      height: 58,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        scrollDirection: Axis.horizontal,
        children: <Widget>[
          _specialChip(
            context,
            active: whitelistSelected,
            label: 'Белые списки',
            count: whitelistCount,
            icon: Icons.cell_tower_rounded,
            accent: const Color(0xFF8ECAFF),
            tooltip: 'Отдельный каталог CIDR/SNI для ограниченного интернета',
            onTap: () => onWhitelistSelected(!whitelistSelected),
          ),
          _specialChip(
            context,
            active: favoritesSelected,
            label: 'Избранное',
            count: favoriteCount,
            icon: Icons.star_rounded,
            accent: const Color(0xFFFFC857),
            onTap: () => onFavoritesSelected(!favoritesSelected),
          ),
          _protocolChip(
            context,
            protocol: null,
            label: 'Все обычные',
            icon: Icons.grid_view_rounded,
            count: null,
            activeOverride: allSelected,
          ),
          for (final protocol in VpnProtocol.values)
            _protocolChip(
              context,
              protocol: protocol,
              label: protocol.label,
              icon: _icon(protocol),
              count: countFor(protocol),
            ),
        ],
      ),
    );
  }

  Widget _specialChip(
    BuildContext context, {
    required bool active,
    required String label,
    required int count,
    required IconData icon,
    required Color accent,
    required VoidCallback onTap,
    String? tooltip,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Tooltip(
        message: tooltip ?? label,
        child: ChoiceChip(
          selected: active,
          onSelected: (_) => onTap(),
          avatar: Icon(
            icon,
            size: 18,
            color: active ? accent : AppColors.textMuted,
          ),
          label: Text('$label  $count'),
          labelStyle: TextStyle(
            color: active ? Colors.white : AppColors.textMuted,
            fontWeight: FontWeight.w800,
          ),
          backgroundColor: AppColors.surface,
          selectedColor: accent.withValues(alpha: 0.18),
          side: BorderSide(color: active ? accent : AppColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    );
  }

  Widget _protocolChip(
    BuildContext context, {
    required VpnProtocol? protocol,
    required String label,
    required IconData icon,
    required int? count,
    bool? activeOverride,
  }) {
    final active = activeOverride ??
        (selected == protocol && !whitelistSelected && !favoritesSelected);
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: ChoiceChip(
        selected: active,
        onSelected: (_) => onSelected(protocol),
        avatar: Icon(
          icon,
          size: 18,
          color: active ? AppColors.cyan : AppColors.textMuted,
        ),
        label: Text(count == null ? label : '$label  $count'),
        labelStyle: TextStyle(
          color: active ? Colors.white : AppColors.textMuted,
          fontWeight: FontWeight.w700,
        ),
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.cyan.withValues(alpha: 0.16),
        side: BorderSide(color: active ? AppColors.cyan : AppColors.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
    );
  }

  IconData _icon(VpnProtocol protocol) => switch (protocol) {
        VpnProtocol.warp => Icons.public_rounded,
        VpnProtocol.vless => Icons.bolt_rounded,
        VpnProtocol.trojan => Icons.security_rounded,
        VpnProtocol.shadowsocks => Icons.visibility_off_rounded,
        VpnProtocol.vmess => Icons.hub_rounded,
        VpnProtocol.hysteria2 => Icons.speed_rounded,
        VpnProtocol.tuic => Icons.rocket_launch_rounded,
      };
}
