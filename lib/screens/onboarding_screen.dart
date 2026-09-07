import 'package:flutter/material.dart';

import '../theme/studio_theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onDone});

  final Future<void> Function() onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _pages = [
    (
      icon: Icons.grid_on_rounded,
      title: 'Start with the beat',
      body:
          'Pick a drum kit, tap pads or the 16-step grid, and add swing until the groove feels right.',
    ),
    (
      icon: Icons.layers_outlined,
      title: 'Stack layers',
      body:
          'Add bass, keys, or guitar. Import your own WAV samples. Patterns A–D become a song on the arrange timeline.',
    ),
    (
      icon: Icons.tune_rounded,
      title: 'Mix, record, share',
      body:
          'Cue tracks in the mixer, punch-in a mic take, then export WAV or MP3. Lock-screen controls keep the beat going. Nothing leaves the phone unless you share it.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StudioColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Row(
                children: [
                  Icon(Icons.graphic_eq_rounded, color: StudioColors.accent2),
                  SizedBox(width: 8),
                  Text(
                    'LayerStudio',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) {
                  final page = _pages[i];
                  return Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(page.icon, size: 72, color: StudioColors.accent),
                        const SizedBox(height: 24),
                        Text(
                          page.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          page.body,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: StudioColors.textDim,
                            height: 1.45,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _pages.length; i++)
                  Container(
                    width: i == _page ? 18 : 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: i == _page
                          ? StudioColors.accent
                          : StudioColors.border,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: FilledButton(
                onPressed: () async {
                  if (_page < _pages.length - 1) {
                    await _controller.nextPage(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOut,
                    );
                    return;
                  }
                  await widget.onDone();
                },
                child: Text(_page < _pages.length - 1 ? 'Next' : 'Make a beat'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
