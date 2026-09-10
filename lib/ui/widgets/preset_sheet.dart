import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../ble/storm_service.dart';
import '../../model/app_settings.dart';
import '../../model/preset.dart';
import '../../model/preset_repository.dart';

/// Modal bottom sheet displaying available presets, allowing fast switching,
/// saving the current setup, and syncing with the ESP32 hardware.
class PresetSheet extends StatelessWidget {
  const PresetSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repo = context.watch<PresetRepository>();
    final storm = context.watch<StormService>();
    final settings = context.watch<AppSettings>();
    final presets = repo.presets;
    final activeId = repo.activePresetId;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.82,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Lighting Presets',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Switch or capture lighting, colors, and audio tuning',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _showSavePresetDialog(context, repo, storm, settings),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Save Current'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Presets list
          Flexible(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: presets.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final preset = presets[index];
                final isActive = preset.id == activeId;

                return _PresetCard(
                  preset: preset,
                  isActive: isActive,
                  onSelect: () async {
                    await repo.applyPreset(preset, storm, settings);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Applied "${preset.name}"'),
                          duration: const Duration(seconds: 1),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                  onDelete: preset.isBuiltIn
                      ? null
                      : () => _confirmDelete(context, repo, preset),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showSavePresetDialog(
    BuildContext context,
    PresetRepository repo,
    StormService storm,
    AppSettings settings,
  ) {
    final nameController = TextEditingController();
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Save Current Preset'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Captures all current firmware tuning sliders, bolt & cloud colours, and audio delay.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Preset Name',
                hintText: 'e.g. Midnight Lightning',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                hintText: 'e.g. Dim warm glow with fast strikes',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              Navigator.of(dialogCtx).pop();

              final created = await repo.saveCurrentState(
                name: name,
                description: descController.text.trim(),
                stormService: storm,
                appSettings: settings,
              );

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Saved "${created.name}" preset'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, PresetRepository repo, Preset preset) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Delete "${preset.name}"?'),
        content: const Text('This custom preset will be permanently removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () async {
              Navigator.of(dialogCtx).pop();
              await repo.deletePreset(preset.id);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.preset,
    required this.isActive,
    required this.onSelect,
    this.onDelete,
  });

  final Preset preset;
  final bool isActive;
  final VoidCallback onSelect;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      color: isActive
          ? scheme.primaryContainer.withValues(alpha: 0.25)
          : scheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isActive ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.3),
          width: isActive ? 1.5 : 1.0,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onSelect,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Swatches: bolt and tint
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 12),
                child: Column(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: preset.boltColor.toColor(),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white24, width: 1),
                      ),
                      child: const Center(
                        child: Icon(Icons.bolt, size: 14, color: Colors.black87),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: preset.cloudTint.toColor(),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white24, width: 1),
                      ),
                      child: const Center(
                        child: Icon(Icons.cloud, size: 14, color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              ),
              // Name and details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            preset.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                              color: isActive ? scheme.primary : scheme.onSurface,
                            ),
                          ),
                        ),
                        if (preset.isBuiltIn) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Built-in',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                        if (isActive) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.check_circle, size: 16, color: scheme.primary),
                        ],
                      ],
                    ),
                    if (preset.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        preset.description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      'bri: ${preset.parameters['bri'] ?? '-'}  •  '
                      'sheet: ${preset.parameters['sheet_ratio'] ?? '-'}  •  '
                      'audio delay: ${preset.speakerLatencyMs}ms',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              if (onDelete != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  color: scheme.error.withValues(alpha: 0.8),
                  tooltip: 'Delete preset',
                  onPressed: onDelete,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
