package com.duplicates_cleaner.android

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Deletes files on SD cards and USB drives through the Storage Access
/// Framework, as the original does with `DocumentFile` tree URIs. The user
/// grants each volume once; the grant is persisted.
class MainActivity : FlutterActivity() {
    private var pendingGrant: ((Uri?) -> Unit)? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "deleteOnVolume" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.success(false)
                        } else {
                            deleteOnVolume(path) { result.success(it) }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /// [path] looks like /storage/1234-ABCD/DCIM/a.jpg.
    private fun deleteOnVolume(path: String, done: (Boolean) -> Unit) {
        val parts = path.removePrefix("/storage/").split("/", limit = 2)
        if (parts.size < 2 || parts[0] == "emulated") return done(false)
        val volume = parts[0]
        val relative = parts[1]
        val existing = contentResolver.persistedUriPermissions.firstOrNull {
            it.isWritePermission &&
                DocumentsContract.getTreeDocumentId(it.uri) == "$volume:"
        }?.uri
        if (existing != null) return done(delete(existing, volume, relative))
        requestVolume(volume) { tree ->
            done(tree != null && delete(tree, volume, relative))
        }
    }

    private fun delete(tree: Uri, volume: String, relative: String): Boolean = try {
        val doc = DocumentsContract.buildDocumentUriUsingTree(tree, "$volume:$relative")
        DocumentsContract.deleteDocument(contentResolver, doc)
    } catch (e: Exception) {
        false
    }

    private fun requestVolume(volume: String, done: (Uri?) -> Unit) {
        if (pendingGrant != null) return done(null)
        pendingGrant = done
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            putExtra(
                DocumentsContract.EXTRA_INITIAL_URI,
                DocumentsContract.buildRootUri(EXTERNAL_STORAGE_AUTHORITY, volume),
            )
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
            )
        }
        startActivityForResult(intent, REQUEST_TREE)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_TREE) return
        val callback = pendingGrant ?: return
        pendingGrant = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) return callback(null)
        contentResolver.takePersistableUriPermission(
            uri,
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
        )
        callback(uri)
    }

    companion object {
        private const val CHANNEL = "duplicates_cleaner/volume"
        private const val REQUEST_TREE = 4711
        private const val EXTERNAL_STORAGE_AUTHORITY = "com.android.externalstorage.documents"
    }
}
