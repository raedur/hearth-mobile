import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../models/wiki_file.dart';
import '../services/api_service.dart';

class WikiScreen extends StatefulWidget {
  const WikiScreen({super.key});

  @override
  State<WikiScreen> createState() => _WikiScreenState();
}

class _WikiScreenState extends State<WikiScreen> {
  final _api = ApiService();
  List<WikiFile> _allFiles = [];
  String? _error;
  bool _loading = true;
  final _searchController = TextEditingController();
  String _query = '';
  final Set<String> _collapsed = {};
  List<Map<String, dynamic>>? _searchResults;
  bool _searching = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadFiles();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final q = _searchController.text.trim();
    setState(() => _query = q.toLowerCase());
    _debounce?.cancel();
    if (q.length < 2) {
      setState(() {
        _searchResults = null;
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        final results = await _api.searchWiki(q);
        if (mounted) setState(() { _searchResults = results; _searching = false; });
      } catch (_) {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  Future<void> _loadFiles() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await _api.wikiList();
      setState(() {
        _allFiles = raw
            .map((e) => WikiFile.fromJson(e as Map<String, dynamic>))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
        _loading = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Map<String, List<WikiFile>> _grouped(List<WikiFile> files) {
    final map = <String, List<WikiFile>>{};
    for (final f in files) {
      final slash = f.path.indexOf('/');
      final dir = slash == -1 ? '' : f.path.substring(0, slash);
      (map[dir] ??= []).add(f);
    }
    return map;
  }

String _folderLabel(String dir) =>
      dir.isEmpty ? 'General' : _titleCase(dir);

  String _fileFolder(WikiFile file) {
    final slash = file.path.indexOf('/');
    return slash == -1 ? '' : file.path.substring(0, slash);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 16),
            FilledButton(onPressed: _loadFiles, child: const Text('Retry')),
          ],
        ),
      );
    }

    final isSearching = _query.length >= 2;

    Widget body;
    if (isSearching) {
      if (_searching) {
        body = const Center(child: CircularProgressIndicator());
      } else if (_searchResults == null || _searchResults!.isEmpty) {
        body = Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off, size: 48, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 12),
              Text('No pages match "$_query"', style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        );
      } else {
        body = _buildSearchResults(_searchResults!);
      }
    } else {
      body = RefreshIndicator(
        onRefresh: _loadFiles,
        child: _buildGroupedList(_allFiles),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search wiki...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: isSearching
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () => _searchController.clear(),
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
        Expanded(child: body),
      ],
    );
  }

  Widget _buildSearchResults(List<Map<String, dynamic>> results) {
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (_, i) {
        final r = results[i];
        final file = WikiFile.fromJson(r);
        final snippet = (r['snippet'] as String?) ?? '';
        final folder = _fileFolder(file);
        return ListTile(
          leading: const Icon(Icons.description_outlined, size: 20),
          title: Text(_displayName(file.name)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (folder.isNotEmpty)
                Text(_titleCase(folder),
                    style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.primary)),
              if (snippet.isNotEmpty) Text(snippet, maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ),
          isThreeLine: folder.isNotEmpty && snippet.isNotEmpty,
          onTap: () => Navigator.push(context, _slideRoute(WikiFileScreen(file: file))),
        );
      },
    );
  }

  Widget _buildGroupedList(List<WikiFile> files) {
    final grouped = _grouped(files);
    final dirs = grouped.keys.toList()..sort();

    return ListView.builder(
      itemCount: dirs.length,
      itemBuilder: (_, i) {
        final dir = dirs[i];
        final files = grouped[dir]!;
        final label = _folderLabel(dir);
        final collapsed = _collapsed.contains(dir);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => setState(() {
                if (collapsed) {
                  _collapsed.remove(dir);
                } else {
                  _collapsed.add(dir);
                }
              }),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    Icon(
                      collapsed ? Icons.chevron_right : Icons.expand_more,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      label,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            letterSpacing: 0.08,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(width: 6),
                    Text('${files.length}',
                        style: Theme.of(context).textTheme.labelSmall),
                  ],
                ),
              ),
            ),
            if (!collapsed)
              ...files.map((file) => ListTile(
                    leading: const Icon(Icons.description_outlined, size: 20),
                    title: Text(_displayName(file.name)),
                    subtitle: file.lastModified != null
                        ? Text(_formatDate(file.lastModified!))
                        : null,
                    onTap: () => Navigator.push(
                        context, _slideRoute(WikiFileScreen(file: file))),
                  )),
          ],
        );
      },
    );
  }

  String _titleCase(String s) =>
      s[0].toUpperCase() + s.substring(1).replaceAll('_', ' ');

  String _displayName(String name) {
    final n = name.endsWith('.md') ? name.substring(0, name.length - 3) : name;
    return n.replaceAll('_', ' ');
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${months[dt.month - 1]} ${dt.day}';
    } catch (_) {
      return '';
    }
  }

}

Route<void> _slideRoute(Widget page) => PageRouteBuilder<void>(
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, __, child) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
        child: child,
      ),
      transitionDuration: const Duration(milliseconds: 280),
    );

class WikiFileScreen extends StatefulWidget {
  final WikiFile file;
  const WikiFileScreen({super.key, required this.file});

  @override
  State<WikiFileScreen> createState() => _WikiFileScreenState();
}

class _WikiFileScreenState extends State<WikiFileScreen> {
  final _api = ApiService();
  String? _content;
  String? _error;
  bool _loading = true;

  String get _displayName {
    final n = widget.file.name.endsWith('.md')
        ? widget.file.name.substring(0, widget.file.name.length - 3)
        : widget.file.name;
    return n.replaceAll('_', ' ');
  }

  String _readTime(String content) {
    final words = content.trim().split(RegExp(r'\s+')).length;
    final minutes = (words / 200).ceil();
    return '$minutes min read';
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${months[dt.month - 1]} ${dt.day}';
    } catch (_) {
      return '';
    }
  }

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  Future<void> _loadContent({bool isRefresh = false}) async {
    setState(() {
      _loading = !isRefresh;
      _error = null;
    });
    try {
      final content = await _api.wikiFile(widget.file.path);
      setState(() {
        _content = content;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (e.statusCode == 404 && mounted) {
        Navigator.pop(context);
        return;
      }
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = _content == null
        ? null
        : [
            if (widget.file.lastModified != null)
              _formatDate(widget.file.lastModified!),
            _readTime(_content!),
          ].join(' · ');

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _displayName,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                    fontWeight: FontWeight.w500,
                  ),
            ),
            if (meta != null)
              Text(meta,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.6),
                      )),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: () => _loadContent(isRefresh: true),
                  child: Markdown(
                    data: _content!,
                    selectable: true,
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                    onTapLink: (text, href, title) {
                      if (href == null || href.startsWith('http') || href.startsWith('#')) return;
                      final resolved = Uri.parse(widget.file.path).resolve(href).path;
                      final name = resolved.split('/').last;
                      Navigator.push(
                        context,
                        _slideRoute(WikiFileScreen(file: WikiFile(path: resolved, name: name))),
                      );
                    },
                  ),
                ),
    );
  }
}
