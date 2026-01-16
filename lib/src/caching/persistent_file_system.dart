import 'package:file/file.dart' as f;
import 'package:file/local.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// A file system implementation that persists files in the Application Support directory.
///
/// **The Problem:**
/// Standard cache managers store files in the temporary directory. The OS (iOS/Android)
/// aggressively wipes this directory when storage is low, causing users to constantly
/// re-download static assets like app icons or badges.
///
/// **The Solution:**
/// This implementation uses `getApplicationSupportDirectory()`, which the OS treats
/// as "user data" and does not auto-delete.
///
/// **Usage:**
/// Used by [ImageCacheRegistry] for the [ImageCacheBucket.avatar] and [ImageCacheBucket.icon] buckets.
class PersistentIOFileSystem implements FileSystem {
  final Future<f.Directory> _fileDir;
  final String _cacheKey;

  PersistentIOFileSystem(this._cacheKey)
      : _fileDir = _createDirectory(_cacheKey);

  static Future<f.Directory> _createDirectory(String key) async {
    // Use ApplicationSupportDirectory instead of TemporaryDirectory
    final baseDir = await getApplicationSupportDirectory();
    final path = p.join(baseDir.path, key);
    const fs = LocalFileSystem();
    final directory = fs.directory(path);
    await directory.create(recursive: true);
    return directory;
  }

  @override
  Future<f.File> createFile(String name) async {
    final directory = await _fileDir;
    if (!(await directory.exists())) {
      await _createDirectory(_cacheKey);
    }
    return directory.childFile(name);
  }
}
