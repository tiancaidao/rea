import 'dart:async';
import 'dart:isolate';

import '../models/duplicate_item.dart';
import 'scan_engine.dart';

/// Runs [ScanEngine] on a background isolate so hashing never blocks the UI.
class BackgroundScan {
  BackgroundScan._(this._isolate, this.progress, this.result, this._cancelPort);

  final Isolate _isolate;
  final Stream<ScanProgress> progress;
  final Future<List<DuplicateGroup>> result;
  final Completer<SendPort> _cancelPort;

  static Future<BackgroundScan> start(ScanRequest request) async {
    final events = ReceivePort();
    final progress = StreamController<ScanProgress>.broadcast();
    final result = Completer<List<DuplicateGroup>>();
    final cancelPort = Completer<SendPort>();
    final isolate = await Isolate.spawn(_entry, (request, events.sendPort));
    events.listen((message) {
      switch (message) {
        case SendPort port:
          cancelPort.complete(port);
        case (ScanPhase phase, int percent, String path):
          progress.add(ScanProgress(phase, percent, path));
        case List<List<Map<String, Object?>>> groups:
          result.complete([
            for (final g in groups)
              DuplicateGroup([for (final j in g) DuplicateItem.fromJson(j)]),
          ]);
          events.close();
          progress.close();
        case (String error, String _):
          result.completeError(Exception(error));
          events.close();
          progress.close();
      }
    });
    return BackgroundScan._(
      isolate,
      progress.stream,
      result.future,
      cancelPort,
    );
  }

  Future<void> cancel() async {
    (await _cancelPort.future).send(true);
    _isolate.kill(priority: Isolate.beforeNextEvent);
  }

  static Future<void> _entry((ScanRequest, SendPort) args) async {
    final (request, out) = args;
    final cancel = ReceivePort();
    var cancelled = false;
    cancel.listen((_) => cancelled = true);
    out.send(cancel.sendPort);
    try {
      final groups = await ScanEngine(
        request,
        onProgress: (p) => out.send((p.phase, p.percent, p.path)),
        isCancelled: () => cancelled,
      ).run();
      out.send([
        for (final g in groups) [for (final i in g.items) i.toJson()],
      ]);
    } catch (e, st) {
      out.send((e.toString(), st.toString()));
    } finally {
      cancel.close();
    }
  }
}
