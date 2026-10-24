import 'dart:io';

import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;

import '../app.dart';
import '../core/byte_size.dart';
import '../core/constants.dart';
import '../models/duplicate_item.dart';
import '../models/enums.dart';
import '../services/app_log.dart';
import '../services/background_scanner.dart';
import '../services/results_controller.dart';
import '../services/scan_engine.dart';
import '../services/storage_service.dart';
import '../widgets/dialogs.dart';
import '../widgets/panel_scaffold.dart';
import '../widgets/themed.dart';

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

    AppLog.info(
      'Scan started: ${widget.scanType.label}, ${algorithm.label}, '
      '${storage.label}, ${exclusion.label}, roots: ${roots.join(', ')}',
    );
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
      AppLog.info(
        'Scan finished: ${groups.length} sets, '
        '${groups.fold(0, (n, g) => n + g.items.length - 1)} duplicates',
      );
      if (!mounted) return;
      setState(() {
        _results = ResultsController(
          groups,
          autoSelect: settings.autoSelectDuplicates,
        );
        _scan = null;
      });
    } catch (e) {
      AppLog.error('Scan failed: $e');
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
    if (blocked != null) return showPaywall(context, reason: blocked);
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
    final outcome = await results.deleteSelected(
      fallback: scope.storage.deleteOnRemovableVolume,
    );
    AppLog.info(
      'Deleted ${outcome.deleted} files, ${formatBytes(outcome.freedBytes)} freed',
    );
    for (final f in outcome.failed) {
      AppLog.error('Could not delete $f');
    }
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
    if (outcome.deleted > 0) await _maybeAskForRating();
  }

  /// `ProcessDeletionThreshold`: every second successful deletion, until the
  /// user has rated or bought premium, ask for a rating.
  Future<void> _maybeAskForRating() async {
    final scope = AppScope.of(context);
    final settings = scope.settings;
    settings.reviewThreshold += 1;
    if (settings.reviewThreshold.isOdd ||
        settings.ratingGiven ||
        scope.premium.isPremium) {
      return;
    }
    final saved = await confirm(
      context,
      title: 'Brilliant job done by you!',
      message:
          'You saved your device memory from unnecessary Duplicates, right ?',
    );
    if (!saved || !mounted) return;
    final rate = await confirm(
      context,
      title: 'Can we get a high five for this through a rating in store :)',
      message: '',
      yes: 'Sure!',
      no: 'later',
    );
    if (!rate) return;
    settings.ratingGiven = true;
    final review = InAppReview.instance;
    if (await review.isAvailable()) await review.requestReview();
  }

  Future<void> _select() async {
    final scope = AppScope.of(context);
    final f = await chooseOne(
      context,
      title: 'Select an option',
      options: SelectFilter.values,
      label: (f) => f.label,
    );
    if (f == null || !mounted) return;
    // Like the original, free users can open the filter; applying it is gated.
    if (!scope.premium.allowsSortAndSelectFilters) {
      return showPaywall(
        context,
        reason: 'Selection filters are a premium feature.',
      );
    }
    _results!.applySelection(f);
  }

  Future<void> _sort() async {
    final scope = AppScope.of(context);
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
    if (picked == null || !mounted) return;
    if (!scope.premium.allowsSortAndSelectFilters) {
      return showPaywall(
        context,
        reason: 'Sort filters are a premium feature.',
      );
    }
    r.sort(picked.$1, ascending: picked.$2);
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return PanelScaffold(
      title: results == null
          ? 'Summary'
          : '${results.duplicateCount} duplicates',
      header: results == null || results.groups.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: ListenableBuilder(
                listenable: results,
                builder: (_, _) => GlowOrb(
                  size: 210,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittedBox(
                        child: Text(
                          formatBytes(results.selectedBytes),
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${results.selectedCount} selected',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            )
          : results == null
          ? _ProgressView(progress: _progress)
          : _ResultsView(results: results, onSelect: _select, onSort: _sort),
      bottom: results == null || results.groups.isEmpty
          ? null
          : ListenableBuilder(
              listenable: results,
              builder: (_, _) => SizedBox(
                width: double.infinity,
                child: PrimaryButton(
                  loading: _deleting,
                  onPressed: results.selectedCount == 0 ? null : _delete,
                  icon: Icons.cleaning_services_outlined,
                  label: _deleting
                      ? 'Deleting files...'
                      : 'Clean Now (${formatBytes(results.selectedBytes)})',
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
            ProgressRing(
              value: determinate ? p.percent / 100 : null,
              size: 240,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    determinate ? '${p.percent}%' : '...',
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            SoftCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const IconBadge(icon: Icons.folder_open_outlined, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      p?.path ?? 'Looking for files...',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconBadge(icon: Icons.check_rounded, size: 88, solid: true),
                  SizedBox(height: 24),
                  Text(
                    'No duplicates found',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Brilliant job done by you!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                ],
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
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Row(
                children: [
                  _ToolChip(
                    icon: Icons.checklist,
                    label: 'Select',
                    onTap: onSelect,
                  ),
                  const SizedBox(width: 10),
                  _ToolChip(icon: Icons.sort, label: 'Sort', onTap: onSort),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                itemCount: rows.length,
                itemBuilder: (_, i) => switch (rows[i]) {
                  (String _, int n, DuplicateGroup g) => Padding(
                    padding: const EdgeInsets.fromLTRB(2, 16, 2, 6),
                    child: Row(
                      children: [
                        Text(
                          'Set $n',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${g.items.length} files · ${_setSize(g)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
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
    const dim = 48.0;
    final thumb = _isImage
        ? ClipOval(
            child: Image.file(
              File(item.path),
              width: dim,
              height: dim,
              fit: BoxFit.cover,
              cacheWidth: 120,
              errorBuilder: (_, _, _) => const IconBadge(
                icon: Icons.broken_image_outlined,
                size: dim,
                solid: true,
              ),
            ),
          )
        : IconBadge(
            icon: Icons.insert_drive_file_outlined,
            color:
                AppColors.badges[p.extension(item.name).hashCode %
                    AppColors.badges.length],
            size: dim,
            solid: true,
          );
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Tooltip(
              message: 'Open file',
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => OpenFilex.open(item.path),
                child: thumb,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (item.isMainFile) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Original',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Modified ${formatDate(item.modified)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                  Text(
                    item.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatBytes(item.size),
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            Checkbox(value: item.checked, onChanged: (_) => onToggle()),
          ],
        ),
      ),
    );
  }
}

class _ToolChip extends StatelessWidget {
  const _ToolChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.background,
    shape: const StadiumBorder(),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    ),
  );
}

/// "45 KB each" when every file has the same size (content and size scans),
/// otherwise the total, since name and appearance sets can mix sizes.
String _setSize(DuplicateGroup g) {
  final first = g.items.first.size;
  if (g.items.every((i) => i.size == first)) {
    return '${formatBytes(first)} each';
  }
  return '${formatBytes(g.items.fold(0, (sum, i) => sum + i.size))} total';
}
