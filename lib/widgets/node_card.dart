import 'package:flutter/material.dart';
import '../models/vpn_node.dart';
import '../theme/app_theme.dart';

class NodeCard extends StatelessWidget {
  const NodeCard({required this.node, required this.selected, required this.onSelect, required this.onConnect, required this.onTest, required this.onFavorite, required this.onDelete, super.key});
  final VpnNode node; final bool selected; final VoidCallback onSelect; final VoidCallback? onConnect; final VoidCallback? onTest; final VoidCallback onFavorite; final VoidCallback onDelete;
  @override Widget build(BuildContext context) {
    final checking = node.health == NodeHealth.checking;
    final status = node.health == NodeHealth.online ? 'Работает · ${node.latencyMs ?? 0} мс' : checking ? 'Проверяется реальным туннелем…' : 'Не проверен';
    return Card(
      color: selected ? AppColors.cyan.withValues(alpha: .12) : null,
      child: InkWell(onTap: onSelect, borderRadius: BorderRadius.circular(24), child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Row(children: <Widget>[
            const Icon(Icons.bolt, color: AppColors.cyan), const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[Text(node.name, style: const TextStyle(fontWeight: FontWeight.w900)), Text('${node.host}:${node.port}', overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textMuted, fontSize: 12))])),
            IconButton(onPressed: onFavorite, icon: Icon(node.isFavorite ? Icons.star : Icons.star_border, color: node.isFavorite ? Colors.amber : null)),
            IconButton(onPressed: onDelete, icon: const Icon(Icons.delete_outline)),
          ]),
          const SizedBox(height: 8),
          Row(children: <Widget>[
            if (checking) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) else Icon(node.health == NodeHealth.online ? Icons.check_circle : Icons.help_outline, size: 17, color: node.health == NodeHealth.online ? AppColors.mint : AppColors.textMuted),
            const SizedBox(width: 7), Expanded(child: Text(status, style: const TextStyle(color: AppColors.textMuted))),
          ]),
          const SizedBox(height: 12),
          Row(children: <Widget>[
            Expanded(child: OutlinedButton.icon(onPressed: onTest, icon: const Icon(Icons.fact_check_outlined), label: const Text('Проверить'))),
            const SizedBox(width: 8),
            Expanded(child: FilledButton.icon(onPressed: onConnect, icon: const Icon(Icons.power_settings_new), label: const Text('Подключить'))),
          ]),
        ]),
      )),
    );
  }
}
