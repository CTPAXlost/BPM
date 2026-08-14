import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_settings.dart';
import '../services/app_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/aurora_background.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppController>(
      builder: (context, controller, _) {
        final settings = controller.settings;
        return AuroraBackground(
          child: SafeArea(
            bottom: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
              children: <Widget>[
                Text(
                  'Настройки',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 5),
                const Text(
                  'Только функции Android, которые действительно используются.',
                  style: TextStyle(color: AppColors.textMuted),
                ),
                const SizedBox(height: 16),
                _Section(
                  title: 'Оформление',
                  icon: Icons.palette_outlined,
                  children: <Widget>[
                    _VisualThemeSetting(
                      value: settings.visualTheme,
                      onChanged: (value) => controller.updateSettings(
                        settings.copyWith(visualTheme: value),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _Section(
                  title: 'Каталог и автообновление',
                  icon: Icons.sync_rounded,
                  children: <Widget>[
                    _SwitchSetting(
                      title: 'Автообновление ключей',
                      subtitle: 'Обновляет включённые источники в фоне.',
                      value: settings.autoRefresh,
                      onChanged: (value) => controller.updateSettings(
                        settings.copyWith(autoRefresh: value),
                      ),
                    ),
                    _SwitchSetting(
                      title: 'Обновлять при возврате',
                      subtitle:
                          'Проверяет срок каталога после открытия приложения.',
                      value: settings.refreshOnResume,
                      onChanged: (value) => controller.updateSettings(
                        settings.copyWith(refreshOnResume: value),
                      ),
                    ),
                    _SwitchSetting(
                      title: 'Пауза во время VPN',
                      subtitle: 'Не обновляет каталог при активном соединении.',
                      value: settings.pauseRefreshWhileConnected,
                      onChanged: (value) => controller.updateSettings(
                        settings.copyWith(pauseRefreshWhileConnected: value),
                      ),
                    ),
                    _ChoiceSetting(
                      title: 'Интервал обновления',
                      value: settings.refreshMinutes,
                      values: const <int>[15, 30, 60, 120, 360, 720, 1440],
                      label: (value) => value < 60
                          ? '$value мин.'
                          : value == 60
                          ? '1 час'
                          : value < 1440
                          ? '${value ~/ 60} ч.'
                          : '1 день',
                      onChanged: (value) => controller.updateSettings(
                        settings.copyWith(refreshMinutes: value),
                      ),
                    ),
                    _ChoiceSetting(
                      title: 'Лимит на протокол',
                      value: settings.maxPerProtocol,
                      values: const <int>[25, 50, 100, 150, 250],
                      label: (value) => '$value профилей',
                      onChanged: (value) => controller.updateSettings(
                        settings.copyWith(maxPerProtocol: value),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _Section(
                  title: 'Раздельное туннелирование',
                  icon: Icons.call_split_rounded,
                  children: <Widget>[
                    _SplitModeSetting(
                      value: settings.splitTunnelMode,
                      onChanged: (value) => controller.updateSettings(
                        settings.copyWith(splitTunnelMode: value),
                      ),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Приложения'),
                      subtitle: Text(
                        settings.splitTunnelPackages.isEmpty
                            ? 'Список пуст'
                            : settings.splitTunnelPackages.join(', '),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.edit_rounded),
                      onTap: () =>
                          _editSplitPackages(context, controller, settings),
                    ),
                    const _InfoLine(
                      text:
                          'Режим применяется одинаково к sing-box и WARP. '
                          'Указываются Android package ID, например org.telegram.messenger.',
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _Section(
                  title: 'Проверка подключения',
                  icon: Icons.speed_rounded,
                  children: <Widget>[
                    const _InfoLine(
                      text:
                          'Проверка временно поднимает Android VPN и требует '
                          'успешный HTTPS через туннель. Выполняется строго '
                          'по одному серверу.',
                    ),
                    _ChoiceSetting(
                      title: 'Тайм-аут',
                      value: settings.urlTestTimeoutMs,
                      values: const <int>[12000, 15000, 20000, 30000, 45000],
                      label: (value) => '${value ~/ 1000} сек.',
                      onChanged: (value) => controller.updateSettings(
                        settings.copyWith(urlTestTimeoutMs: value),
                      ),
                    ),
                    _SwitchSetting(
                      title: 'Удалять не прошедшие проверку',
                      subtitle:
                          'Только после ручного полного подключения и провала HTTPS через VPN.',
                      value: settings.autoRemoveUnavailable,
                      onChanged: (value) => controller.updateSettings(
                        settings.copyWith(autoRemoveUnavailable: value),
                      ),
                    ),
                    _ChoiceSetting(
                      title: 'Карантин удалённого профиля',
                      value: settings.quarantineHours,
                      values: const <int>[6, 12, 24, 48, 72, 168],
                      label: (value) => value == 168 ? '7 дней' : '$value ч.',
                      onChanged: (value) => controller.updateSettings(
                        settings.copyWith(quarantineHours: value),
                      ),
                    ),
                    _SwitchSetting(
                      title: 'Скрывать не прошедшие проверку',
                      subtitle:
                          'Оставляет их в каталоге, но убирает из списка.',
                      value: settings.hideOffline,
                      onChanged: (value) => controller.updateSettings(
                        settings.copyWith(hideOffline: value),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _Section(
                  title: 'Выбор и подключение',
                  icon: Icons.alt_route_rounded,
                  children: <Widget>[
                    _SwitchSetting(
                      title: 'Автовыбор лучшего',
                      subtitle:
                          'Берёт лучший из профилей, передавших HTTPS через VPN.',
                      value: settings.autoSelectBest,
                      onChanged: (value) => controller.updateSettings(
                        settings.copyWith(autoSelectBest: value),
                      ),
                    ),
                    _SwitchSetting(
                      title: 'Предпочитать белые списки',
                      subtitle:
                          'Даёт специальным профилям приоритет при сортировке.',
                      value: settings.preferWhitelist,
                      onChanged: (value) => controller.updateSettings(
                        settings.copyWith(preferWhitelist: value),
                      ),
                    ),
                    _SwitchSetting(
                      title: 'Строгая маршрутизация',
                      subtitle: 'Снижает риск обхода трафика мимо VPN.',
                      value: settings.strictRoute,
                      onChanged: (value) => controller.updateSettings(
                        settings.copyWith(strictRoute: value),
                      ),
                    ),
                    _SwitchSetting(
                      title: 'Локальная сеть напрямую',
                      subtitle:
                          'Роутер и домашние устройства остаются доступными.',
                      value: settings.bypassLan,
                      onChanged: (value) => controller.updateSettings(
                        settings.copyWith(bypassLan: value),
                      ),
                    ),
                    _SwitchSetting(
                      title: 'Автоподбор MTU',
                      subtitle:
                          'Используется ядром sing-box; ручное значение запасное.',
                      value: settings.adaptiveMtu,
                      onChanged: (value) => controller.updateSettings(
                        settings.copyWith(adaptiveMtu: value),
                      ),
                    ),
                    _ChoiceSetting(
                      title: 'MTU',
                      value: settings.mtu,
                      values: const <int>[
                        1180,
                        1200,
                        1240,
                        1280,
                        1320,
                        1360,
                        1400,
                      ],
                      label: (value) => '$value',
                      onChanged: (value) => controller.updateSettings(
                        settings.copyWith(mtu: value),
                      ),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('DNS'),
                      subtitle: Text(settings.dns),
                      trailing: const Icon(Icons.edit_rounded),
                      onTap: () => _editDns(context, controller, settings),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const _AboutCard(),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _editDns(
    BuildContext context,
    AppController controller,
    AppSettings settings,
  ) async {
    final field = TextEditingController(text: settings.dns);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('DNS-сервер'),
        content: TextField(
          controller: field,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'https://1.1.1.1/dns-query',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, field.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    field.dispose();
    if (result != null && result.isNotEmpty) {
      await controller.updateSettings(settings.copyWith(dns: result));
    }
  }

  Future<void> _editSplitPackages(
    BuildContext context,
    AppController controller,
    AppSettings settings,
  ) async {
    final field = TextEditingController(
      text: settings.splitTunnelPackages.join('\n'),
    );
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Android package ID'),
        content: TextField(
          controller: field,
          minLines: 5,
          maxLines: 10,
          autocorrect: false,
          decoration: const InputDecoration(
            hintText: 'org.telegram.messenger\ncom.whatsapp',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, field.text),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    field.dispose();
    if (result == null) return;
    final packages =
        result
            .split(RegExp(r'[,;\s]+'))
            .map((value) => value.trim())
            .where(
              (value) => RegExp(
                r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$',
              ).hasMatch(value),
            )
            .toSet()
            .toList()
          ..sort();
    await controller.updateSettings(
      settings.copyWith(splitTunnelPackages: packages),
    );
  }
}

class _SplitModeSetting extends StatelessWidget {
  const _SplitModeSetting({required this.value, required this.onChanged});

  final SplitTunnelMode value;
  final ValueChanged<SplitTunnelMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Режим приложений'),
      trailing: DropdownButton<SplitTunnelMode>(
        value: value,
        items: const <DropdownMenuItem<SplitTunnelMode>>[
          DropdownMenuItem(
            value: SplitTunnelMode.off,
            child: Text('Выключено'),
          ),
          DropdownMenuItem(
            value: SplitTunnelMode.include,
            child: Text('Только выбранные'),
          ),
          DropdownMenuItem(
            value: SplitTunnelMode.exclude,
            child: Text('Кроме выбранных'),
          ),
        ],
        onChanged: (item) {
          if (item != null) onChanged(item);
        },
      ),
    );
  }
}

class _VisualThemeSetting extends StatelessWidget {
  const _VisualThemeSetting({required this.value, required this.onChanged});

  final VisualTheme value;
  final ValueChanged<VisualTheme> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SegmentedButton<VisualTheme>(
        segments: const <ButtonSegment<VisualTheme>>[
          ButtonSegment<VisualTheme>(
            value: VisualTheme.nightmare,
            icon: Icon(Icons.local_fire_department_outlined),
            label: Text('Кошмар'),
          ),
          ButtonSegment<VisualTheme>(
            value: VisualTheme.symbiosis,
            icon: Icon(Icons.bolt_outlined),
            label: Text('Симбиоз'),
          ),
        ],
        selected: <VisualTheme>{value},
        onSelectionChanged: (values) => onChanged(values.first),
        showSelectedIcon: true,
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

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
              Icon(icon, color: AppColors.cyan),
              const SizedBox(width: 9),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _SwitchSetting extends StatelessWidget {
  const _SwitchSetting({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _ChoiceSetting extends StatelessWidget {
  const _ChoiceSetting({
    required this.title,
    required this.value,
    required this.values,
    required this.label,
    required this.onChanged,
  });

  final String title;
  final int value;
  final List<int> values;
  final String Function(int value) label;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final effectiveValue = values.contains(value) ? value : values.first;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      trailing: DropdownButton<int>(
        value: effectiveValue,
        items: <DropdownMenuItem<int>>[
          for (final item in values)
            DropdownMenuItem<int>(value: item, child: Text(label(item))),
        ],
        onChanged: (item) {
          if (item != null) onChanged(item);
        },
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cyan.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.info_outline_rounded,
            color: AppColors.cyan,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: const ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.android_rounded, color: AppColors.mint),
        title: Text('Поколение VPN 0.9.5'),
        subtitle: Text(
          'Android-клиент с WARP, реальной проверкой VPN-подключения, '
          'автообновлением каталогов и split tunneling.',
        ),
      ),
    );
  }
}
