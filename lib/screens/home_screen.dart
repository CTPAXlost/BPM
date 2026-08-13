import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/vpn_core.dart';
import '../models/vpn_node.dart';
import '../services/app_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/aurora_background.dart';
import '../widgets/status_orb.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppController>(
      builder: (context, controller, _) {
        final selected = controller.selectedNode;
        return AuroraBackground(
          child: SafeArea(
            bottom: false,
            child: RefreshIndicator(
              onRefresh: controller.refreshCatalog,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 100),
                children: <Widget>[
                  _Header(controller: controller),
                  const SizedBox(height: 18),
                  _ConnectionCard(controller: controller, node: selected),
                  const SizedBox(height: 16),
                  _ModeCard(controller: controller),
                  const SizedBox(height: 16),
                  _CatalogSummary(controller: controller),
                  const SizedBox(height: 16),
                  _TrafficCard(controller: controller),
                  const SizedBox(height: 16),
                  const _HonestTestNote(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Image.asset('assets/images/logo_mark.png', width: 44, height: 44),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Поколение VPN',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
              Text(
                'Android · стабильная основа',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          tooltip: 'Обновить каталог',
          onPressed: controller.refreshing ? null : controller.refreshCatalog,
          icon: controller.refreshing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.sync_rounded),
        ),
      ],
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({required this.controller, required this.node});

  final AppController controller;
  final VpnNode? node;

  @override
  Widget build(BuildContext context) {
    final stateText = switch (controller.coreState) {
      VpnCoreState.connected => 'VPN подключён',
      VpnCoreState.connecting || VpnCoreState.preparing => 'Подключение…',
      VpnCoreState.disconnecting => 'Отключение…',
      VpnCoreState.error => 'Ошибка VPN',
      VpnCoreState.disconnected => 'VPN отключён',
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 20),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: controller.connected
              ? AppColors.mint.withValues(alpha: 0.55)
              : AppColors.border,
        ),
      ),
      child: Column(
        children: <Widget>[
          Text(
            stateText,
            style: TextStyle(
              color: controller.connected ? AppColors.mint : AppColors.textMuted,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 18),
          StatusOrb(
            state: controller.coreState,
            onTap: controller.connectOrDisconnect,
          ),
          const SizedBox(height: 20),
          Text(
            node?.name ?? 'Сервер не выбран',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            node == null
                ? 'Открой «Серверы» или включи автоматический выбор'
                : '${node!.flag} ${node!.protocol.label} · ${node!.countryName.isEmpty ? node!.host : node!.countryName}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textMuted),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: controller.busy ? null : controller.connectOrDisconnect,
              icon: Icon(
                controller.connected
                    ? Icons.stop_rounded
                    : Icons.power_settings_new_rounded,
              ),
              label: Text(controller.connected ? 'Отключить' : 'Подключить'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final auto = controller.settings.autoSelectBest;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('Режим выбора', style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          SegmentedButton<bool>(
            segments: const <ButtonSegment<bool>>[
              ButtonSegment<bool>(
                value: true,
                icon: Icon(Icons.auto_awesome_rounded),
                label: Text('Авто'),
              ),
              ButtonSegment<bool>(
                value: false,
                icon: Icon(Icons.touch_app_rounded),
                label: Text('Вручную'),
              ),
            ],
            selected: <bool>{auto},
            onSelectionChanged: (value) {
              controller.updateSettings(
                controller.settings.copyWith(autoSelectBest: value.first),
              );
            },
          ),
          const SizedBox(height: 10),
          Text(
            auto
                ? 'При подключении выбирается лучший из профилей, ответивших на URL Test. Это предварительный отбор, а не скрытое подключение.'
                : 'Подключается только сервер, который выбран тобой в списке.',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _CatalogSummary extends StatelessWidget {
  const _CatalogSummary({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  'Каталог',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                controller.lastRefresh == null
                    ? 'ещё не обновлялся'
                    : _formatAge(controller.lastRefresh!),
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: _Metric(
                  value: '${controller.regularNodes.length}',
                  label: 'серверов',
                  icon: Icons.dns_rounded,
                ),
              ),
              Expanded(
                child: _Metric(
                  value: '${controller.workingCount}',
                  label: 'URL Test OK',
                  icon: Icons.check_circle_rounded,
                ),
              ),
              Expanded(
                child: _Metric(
                  value: '${controller.warpNodes.length}',
                  label: 'WARP',
                  icon: Icons.bolt_rounded,
                ),
              ),
            ],
          ),
          if (controller.testingAll) ...<Widget>[
            const SizedBox(height: 14),
            LinearProgressIndicator(
              value: controller.testingTotal == 0
                  ? null
                  : controller.testingCompleted / controller.testingTotal,
            ),
            const SizedBox(height: 6),
            Text(
              'URL Test: ${controller.testingCompleted} из ${controller.testingTotal}',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  static String _formatAge(DateTime value) {
    final minutes = DateTime.now().difference(value).inMinutes;
    if (minutes < 1) return 'только что';
    if (minutes < 60) return '$minutes мин назад';
    final hours = minutes ~/ 60;
    if (hours < 24) return '$hours ч назад';
    return '${hours ~/ 24} дн назад';
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label, required this.icon});

  final String value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Icon(icon, color: AppColors.cyan, size: 20),
        const SizedBox(height: 5),
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
      ],
    );
  }
}

class _TrafficCard extends StatelessWidget {
  const _TrafficCard({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _TrafficValue(
              icon: Icons.arrow_downward_rounded,
              label: 'Скачивание',
              value: _formatRate(controller.traffic.downloadSpeed),
            ),
          ),
          const SizedBox(height: 44, child: VerticalDivider()),
          Expanded(
            child: _TrafficValue(
              icon: Icons.arrow_upward_rounded,
              label: 'Отдача',
              value: _formatRate(controller.traffic.uploadSpeed),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatRate(int bytes) {
    if (bytes >= 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} МБ/с';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} КБ/с';
    return '$bytes Б/с';
  }
}

class _TrafficValue extends StatelessWidget {
  const _TrafficValue({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Icon(icon, color: AppColors.cyan),
        const SizedBox(height: 5),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
        Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
      ],
    );
  }
}

class _HonestTestNote extends StatelessWidget {
  const _HonestTestNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.cyan.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cyan.withValues(alpha: 0.25)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline_rounded, color: AppColors.cyan),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'URL Test и подключение разделены. URL Test не запрашивает VPN-разрешение и не включает системный туннель. Полный доступ в интернет подтверждается только после твоего нажатия «Подключить».',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
