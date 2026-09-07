import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/sound_library.dart';
import '../models/track.dart';
import '../services/studio_controller.dart';
import '../theme/studio_theme.dart';

class SoundLibraryScreen extends StatelessWidget {
  const SoundLibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<StudioController>();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const Text(
          'Sound Library',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        const Text(
          'Preview a tone, then Add Track to layer it in your song. Import your own WAV samples.',
          style: TextStyle(color: StudioColors.textDim),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final cat in [
              TrackCategory.drums,
              TrackCategory.bass,
              TrackCategory.keys,
              TrackCategory.guitar,
            ])
              OutlinedButton.icon(
                onPressed: () => _importSample(context, c, cat),
                icon: const Icon(Icons.file_upload_outlined, size: 18),
                label: Text('Import ${cat.shortLabel} WAV'),
              ),
          ],
        ),
        const SizedBox(height: 16),
        for (final cat in TrackCategory.values) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 8),
            child: Text(
              cat == TrackCategory.mic ? 'MIC' : cat.name.toUpperCase(),
              style: const TextStyle(
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
                color: StudioColors.accent2,
              ),
            ),
          ),
          if (cat == TrackCategory.mic)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text(
                'Mic tracks are added from Arrange. Arm, then Play to punch in from the playhead.',
                style: TextStyle(color: StudioColors.textDim, fontSize: 13),
              ),
            ),
          ...SoundLibrary.byCategory(cat).map((preset) {
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: Color(preset.colorValue),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            preset.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        if (preset.id.startsWith('user_'))
                          const Text(
                            'YOURS',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: StudioColors.accent2,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      preset.description,
                      style: const TextStyle(
                        color: StudioColors.textDim,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => c.previewPreset(preset),
                          icon: const Icon(Icons.hearing),
                          label: const Text('Preview'),
                        ),
                        const SizedBox(width: 10),
                        FilledButton.icon(
                          onPressed: () async {
                            await c.addTrackFromPreset(preset);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Added “${preset.name}”'),
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Add Track'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ],
    );
  }

  Future<void> _importSample(
    BuildContext context,
    StudioController c,
    TrackCategory category,
  ) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['wav'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not read WAV bytes')),
          );
        }
        return;
      }
      final preset = await c.importUserSample(
        bytes: bytes,
        originalName: file.name,
        category: category,
      );
      if (!context.mounted) return;
      if (preset == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Import failed')),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported “${preset.name}”')),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e')),
        );
      }
    }
  }
}
