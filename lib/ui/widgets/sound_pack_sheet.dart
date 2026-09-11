import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../audio/sound_pack.dart';
import '../../audio/thunder_player.dart';
import '../theme.dart';

/// Modal bottom sheet allowing users to view, select, and import custom audio packs.
class SoundPackSheet extends StatelessWidget {
  const SoundPackSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final packManager = context.watch<SoundPackManager>();
    final thunder = context.watch<ThunderPlayer>();
    final packs = packManager.packs;
    final activeId = packManager.activePackId;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
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
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 14, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Thunder Sound Packs',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Manage or import custom MP3 / WAV thunder recordings',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _showCreatePackDialog(context, packManager, thunder),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Import Pack'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Pack List
          Flexible(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: packs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final pack = packs[index];
                final isActive = pack.id == activeId;

                return Card(
                  color: isActive
                      ? scheme.primaryContainer.withValues(alpha: 0.25)
                      : scheme.surfaceContainer,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: isActive
                          ? scheme.primary
                          : scheme.outlineVariant.withValues(alpha: 0.3),
                      width: isActive ? 1.5 : 1.0,
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () async {
                      await packManager.setActivePack(pack.id);
                      await thunder.loadPack(pack);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Switched to "${pack.name}"'),
                            behavior: SnackBarBehavior.floating,
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                pack.isBuiltIn
                                    ? Icons.library_music
                                    : Icons.audio_file_outlined,
                                size: 20,
                                color: isActive ? scheme.primary : scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  pack.name,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight:
                                        isActive ? FontWeight.bold : FontWeight.w600,
                                    color: isActive ? scheme.primary : scheme.onSurface,
                                  ),
                                ),
                              ),
                              if (pack.isBuiltIn) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: scheme.surfaceContainerHigh,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'Bundled',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                              if (isActive) ...[
                                const SizedBox(width: 8),
                                Icon(Icons.check_circle, size: 18, color: scheme.primary),
                              ],
                              if (!pack.isBuiltIn)
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 20),
                                  color: scheme.error.withValues(alpha: 0.8),
                                  onPressed: () =>
                                      _confirmDelete(context, packManager, thunder, pack),
                                ),
                            ],
                          ),
                          if (pack.description.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              pack.description,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          // Sample badges
                          Row(
                            children: [
                              _sampleChip(
                                label: 'Close',
                                isCustom: !pack.isAssetFor(ThunderDistance.close),
                                scheme: scheme,
                              ),
                              const SizedBox(width: 6),
                              _sampleChip(
                                label: 'Mid',
                                isCustom: !pack.isAssetFor(ThunderDistance.mid),
                                scheme: scheme,
                              ),
                              const SizedBox(width: 6),
                              _sampleChip(
                                label: 'Far',
                                isCustom: !pack.isAssetFor(ThunderDistance.far),
                                scheme: scheme,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _sampleChip({
    required String label,
    required bool isCustom,
    required ColorScheme scheme,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isCustom
            ? scheme.primary.withValues(alpha: 0.15)
            : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isCustom
              ? scheme.primary.withValues(alpha: 0.4)
              : Colors.transparent,
        ),
      ),
      child: Text(
        '$label: ${isCustom ? "Custom" : "Asset"}',
        style: kMonoStyle.copyWith(
          fontSize: 11,
          color: isCustom ? scheme.primary : scheme.onSurfaceVariant,
          fontWeight: isCustom ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  void _showCreatePackDialog(
    BuildContext context,
    SoundPackManager packManager,
    ThunderPlayer thunder,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => _CreateSoundPackDialog(
        packManager: packManager,
        thunderPlayer: thunder,
      ),
    );
  }

  void _confirmDelete(
    BuildContext context,
    SoundPackManager packManager,
    ThunderPlayer thunder,
    SoundPack pack,
  ) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Delete "${pack.name}"?'),
        content: const Text('This custom sound pack will be removed.'),
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
              await packManager.deletePack(pack.id);
              await thunder.loadPack(packManager.activePack);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _CreateSoundPackDialog extends StatefulWidget {
  const _CreateSoundPackDialog({
    required this.packManager,
    required this.thunderPlayer,
  });

  final SoundPackManager packManager;
  final ThunderPlayer thunderPlayer;

  @override
  State<_CreateSoundPackDialog> createState() => _CreateSoundPackDialogState();
}

class _CreateSoundPackDialogState extends State<_CreateSoundPackDialog> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();

  String? _closeAudioPath;
  String? _midAudioPath;
  String? _farAudioPath;
  bool _importing = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AlertDialog(
      title: const Text('Create Custom Sound Pack'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Pack Name',
                hintText: 'e.g. Alpine Storm Recordings',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                hintText: 'e.g. Real acoustic recordings with rolling echo',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Assign Audio Samples (MP3 / WAV / OGG):',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),

            _fileRow(
              distance: ThunderDistance.close,
              path: _closeAudioPath,
              scheme: scheme,
              onPick: () async {
                final path = await widget.packManager.pickAndImportAudioFile(ThunderDistance.close);
                if (path != null) setState(() => _closeAudioPath = path);
              },
            ),
            const SizedBox(height: 8),
            _fileRow(
              distance: ThunderDistance.mid,
              path: _midAudioPath,
              scheme: scheme,
              onPick: () async {
                final path = await widget.packManager.pickAndImportAudioFile(ThunderDistance.mid);
                if (path != null) setState(() => _midAudioPath = path);
              },
            ),
            const SizedBox(height: 8),
            _fileRow(
              distance: ThunderDistance.far,
              path: _farAudioPath,
              scheme: scheme,
              onPick: () async {
                final path = await widget.packManager.pickAndImportAudioFile(ThunderDistance.far);
                if (path != null) setState(() => _farAudioPath = path);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _importing
              ? null
              : () async {
                  final name = _nameController.text.trim();
                  if (name.isEmpty) return;

                  setState(() => _importing = true);
                  final pack = await widget.packManager.createPack(
                    name: name,
                    description: _descController.text.trim(),
                    closePath: _closeAudioPath,
                    midPath: _midAudioPath,
                    farPath: _farAudioPath,
                  );

                  await widget.thunderPlayer.loadPack(pack);

                  if (context.mounted) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Created & activated "${pack.name}"'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
          child: const Text('Create & Activate'),
        ),
      ],
    );
  }

  Widget _fileRow({
    required ThunderDistance distance,
    required String? path,
    required ColorScheme scheme,
    required VoidCallback onPick,
  }) {
    final fileName = path != null ? path.split(RegExp(r'[\\/]')).last : 'Using bundled asset';
    final hasCustom = path != null && path.isNotEmpty;

    return Row(
      children: [
        SizedBox(
          width: 50,
          child: Text(
            distance.label,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: Text(
            fileName,
            style: kMonoStyle.copyWith(
              fontSize: 11,
              color: hasCustom ? scheme.primary : scheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 6),
        OutlinedButton(
          onPressed: onPick,
          style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
          child: const Text('Browse'),
        ),
      ],
    );
  }
}
