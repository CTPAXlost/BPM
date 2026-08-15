import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_settings.dart';
import '../services/app_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/aurora_background.dart';
import '../widgets/android_app_selector.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override Widget build(BuildContext context) => Consumer<AppController>(builder: (context, controller, _) {
    final s = controller.settings;
    return AuroraBackground(child: SafeArea(bottom: false, child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), children: <Widget>[
      Text('Настройки', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 16),
      _Section('Оформление', <Widget>[
        SegmentedButton<VisualTheme>(segments: const <ButtonSegment<VisualTheme>>[ButtonSegment(value: VisualTheme.nightmare, label: Text('Кошмар')), ButtonSegment(value: VisualTheme.symbiosis, label: Text('Симбиоз'))], selected: <VisualTheme>{s.visualTheme}, onSelectionChanged: (v) => controller.updateSettings(s.copyWith(visualTheme: v.first))),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Лицо и звук при подключении'), subtitle: const Text('Появляются только после успешного запуска туннеля.'), value: s.toastyEnabled, onChanged: (v) => controller.updateSettings(s.copyWith(toastyEnabled: v))),
      ]),
      _Section('Автоматизация', <Widget>[
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Создать WARP, если список пуст'), value: s.autoGenerateWarp, onChanged: (v) => controller.updateSettings(s.copyWith(autoGenerateWarp: v))),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Удалять нерабочие профили'), subtitle: const Text('Только после реальной HTTPS-проверки через туннель.'), value: s.autoRemoveUnavailable, onChanged: (v) => controller.updateSettings(s.copyWith(autoRemoveUnavailable: v))),
      ]),
      _Section(Platform.isWindows ? 'Раздельное туннелирование Windows' : 'Раздельное туннелирование Android', <Widget>[
        DropdownButtonFormField<SplitTunnelMode>(initialValue: s.splitTunnelMode, decoration: const InputDecoration(labelText: 'Режим'), items: const <DropdownMenuItem<SplitTunnelMode>>[
          DropdownMenuItem(value: SplitTunnelMode.off, child: Text('Выключено')),
          DropdownMenuItem(value: SplitTunnelMode.include, child: Text('VPN только для выбранных')),
          DropdownMenuItem(value: SplitTunnelMode.exclude, child: Text('VPN для всех, кроме выбранных')),
        ], onChanged: Platform.isWindows ? null : (v) { if (v != null) controller.updateSettings(s.copyWith(splitTunnelMode: v)); }),
        const SizedBox(height: 10),
        SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: Platform.isWindows ? null : () => _selectApplications(context, controller), icon: const Icon(Icons.apps), label: Text('Выбрать приложения (${s.splitTunnelPackages.length})'))),
        const SizedBox(height: 8),
        Text(
          Platform.isWindows
              ? 'В первой Windows-сборке доступен полный WARP-туннель. Разделение по приложениям заблокировано до интеграции отдельного WFP-драйвера.'
              : 'Выбери установленные приложения из списка. Режим «только для выбранных» передаёт их в IncludedApplications, режим исключения — в ExcludedApplications.',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
      ]),
      _Section('Сеть', <Widget>[
        ListTile(contentPadding: EdgeInsets.zero, title: const Text('MTU'), subtitle: Slider(min: 1180, max: 1500, divisions: 32, value: s.mtu.toDouble(), label: '${s.mtu}', onChanged: (v) => controller.updateSettings(s.copyWith(mtu: v.round()))), trailing: Text('${s.mtu}')),
        ListTile(contentPadding: EdgeInsets.zero, title: const Text('DNS'), subtitle: Text(s.dns), trailing: const Icon(Icons.edit), onTap: () => _editDns(context, controller)),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Локальная сеть мимо VPN'), value: s.bypassLan, onChanged: (v) => controller.updateSettings(s.copyWith(bypassLan: v))),
      ]),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(
        Platform.isWindows
            ? 'Windows использует встроенное официальное AmneziaWG-ядро. Отдельное приложение не устанавливается; UAC нужен только для запуска системной службы туннеля.'
            : 'Android: VPN и раздельное туннелирование работают через нативный AmneziaWG. iOS будет отдельным этапом с Packet Tunnel Extension.',
        style: const TextStyle(color: AppColors.textMuted),
      ))),
    ])));
  });

  Future<void> _selectApplications(BuildContext context, AppController controller) async {
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (_) => AndroidAppSelectorDialog(initialSelection: controller.settings.splitTunnelPackages.toSet()),
    );
    if (result != null) {
      final packages = result.toList(growable: false)..sort();
      await controller.updateSettings(controller.settings.copyWith(splitTunnelPackages: packages));
    }
  }
  Future<void> _editDns(BuildContext context, AppController controller) async {
    final field = TextEditingController(text: controller.settings.dns);
    final result = await showDialog<String>(context: context, builder: (context) => AlertDialog(title: const Text('DNS-сервер'), content: TextField(controller: field), actions: <Widget>[TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')), FilledButton(onPressed: () => Navigator.pop(context, field.text.trim()), child: const Text('Сохранить'))]));
    field.dispose(); if (result != null && result.isNotEmpty) await controller.updateSettings(controller.settings.copyWith(dns: result));
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.children); final String title; final List<Widget> children;
  @override Widget build(BuildContext context) => Card(margin: const EdgeInsets.only(bottom: 12), child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)), const SizedBox(height: 12), ...children])));
}
