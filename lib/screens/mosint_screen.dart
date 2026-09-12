import 'package:flutter/material.dart';

class MosintScreen extends StatefulWidget {
  const MosintScreen({super.key});

  @override
  State<MosintScreen> createState() => _MosintScreenState();
}

class _MosintScreenState extends State<MosintScreen> {
  final _emailController = TextEditingController();
  bool _hasSearched = false;
  String? _email;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _analyze() {
    final value = _emailController.text.trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid email address to continue.'),
        ),
      );
      return;
    }
    setState(() {
      _email = value;
      _hasSearched = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final domain = _email?.split('@').last;
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          height: 42,
                          width: 42,
                          decoration: BoxDecoration(
                            color: const Color(0xFF111827),
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: const Icon(
                            Icons.radar_rounded,
                            color: Color(0xFF60A5FA),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Mosint',
                          style: TextStyle(
                            color: Color(0xFF111827),
                            fontSize: 25,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.8,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'About safe use',
                          onPressed: () => _showSafetySheet(context),
                          icon: const Icon(Icons.shield_outlined),
                        ),
                      ],
                    ),
                    const SizedBox(height: 29),
                    const Text(
                      'Email intelligence,\nwith clear boundaries.',
                      style: TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 30,
                        height: 1.12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.1,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Inspect an address you own or are authorized to assess. '
                      'Mosint keeps results focused on exposure and configuration.',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 14,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 23),
                    _SearchCard(
                      controller: _emailController,
                      onSubmit: _analyze,
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      'CAPABILITIES',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const _CapabilityTile(
                    icon: Icons.dns_outlined,
                    tint: Color(0xFF2563EB),
                    title: 'Mail configuration',
                    detail:
                        'MX presence, provider signals, SPF & DMARC readiness',
                  ),
                  const SizedBox(height: 10),
                  const _CapabilityTile(
                    icon: Icons.policy_outlined,
                    tint: Color(0xFF7C3AED),
                    title: 'Exposure check',
                    detail: 'Breach notification sources — never credentials',
                  ),
                  const SizedBox(height: 10),
                  const _CapabilityTile(
                    icon: Icons.public_outlined,
                    tint: Color(0xFF059669),
                    title: 'Domain context',
                    detail: 'Registration and public infrastructure signals',
                  ),
                  if (_hasSearched) ...[
                    const SizedBox(height: 27),
                    _ResultsHeader(email: _email!),
                    const SizedBox(height: 10),
                    _ResultCard(
                      status: 'READY',
                      color: const Color(0xFF2563EB),
                      icon: Icons.alternate_email_rounded,
                      title: domain!,
                      detail: 'Email syntax validated · domain extracted',
                    ),
                    const SizedBox(height: 10),
                    const _ResultCard(
                      status: 'CONSENT REQUIRED',
                      color: Color(0xFFF59E0B),
                      icon: Icons.lock_outline_rounded,
                      title: 'External source checks',
                      detail:
                          'Connect approved data sources before any lookup.',
                    ),
                  ],
                  const SizedBox(height: 28),
                  const _PrivacyNote(),
                  const SizedBox(height: 30),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSafetySheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => const Padding(
        padding: EdgeInsets.fromLTRB(24, 4, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Use Mosint responsibly',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 12),
            Text(
              'Only inspect addresses you own or have permission to assess. '
              'Exposure sources should report breach status and remediation '
              'guidance; Mosint is not designed to retrieve, store, or reveal passwords.',
              style: TextStyle(color: Color(0xFF475569), height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchCard extends StatelessWidget {
  const _SearchCard({required this.controller, required this.onSubmit});

  final TextEditingController controller;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(19),
        boxShadow: const [
          BoxShadow(
            color: Color(0x241E3A8A),
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          TextField(
            controller: controller,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => onSubmit(),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              prefixIcon: const Icon(
                Icons.alternate_email_rounded,
                color: Color(0xFF93C5FD),
              ),
              hintText: 'name@company.com',
              hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
              filled: true,
              fillColor: const Color(0xFF1F2937),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onSubmit,
              icon: const Icon(Icons.radar_rounded, size: 18),
              label: const Text('Analyze email'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CapabilityTile extends StatelessWidget {
  const _CapabilityTile({
    required this.icon,
    required this.tint,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final Color tint;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: .11),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: tint),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultsHeader extends StatelessWidget {
  const _ResultsHeader({required this.email});
  final String email;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Text(
        'ANALYSIS',
        style: TextStyle(
          color: Color(0xFF64748B),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
      const Spacer(),
      Text(
        email,
        style: const TextStyle(
          color: Color(0xFF2563EB),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.status,
    required this.color,
    required this.icon,
    required this.title,
    required this.detail,
  });
  final String status;
  final Color color;
  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: const Color(0xFFE2E8F0)),
    ),
    child: Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                status,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .7,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF1E293B),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFEFF6FF),
      borderRadius: BorderRadius.circular(14),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.verified_user_outlined, color: Color(0xFF2563EB), size: 20),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'Built for authorized security research. No passwords, credentials, or private data are collected or displayed.',
            style: TextStyle(
              color: Color(0xFF1E40AF),
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );
}
