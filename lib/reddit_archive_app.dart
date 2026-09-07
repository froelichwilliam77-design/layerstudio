import 'package:flutter/material.dart';

class TraceArchiveApp extends StatelessWidget {
  const TraceArchiveApp({super.key});

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF111827);
    return MaterialApp(
      title: 'Trace Archive',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: ink,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF65D6C2),
          secondary: Color(0xFFA8B5FF),
          surface: Color(0xFF192334),
        ),
        textTheme: ThemeData.dark().textTheme.apply(
          fontFamily: 'Roboto',
          bodyColor: const Color(0xFFF4F7FB),
          displayColor: const Color(0xFFF4F7FB),
        ),
      ),
      home: const ArchiveSearchScreen(),
    );
  }
}

class ArchiveSearchScreen extends StatefulWidget {
  const ArchiveSearchScreen({super.key});

  @override
  State<ArchiveSearchScreen> createState() => _ArchiveSearchScreenState();
}

class _ArchiveSearchScreenState extends State<ArchiveSearchScreen> {
  final _query = TextEditingController(text: 'orbiting_mars');
  String _scope = 'Everything';
  String _type = 'All';
  bool _deletedOnly = false;
  bool _searched = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<ArchiveRecord> get _results {
    var records = _records.where((record) {
      if (_type != 'All' && record.type != _type) return false;
      if (_deletedOnly && !record.removed) return false;
      return true;
    }).toList();
    if (_scope == 'Posts') {
      records = records.where((r) => r.type == 'Post').toList();
    }
    if (_scope == 'Comments') {
      records = records.where((r) => r.type == 'Comment').toList();
    }
    return records;
  }

  void _search() {
    FocusScope.of(context).unfocus();
    setState(() => _searched = true);
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _header()),
            SliverToBoxAdapter(child: _searchPanel()),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 26, 20, 14),
                child: Row(
                  children: [
                    Text(
                      _searched
                          ? '${results.length} matching records'
                          : 'Recent indexed records',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Newest first',
                      style: TextStyle(
                        color: Colors.blueGrey.shade300,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (results.isEmpty)
              const SliverToBoxAdapter(child: _NoResults())
            else
              SliverList.separated(
                itemCount: results.length,
                itemBuilder: (_, index) => _RecordCard(record: results[index]),
                separatorBuilder: (_, __) => const SizedBox(height: 12),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
      bottomNavigationBar: _bottomBar(),
    );
  }

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
    child: Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFF65D6C2).withValues(alpha: .14),
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Icon(
            Icons.travel_explore_rounded,
            color: Color(0xFF65D6C2),
          ),
        ),
        const SizedBox(width: 12),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TRACE',
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2.2),
            ),
            Text(
              'PUBLIC ARCHIVE',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.3,
                color: Color(0xFF91A0B6),
              ),
            ),
          ],
        ),
        const Spacer(),
        IconButton(
          tooltip: 'About archive data',
          icon: const Icon(
            Icons.info_outline_rounded,
            color: Color(0xFFB8C5D9),
          ),
          onPressed: _showAbout,
        ),
      ],
    ),
  );

  Widget _searchPanel() => Container(
    margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF192334),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFF2B3A50)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Search the public record',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 5),
        const Text(
          'Explore public posts and comments preserved by participating archives.',
          style: TextStyle(color: Color(0xFF9DABC0), fontSize: 13),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _query,
          onSubmitted: (_) => _search(),
          decoration: InputDecoration(
            hintText: 'Username, community, or keyword',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _query.text.isNotEmpty
                ? IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => setState(_query.clear),
                  )
                : null,
            filled: true,
            fillColor: const Color(0xFF101923),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 14),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: ['Everything', 'Posts', 'Comments'].map((scope) {
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(scope),
                  selected: _scope == scope,
                  onSelected: (_) => setState(() => _scope = scope),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            FilterChip(
              avatar: const Icon(Icons.delete_outline_rounded, size: 17),
              label: const Text('Removed only'),
              selected: _deletedOnly,
              onSelected: (value) => setState(() => _deletedOnly = value),
            ),
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              tooltip: 'Filter record type',
              onSelected: (value) => setState(() => _type = value),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'All', child: Text('All record types')),
                PopupMenuItem(value: 'Post', child: Text('Posts')),
                PopupMenuItem(value: 'Comment', child: Text('Comments')),
              ],
              child: Chip(
                avatar: const Icon(Icons.tune_rounded, size: 17),
                label: Text(_type == 'All' ? 'Filters' : _type),
              ),
            ),
            const Spacer(),
            FilledButton.icon(
              key: const Key('archive-search-button'),
              onPressed: _search,
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: const Text('Search'),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _bottomBar() => Container(
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: Color(0xFF29384D))),
    ),
    child: BottomNavigationBar(
      backgroundColor: const Color(0xFF141E2C),
      selectedItemColor: const Color(0xFF65D6C2),
      unselectedItemColor: const Color(0xFF91A0B6),
      currentIndex: 0,
      onTap: (index) {
        if (index == 2) _showAbout();
      },
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.manage_search_rounded),
          label: 'Search',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.bookmark_outline_rounded),
          label: 'Saved',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.shield_outlined),
          label: 'Guide',
        ),
      ],
    ),
  );

  void _showAbout() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1B2737),
      showDragHandle: true,
      builder: (_) => const SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, 8, 24, 34),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Public archive, responsible use',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 12),
              Text(
                'Trace surfaces only publicly available, archive-provided records. It is not a people-search product and should not be used to target, harass, or identify individuals.',
              ),
              SizedBox(height: 12),
              Text(
                'Archive copies can be incomplete, outdated, or removed at the source. Verify important claims against the original public context.',
                style: TextStyle(color: Color(0xFFAEBBD0)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.record});
  final ArchiveRecord record;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF172131),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF2B3A50)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Tag(
                label: record.type,
                color: record.type == 'Post'
                    ? const Color(0xFFA8B5FF)
                    : const Color(0xFF65D6C2),
              ),
              const SizedBox(width: 7),
              if (record.removed)
                const _Tag(label: 'REMOVED', color: Color(0xFFFFB86B)),
              const Spacer(),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Save record',
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Saved locally for this session'),
                  ),
                ),
                icon: const Icon(
                  Icons.bookmark_border_rounded,
                  color: Color(0xFFB8C5D9),
                ),
              ),
            ],
          ),
          Text(
            record.community,
            style: const TextStyle(
              color: Color(0xFF91A0B6),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          if (record.title != null) ...[
            Text(
              record.title!,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 7),
          ],
          Text(
            record.body,
            style: const TextStyle(height: 1.42, color: Color(0xFFD9E2EF)),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(
                Icons.account_circle_outlined,
                size: 16,
                color: Color(0xFF91A0B6),
              ),
              const SizedBox(width: 5),
              Text(
                'u/${record.author}',
                style: const TextStyle(fontSize: 12, color: Color(0xFFB8C5D9)),
              ),
              const Spacer(),
              const Icon(
                Icons.schedule_rounded,
                size: 15,
                color: Color(0xFF91A0B6),
              ),
              const SizedBox(width: 4),
              Text(
                record.time,
                style: const TextStyle(fontSize: 12, color: Color(0xFF91A0B6)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .13),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: .8,
        color: color,
      ),
    ),
  );
}

class _NoResults extends StatelessWidget {
  const _NoResults();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(40),
    child: Column(
      children: [
        Icon(Icons.manage_search_outlined, size: 44, color: Color(0xFF91A0B6)),
        SizedBox(height: 12),
        Text(
          'No records match these filters',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class ArchiveRecord {
  const ArchiveRecord({
    required this.type,
    required this.community,
    required this.author,
    required this.time,
    required this.body,
    this.title,
    this.removed = false,
  });
  final String type, community, author, time, body;
  final String? title;
  final bool removed;
}

const _records = [
  ArchiveRecord(
    type: 'Post',
    community: 'r/space',
    author: 'orbiting_mars',
    time: 'May 14, 2024 · 09:32 UTC',
    title: 'The quietest part of a launch window',
    body:
        'A small field note from observing the morning pass. The timing is more forgiving than it first appears.',
    removed: true,
  ),
  ArchiveRecord(
    type: 'Comment',
    community: 'r/AskScience',
    author: 'orbiting_mars',
    time: 'Mar 03, 2024 · 18:04 UTC',
    body:
        'The original paper is a useful place to start, but the uncertainty range matters more than the headline figure.',
  ),
  ArchiveRecord(
    type: 'Comment',
    community: 'r/photography',
    author: 'orbiting_mars',
    time: 'Jan 27, 2024 · 21:18 UTC',
    body:
        'A tripod and a long exposure were enough for this one. I kept the edit deliberately light.',
  ),
];
