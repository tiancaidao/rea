import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/enums.dart';
import 'photo_library.dart';

class StorageUnavailable implements Exception {
  StorageUnavailable(this.title, this.message);
  final String title;
  final String message;
}

/// Resolves scan roots for each storage option and handles storage access.
///
/// Android mirrors the original: "All files access" plus volume paths under
/// /storage. iOS has no shared file system, so "internal" means the app's
/// Documents folder (shared through the Files app) and the custom folder
/// option uses the system folder picker.
class StorageService {
  static const internalRoot = '/storage/emulated/0';
  static const parallelRoot = '/storage/emulated/999';

  /// On iOS, internal storage also means the Photos library.
  final photos = PhotoLibraryService();

  Future<bool> ensureAccess() async {
    if (!Platform.isAndroid) return true;
    if (await Permission.manageExternalStorage.isGranted) return true;
    if (await Permission.manageExternalStorage.request().isGranted) return true;
    // Android 10 and below fall back to the legacy storage permission.
    return (await Permission.storage.request()).isGranted;
  }

  Future<void> openAccessSettings() => openAppSettings();

  static const _volume = MethodChannel('duplicates_cleaner/volume');

  /// Deletes a file on an SD card or USB drive through the Storage Access
  /// Framework, asking once per volume for folder access. Used when a plain
  /// delete is refused. Returns false off Android or for internal storage.
  Future<bool> deleteOnRemovableVolume(String path) async {
    if (!Platform.isAndroid ||
        !path.startsWith('/storage/') ||
        path.startsWith('/storage/emulated/')) {
      return false;
    }
    try {
      return await _volume.invokeMethod<bool>('deleteOnVolume', {
            'path': path,
          }) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  Future<String?> pickFolder() =>
      FilePicker.getDirectoryPath(dialogTitle: 'Select a folder to scan');

  Future<List<String>> rootsFor(
    StorageSelection s, {
    String? customFolder,
  }) async {
    if (s == StorageSelection.customFolder) {
      if (customFolder == null || !Directory(customFolder).existsSync()) {
        throw StorageUnavailable(
          'Select a folder',
          'Choose a folder to scan first.',
        );
      }
      return [customFolder];
    }
    if (!Platform.isAndroid) {
      return [(await getApplicationDocumentsDirectory()).path];
    }
    final removable = await _removableVolumes();
    switch (s) {
      case StorageSelection.internal:
        return [internalRoot];
      case StorageSelection.parallel:
        if (!Directory(parallelRoot).existsSync()) {
          throw StorageUnavailable(
            'Parallel storage not found',
            'No dual-app / parallel space was found.',
          );
        }
        return [parallelRoot];
      case StorageSelection.sdCard:
      case StorageSelection.usb:
        if (removable.isEmpty) {
          throw s == StorageSelection.sdCard
              ? StorageUnavailable(
                  'SD Card Not Found!',
                  'Please re-check the device memory card slot.',
                )
              : StorageUnavailable(
                  'USB Error!',
                  'USB device not mounted correctly. Please eject and reattach it.',
                );
        }
        return removable;
      case StorageSelection.internalPlusSdCard:
        return [internalRoot, ...removable];
      case StorageSelection.customFolder:
        return const [];
    }
  }

  /// Volume roots such as /storage/1234-ABCD derived from the app-specific
  /// external directories Android reports for each mounted volume.
  Future<List<String>> _removableVolumes() async {
    final dirs = await getExternalStorageDirectories() ?? const [];
    return [
      for (final d in dirs)
        if (!d.path.startsWith('/storage/emulated'))
          d.path.split('/Android/').first,
    ];
  }
}
