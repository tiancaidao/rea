import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Plain-text activity log, like the original's Serilog file
/// (`logs/KaerosDCLog.txt`), shared from Settings → Export Log.
class AppLog {
  AppLog._();

  static const _maxBytes = 1 << 20;
  static File? _file;

  static Future<File> _logFile() async {
    if (_file != null) return _file!;
    final dir = Directory(
      p.join((await getApplicationSupportDirectory()).path, 'logs'),
    );
    await dir.create(recursive: true);
    return _file = File(p.join(dir.path, 'DCLog.txt'));
  }

  static Future<void> info(String message) => _write('INF', message);
  static Future<void> error(String message) => _write('ERR', message);

  static Future<void> _write(String level, String message) async {
    try {
      final f = await _logFile();
      // Keep the newest half once the log passes 1 MB.
      if (await f.exists() && await f.length() > _maxBytes) {
        final text = await f.readAsString();
        await f.writeAsString(text.substring(text.length ~/ 2));
      }
      await f.writeAsString(
        '${DateTime.now().toIso8601String()} [$level] $message\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // Logging must never break a scan or a delete.
    }
  }

  /// Opens the share sheet with the log file. Returns false if nothing has
  /// been logged yet.
  static Future<bool> export() async {
    final f = await _logFile();
    if (!await f.exists() || await f.length() == 0) return false;
    await SharePlus.instance.share(
      ShareParams(files: [XFile(f.path)], subject: 'Duplicates Cleaner log'),
    );
    return true;
  }
}
