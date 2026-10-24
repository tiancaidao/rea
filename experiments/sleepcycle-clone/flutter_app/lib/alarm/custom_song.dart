import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../app_state.dart';

/// "Your own song" as the alarm: an audio file the user picks from the phone,
/// copied into the app's storage so it still rings if the original is moved.
class CustomSong {
  static const label = 'Your own song';

  /// The copied file, or null when none has been picked (or it's gone).
  static String? get path {
    final p = AppState.I.pref('alarm_custom_path');
    return p.isNotEmpty && File(p).existsSync() ? p : null;
  }

  static String get title => AppState.I.pref('alarm_custom_name');

  /// Let the user pick a song; returns true when one was set as the alarm.
  static Future<bool> pick() async {
    final f = await FilePicker.pickFile(type: FileType.audio);
    final src = f?.path;
    if (src == null) return false;
    final dir = await getApplicationSupportDirectory();
    final ext = src.contains('.') ? src.substring(src.lastIndexOf('.')) : '.mp3';
    final dst = File('${dir.path}/alarm_custom$ext');
    await File(src).copy(dst.path);
    final s = AppState.I;
    s.setPref('alarm_custom_path', dst.path);
    s.setPref('alarm_custom_name', f!.name.replaceAll(RegExp(r'\.[^.]+$'), ''));
    s.setPref('alarm_sound', label);
    return true;
  }
}
