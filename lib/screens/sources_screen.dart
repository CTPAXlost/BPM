import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/source_definition.dart';
import '../services/app_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/aurora_background.dart';

class SourcesScreen extends StatelessWidget {
  const SourcesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppController>(
      builder: (context, controller, _) {
        return AuroraBackground(
          child: SafeArea(
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text('Источники', style: Theme.of(context).textTheme.headlineMedium),
                            const Text(
                              'Подписки обновляются автоматически и не заменяют последний рабочий каталог пустым.',
                              style: TextStyle(color: AppColors.textMuted),
                            ),
                          ],
                        ),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Добавить источник',
                        onPressed: () => _addSource(context, controller),
                        icon: const Icon(Icons.add_rounded),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: controller.refreshing ? null : controller.refreshCatalog,
                      icon: controller.refreshing
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.sync_rounded),
                      label: const Text('Обновить все источники сейчас'),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                    itemCount: controller.sources.length,
                    itemBuilder: (context, index) {
                      final source = controller.sources[index];
                      return _SourceCard(
                        source: source,
                        onToggle: () => controller.toggleSource(source),
                        onDelete: () => _deleteSource(context, controller, source),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _addSource(BuildContext context, AppController controller) async {
    final name = TextEditingController();
    final url = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Новый источник'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Название')),
              const SizedBox(height: 12),
              TextField(
                controller: url,
                decoration: const InputDecoration(labelText: 'HTTPS-ссылка на подписку или raw-файл'),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(
            onPressed: () async {
              final parsed = Uri.tryParse(url.text.trim());
              if (parsed == null || parsed.scheme != 'https' || parsed.host.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Нужна корректная HTTPS-ссылка.')),
                );
                return;
              }
              await controller.addSource(name.text, url.text);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
    name.dispose();
    url.dispose();
  }

  Future<void> _deleteSource(
    BuildContext context,
    AppController controller,
    SourceDefinition source,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить источник?'),
        content: Text(source.name),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (confirmed == true) await controller.removeSource(source);
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.source,
    required this.onToggle,
    required this.onDelete,
  });

  final SourceDefinition source;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: source.enabled ? AppColors.cyan.withValues(alpha: 0.45) : AppColors.border),
      ),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            backgroundColor: source.enabled ? AppColors.cyan.withValues(alpha: 0.12) : AppColors.surfaceStrong,
            child: Icon(source.type == 'v2nodes_seed' ? Icons.language_rounded : Icons.code_rounded, color: source.enabled ? AppColors.cyan : AppColors.textMuted),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(source.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(source.url, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ],
            ),
          ),
          Switch(value: source.enabled, onChanged: (_) => onToggle()),
          IconButton(onPressed: onDelete, icon: const Icon(Icons.delete_outline_rounded)),
        ],
      ),
    );
  }
}
