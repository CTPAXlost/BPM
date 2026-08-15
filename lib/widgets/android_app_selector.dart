import 'package:flutter/material.dart';

import '../core/amneziawg_bridge.dart';

class AndroidAppSelectorDialog extends StatefulWidget {
  const AndroidAppSelectorDialog({super.key, required this.initialSelection});

  final Set<String> initialSelection;

  @override
  State<AndroidAppSelectorDialog> createState() => _AndroidAppSelectorDialogState();
}

class _AndroidAppSelectorDialogState extends State<AndroidAppSelectorDialog> {
  final _bridge = AmneziaWgBridge();
  final _search = TextEditingController();
  late final Set<String> _selected;
  late final Future<List<InstalledAndroidApp>> _apps;
  bool _showSystem = false;

  @override
  void initState() {
    super.initState();
    _selected = <String>{...widget.initialSelection};
    _apps = _bridge.installedApplications();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Выбор приложений'),
    contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
    content: SizedBox(
      width: 560,
      height: 560,
      child: Column(children: <Widget>[
        TextField(
          controller: _search,
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Название или пакет'),
          onChanged: (_) => setState(() {}),
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Показывать системные'),
          value: _showSystem,
          onChanged: (value) => setState(() => _showSystem = value),
        ),
        Expanded(child: FutureBuilder<List<InstalledAndroidApp>>(
          future: _apps,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            if (snapshot.hasError) return Center(child: Text('Не удалось получить приложения: ${snapshot.error}'));
            final query = _search.text.trim().toLowerCase();
            final apps = (snapshot.data ?? const <InstalledAndroidApp>[]).where((app) {
              if (!_showSystem && app.isSystem) return false;
              return query.isEmpty || app.label.toLowerCase().contains(query) || app.packageName.toLowerCase().contains(query);
            }).toList(growable: false);
            if (apps.isEmpty) return const Center(child: Text('Приложения не найдены'));
            return ListView.builder(
              itemCount: apps.length,
              itemBuilder: (context, index) {
                final app = apps[index];
                final selected = _selected.contains(app.packageName);
                return CheckboxListTile(
                  value: selected,
                  onChanged: (value) => setState(() {
                    if (value == true) _selected.add(app.packageName); else _selected.remove(app.packageName);
                  }),
                  secondary: app.icon == null
                      ? const CircleAvatar(child: Icon(Icons.android))
                      : ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.memory(app.icon!, width: 42, height: 42)),
                  title: Text(app.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(app.packageName, maxLines: 1, overflow: TextOverflow.ellipsis),
                );
              },
            );
          },
        )),
      ]),
    ),
    actions: <Widget>[
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
      FilledButton(onPressed: () => Navigator.pop(context, _selected), child: Text('Сохранить (${_selected.length})')),
    ],
  );
}
