import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/studio_controller.dart';
import '../theme/studio_theme.dart';
import '../utils/music_theory.dart';
import '../widgets/empty_state.dart';
import 'studio_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<StudioController>().refreshRecent();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<StudioController>();
    final fmt = DateFormat.MMMd().add_jm();

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.graphic_eq_rounded, color: StudioColors.accent2),
            SizedBox(width: 8),
            Text('LayerStudio'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Import project',
            onPressed: () => _importProject(context),
            icon: const Icon(Icons.file_upload_outlined),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => c.refreshRecent(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _newProject(context),
        icon: const Icon(Icons.add),
        label: const Text('New Project'),
      ),
      body: Column(
        children: [
          if (!c.exportBannerDismissed)
            MaterialBanner(
              content: const Text(
                'Export your .layerstudio project so you do not lose work if you reinstall or switch phones.',
              ),
              leading: const Icon(Icons.folder_zip_outlined),
              actions: [
                TextButton(
                  onPressed: () => c.dismissExportBanner(),
                  child: const Text('Got it'),
                ),
              ],
            ),
          Expanded(
            child: c.recent.isEmpty
                ? EmptyState(
                    icon: Icons.library_music_outlined,
                    title: 'Make your first beat',
                    subtitle:
                        'Beat-maker first: pick a tempo, program drums, layer bass/keys, mix, and export.',
                    actionLabel: 'New Project',
                    onAction: () => _newProject(context),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    itemCount: c.recent.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final p = c.recent[i];
                      return Dismissible(
                        key: ValueKey(p.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          decoration: BoxDecoration(
                            color: StudioColors.danger.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.delete,
                            color: StudioColors.danger,
                          ),
                        ),
                        confirmDismiss: (_) async {
                          return await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Delete project?'),
                                  content: Text(
                                    'Delete "${p.name}" permanently?',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child: const Text('Cancel'),
                                    ),
                                    FilledButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Delete'),
                                    ),
                                  ],
                                ),
                              ) ??
                              false;
                        },
                        onDismissed: (_) => c.deleteProject(p.id),
                        child: Card(
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            title: Text(
                              p.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              '${p.bpm} BPM · ${p.key} ${p.scale} · '
                              '${p.tracks.length} tracks · ${fmt.format(p.updatedAt.toLocal())}',
                              style: const TextStyle(
                                color: StudioColors.textDim,
                              ),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () async {
                              await c.openProject(p);
                              if (context.mounted) {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const StudioScreen(),
                                  ),
                                );
                              }
                            },
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

  Future<void> _importProject(BuildContext context) async {
    final c = context.read<StudioController>();
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['layerstudio', 'zip'],
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.single;
      final bytes = picked.bytes;
      final path = picked.path;
      String? err;
      if (bytes != null && bytes.isNotEmpty) {
        err = await c.importProjectBytes(bytes);
      } else if (path != null) {
        err = await c.importProjectFile(File(path));
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not read selected file')),
          );
        }
        return;
      }
      if (!context.mounted) return;
      if (err != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Import failed: $err')));
        return;
      }
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const StudioScreen()));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Import failed: $e')));
      }
    }
  }

  Future<void> _newProject(BuildContext context) async {
    final nameCtrl = TextEditingController(
      text: 'Song ${DateTime.now().month}/${DateTime.now().day}',
    );
    var bpm = 120;
    var key = 'C';
    var scale = 'major';
    var bars = 4;

    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: StudioColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'New Project',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('BPM: $bpm'),
                  Slider(
                    min: 60,
                    max: 180,
                    divisions: 120,
                    value: bpm.toDouble(),
                    onChanged: (v) => setModal(() => bpm = v.round()),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Key',
                            border: OutlineInputBorder(),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              value: key,
                              items: MusicTheory.pitchNames
                                  .map(
                                    (k) => DropdownMenuItem(
                                      value: k,
                                      child: Text(k),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) => setModal(() => key = v ?? 'C'),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Scale',
                            border: OutlineInputBorder(),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              value: scale,
                              items: const [
                                DropdownMenuItem(
                                  value: 'major',
                                  child: Text('Major'),
                                ),
                                DropdownMenuItem(
                                  value: 'minor',
                                  child: Text('Minor'),
                                ),
                              ],
                              onChanged: (v) =>
                                  setModal(() => scale = v ?? 'major'),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('Bars: $bars'),
                  Slider(
                    min: 2,
                    max: 16,
                    divisions: 14,
                    value: bars.toDouble(),
                    onChanged: (v) => setModal(() => bars = v.round()),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Create'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (created == true && context.mounted) {
      final c = context.read<StudioController>();
      await c.createProject(
        name: nameCtrl.text.trim().isEmpty ? 'Untitled' : nameCtrl.text.trim(),
        bpm: bpm,
        key: key,
        scale: scale,
        bars: bars,
      );
      nameCtrl.dispose();
      if (context.mounted) {
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const StudioScreen()));
      }
    } else {
      nameCtrl.dispose();
    }
  }
}
