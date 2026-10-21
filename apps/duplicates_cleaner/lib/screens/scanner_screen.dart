import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;

import '../app.dart';
import '../core/byte_size.dart';
import '../core/constants.dart';
import '../models/duplicate_item.dart';
import '../models/enums.dart';
import '../services/background_scanner.dart';
import '../services/results_controller.dart';
import '../services/scan_engine.dart';
import '../services/storage_service.dart';
import '../widgets/dialogs.dart';
import '../widgets/panel_scaffold.dart';

/// Scan progress, results, selection and deletion (`ScannerPageActivity`).
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key, required this.scanType});

  final ScanType scanType;

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  BackgroundScan? _scan;
  ScanProgress? _progress;
  ResultsController? _results;
  String? _error;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _scan?.cancel();
    _results?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final scope = AppScope.of(context);
    final settings = scope.settings, premium = scope.premium;

    var algorithm = settings.algorithm;
    if (!premium.allowsAlgorithm(algorithm) ||
        (algorithm == ScanAlgorithm.sameAppearance &&
            widget.scanType != ScanType.image)) {
      algorithm = ScanAlgorithm.sameContent;
    }
    final storage = premium.allowsStorage(settings.storage)
        ? settings.storage
        : StorageSelection.internal;
    final exclusion = premium.allowsSizeExclusion(settings.sizeExclusion)
        ? settings.sizeExclusion
        : FileSizeExclusion.none;

    if (algorithm == ScanAlgorithm.sameAppearance &&
        !settings.similarImageWarningDisabled) {
      final dontRemind = await confirm(
        context,
        title: 'Similar image scan',
        message:
            'This scan can take time. Please review each image carefully; '
            'false positives are possible.',
        yes: 'Dont remind again',
        no: 'Ok',
      );
      if (dontRemind) settings.similarImageWarningDisabled = true;
    }

    if (!await scope.storage.ensureAccess()) {
      if (!mounted) return;
      final open = await confirm(
        context,
        title: 'All files access required',
        message:
            'To access files on device folders and subfolders, the app needs all '
            'files access. Please enable it now to proceed further.',
        yes: 'Show me',
        no: 'Back',
      );
      if (open) await scope.storage.openAccessSettings();
      if (mounted) Navigator.of(context).pop();
      return;
    }

    List<String> roots;
    try {
      roots = await scope.storage.rootsFor(
        storage,
        customFolder: settings.customFolder,
      );
    } on StorageUnavailable catch (e) {
      if (!mounted) return;
      await showMessage(context, e.title, e.message);
      if (mounted) Navigator.of(context).pop();
      return;
    }

    final scan = await BackgroundScan.start(
      ScanRequest(
        roots: roots,
        extensions: widget.scanType.extensions(settings.customExtensions),
        algorithm: algorithm,
        sizeExclusion: exclusion,
        verifyContent: settings.verifyContent,
      ),
    );
    if (!mounted) {
      await scan.cancel();
      return;
    }
    _scan = scan;
    scan.progress.listen((p) {
      if (mounted) setState(() => _progress = p);
    });
    try {
      final groups = await scan.result;
      if (!mounted) return;
      setState(() {
        _results = ResultsController(
          groups,
          autoSelect: settings.autoSelectDuplicates,
        );
        _scan = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _delete() async {
    final scope = AppScope.of(context);
    final results = _results!;
    if (results.selectedCount == 0) return;
    final blocked = results.freeTierBlockReason(
      isPremium: scope.premium.isPremium,
    );
    if (blocked != null) return showUpgradeDialog(context, reason: blocked);
    if (scope.settings.promptBeforeDeletion) {
      final ok = await confirm(
        context,
        title: 'Warning: Deletion Confirmation!',
        message:
            'Are you sure to delete ${results.selectedCount} selected files? '
            'Files are permanently deleted, please re-check file paths.',
      );
      if (!ok) return;
    }
    setState(() => _deleting = true);
    final outcome = await results.deleteSelected();
    if (!mounted) return;
    setState(() => _deleting = false);
    scope.settings.deletionSuccessCount += outcome.deleted;
    final failed = outcome.failed.isEmpty
        ? ''
        : ' (${outcome.failed.length} could not be deleted)';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Files deleted successfully: ${outcome.deleted}, '
          '${formatBytes(outcome.freedBytes)} freed$failed',
        ),
      ),
    );
  }

  Future<void> _select() async {
    final scope = AppScope.of(context);
    if (!scope.premium.allowsSortAndSelectFilters) {
      return showUpgradeDialog(
        context,
        reason: 'Selection filters are a premium feature.',
      );
    }
    final f = await chooseOne(
      context,
      title: 'Select an option',
      options: SelectFilter.values,
      label: (f) => f.label,
    );
    if (f != null) _results!.applySelection(f);
  }

  Future<void> _sort() async {
    final scope = AppScope.of(context);
    if (!scope.premium.allowsSortAndSelectFilters) {
      return showUpgradeDialog(
        context,
        reason: 'Sort filters are a premium feature.',
      );
    }
    final options = [
      for (final f in SortField.values) ...[(f, true), (f, false)],
    ];
    final r = _results!;
    final picked = await chooseOne<(SortField, bool)>(
      context,
      title: 'Sort',
      options: options,
      selected: r.sortField == null ? null : (r.sortField!, r.ascending),
      label: (o) => '${o.$1.label} - ${o.$2 ? 'Ascending' : 'Descending'}',
    );
    if (picked != null) r.sort(picked.$1, ascending: picked.$2);
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return PanelScaffold(
      title: results == null
          ? 'Summary'
          : '${results.duplicateCount} duplicates',
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!),
              ),
            )
          : results == null
          ? _ProgressView(progress: _progress)
          : _ResultsView(results: results, onSelect: _select, onSort: _sort),
      bottom: results == null
          ? null
          : ListenableBuilder(
              listenable: results,
              builder: (_, _) => Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton.icon(
                    onPressed: _deleting || results.selectedCount == 0
                        ? null
                        : _delete,
                    icon: _deleting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.delete_outline),
                    label: Text(
                      _deleting
                          ? 'Deleting files...'
                          : 'CAN BE DELETED (${formatBytes(results.selectedBytes)})',
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

class _ProgressView extends StatelessWidget {
  const _ProgressView({required this.progress});

  final ScanProgress? progress;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final determinate = p != null && p.phase != ScanPhase.enumerating;
    final label = switch (p?.phase) {
      null || ScanPhase.enumerating => 'Analyzing...',
      ScanPhase.analyzing => 'Analyzing...',
      ScanPhase.comparing => 'Comparing...',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 125,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: determinate ? p.percent / 100 : null,
                    strokeWidth: 10,
                    backgroundColor: Colors.black12,
                    color: AppColors.accent,
                  ),
                  if (determinate)
                    Center(
                      child: Text(
                        '${p.percent}%',
                        style: const TextStyle(fontSize: 22),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(label, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            Text(
              p?.path ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AppColors.lightBlack),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultsView extends StatelessWidget {
  const _ResultsView({
    required this.results,
    required this.onSelect,
    required this.onSort,
  });

  final ResultsController results;
  final VoidCallback onSelect;
  final VoidCallback onSort;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: results,
      builder: (context, _) {
        if (results.groups.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No duplicates found. Brilliant job done by you!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
            ),
          );
        }
        final rows = <Object>[];
        for (final (i, g) in results.groups.indexed) {
          rows
            ..add(('header', i + 1, g))
            ..addAll(g.items);
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onSelect,
                      icon: const Icon(Icons.checklist),
                      label: const Text('Select'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onSort,
                      icon: const Icon(Icons.sort),
                      label: const Text('Sort'),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: rows.length,
                itemBuilder: (_, i) => switch (rows[i]) {
                  (String _, int n, DuplicateGroup g) => Padding(
                    padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
                    child: Text(
                      'Set $n: ${g.items.length} files (${formatBytes(g.items.first.size)} each)',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  DuplicateItem item => _DuplicateTile(
                    item: item,
                    onToggle: () => results.toggle(item),
                  ),
                  _ => const SizedBox.shrink(),
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DuplicateTile extends StatelessWidget {
  const _DuplicateTile({required this.item, required this.onToggle});

  final DuplicateItem item;
  final VoidCallback onToggle;

  bool get _isImage => AppConstants.decodableImageExtensions.contains(
    p.extension(item.name).replaceFirst('.', '').toLowerCase(),
  );

  @override
  Widget build(BuildContext context) {
    final thumb = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox.square(
        dimension: AppConstants.thumbnailSize,
        child: _isImage
            ? Image.file(
                File(item.path),
                fit: BoxFit.cover,
                cacheWidth: 120,
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.broken_image_outlined),
              )
            : const ColoredBox(
                color: AppColors.primary,
                child: Icon(Icons.insert_drive_file_outlined),
              ),
      ),
    );
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Checkbox(value: item.checked, onChanged: (_) => onToggle()),
              InkWell(onTap: () => OpenFilex.open(item.path), child: thumb),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 15),
                          ),
                        ),
                        if (item.isMainFile)
                          const Chip(
                            label: Text(
                              'Original',
                              style: TextStyle(fontSize: 11),
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                    Text(
                      'Size: ${formatBytes(item.size)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      'Modified: ${formatDate(item.modified)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      item.path,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.lightBlack,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
