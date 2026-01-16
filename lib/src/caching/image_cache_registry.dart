import 'dart:io';

import 'package:aio_image_view/src/caching/cache_config.dart';
import 'package:aio_image_view/src/caching/cache_key_strategy.dart';
import 'package:aio_image_view/src/caching/cache_metrics.dart';
import 'package:aio_image_view/src/caching/circuit_breaker.dart';
import 'package:aio_image_view/src/caching/persistent_file_system.dart';
import 'package:aio_image_view/src/caching/resilient_file_service.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// The central command center for the application's image caching system.
///
/// **Role:**
/// [ImageCacheRegistry] acts as a factory and manager for [CacheManager] instances,
/// ensuring that each category of image (avatar, content, icon) is treated according
/// to its specific retention and resilience policy.
///
/// **Key Responsibilities:**
/// 1.  **Multi-Bucket Management:** Lazily creates and retrieves specialized cache managers.
/// 2.  **Security Scope:** Manages the current `userId` to salt cache keys for private images.
/// 3.  **Resilience Orchestration:** Shares a single [HostCircuitBreaker] across all buckets
///     to prevent retry storms on bad networks.
/// 4.  **Maintenance:** Prunes old cache versions to prevent disk bloat.
///
/// ## Usage
///
/// ### Initialization (in `main.dart`)
/// ```dart
/// void main() async {
///   // ...
///   imageCaches.initialize(
///     userId: authService.currentUserId,
///     metricsCallback: kDebugMode ? debugMetricsCallback : null,
///   );
///   runApp(MyApp());
/// }
/// ```
///
/// ### Accessing Managers
/// ```dart
/// CachedNetworkImage(
///   imageUrl: 'https://example.com/avatar.jpg',
///   cacheManager: imageCaches.avatar, // Uses long-lived, persistent storage
/// )
/// ```
///
/// ### Managing Session State
/// ```dart
/// // On Logout
/// await imageCaches.clearUserCaches(); // Wipes private data
/// imageCaches.setUserId(null); // Resets scope
/// ```
class ImageCacheRegistry {
  ImageCacheRegistry._();

  static final ImageCacheRegistry instance = ImageCacheRegistry._();

  final Map<ImageCacheBucket, CacheManager> _managers = {};
  final HostCircuitBreaker _circuitBreaker = HostCircuitBreaker();

  CacheMetricsCallback? _metricsCallback;
  String? _currentUserId;
  bool _initialized = false;

  /// Initializes the registry with global configuration.
  ///
  /// Call this once at app startup before any images are displayed.
  ///
  /// *   [metricsCallback]: Optional callback to receive performance/error events for debugging.
  /// *   [userId]: The ID of the currently logged-in user (if any).
  void initialize({CacheMetricsCallback? metricsCallback, String? userId}) {
    _metricsCallback = metricsCallback;
    _currentUserId = userId;
    _initialized = true;
    _pruneOldVersions();
  }

  /// Removes obsolete cache directories from previous versions of the app.
  ///
  /// **Why:** Prevents "ghost" cache files from filling up the user's storage
  /// after we update [CacheBucketConfig.key] (e.g., migrating from `v1` to `v2`).
  Future<void> _pruneOldVersions() async {
    try {
      final baseDir = await getApplicationSupportDirectory();
      final tempDir = await getTemporaryDirectory();

      final dirsToCheck = [baseDir, tempDir];

      for (final dir in dirsToCheck) {
        if (!dir.existsSync()) continue;

        await for (final entity in dir.list()) {
          if (entity is Directory) {
            final name = p.basename(entity.path);

            // Check if this directory matches any bucket prefix but is NOT the current key
            for (final config in CacheBucketConfig.configs.values) {
              final currentKey = config.key;
              // We assume keys follow 'name-vN' pattern.
              // We want to find 'name-v' where the version suffix differs.
              if (!currentKey.contains('-v')) continue;

              final prefix = currentKey.substring(
                0,
                currentKey.lastIndexOf('-v') + 2,
              ); // '...-v'

              if (name.startsWith(prefix) && name != currentKey) {
                // It's an old version (e.g. img-avatar-v0 vs img-avatar-v1)
                try {
                  await entity.delete(recursive: true);
                } catch (_) {
                  // Ignore cleanup errors
                }
              }
            }
          }
        }
      }
    } catch (_) {
      // Ignore root directory access errors
    }
  }

  /// Sets the current user context.
  ///
  /// Call this immediately after a successful login.
  /// Future calls to [buildCacheKey] with `isPrivate: true` will use this ID.
  void setUserId(String? userId) {
    _currentUserId = userId;
  }

  /// The currently active user ID.
  ///
  /// Returns `null` if no user is logged in.
  String? get currentUserId => _currentUserId;

  /// Whether [initialize] has been called.
  bool get isInitialized => _initialized;

  /// Retrieves (or creates) the cache manager for a specific bucket.
  ///
  /// Uses a lazy initialization strategy to avoid opening database connections
  /// for unused buckets.
  CacheManager getManager(ImageCacheBucket bucket) {
    return _managers.putIfAbsent(bucket, () => _createManager(bucket));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Convenience accessors
  // ─────────────────────────────────────────────────────────────────────────

  /// Cache manager optimized for user avatars.
  ///
  /// Characteristics:
  /// *   **Storage:** Persistent (Application Support).
  /// *   **Retention:** High (180 days).
  /// *   **Freshness:** 12 hours min, 30 days max.
  CacheManager get avatar => getManager(ImageCacheBucket.avatar);

  /// Cache manager optimized for list/grid thumbnails.
  ///
  /// Characteristics:
  /// *   **Storage:** Temporary (Cache).
  /// *   **Retention:** Medium (60 days).
  /// *   **Concurrency:** High (6 concurrent downloads).
  CacheManager get thumbnail => getManager(ImageCacheBucket.thumbnail);

  /// Cache manager optimized for standard content (feed images).
  ///
  /// Characteristics:
  /// *   **Storage:** Temporary (Cache).
  /// *   **Retention:** Low/Medium (30 days).
  CacheManager get content => getManager(ImageCacheBucket.content);

  /// Cache manager optimized for app icons and static assets.
  ///
  /// Characteristics:
  /// *   **Storage:** Persistent (Application Support).
  /// *   **Retention:** Very High (365 days).
  CacheManager get icon => getManager(ImageCacheBucket.icon);

  /// Cache manager optimized for large hero banners.
  ///
  /// Characteristics:
  /// *   **Storage:** Temporary (Cache).
  /// *   **Concurrency:** Low (2 concurrent downloads).
  CacheManager get banner => getManager(ImageCacheBucket.banner);

  // ─────────────────────────────────────────────────────────────────────────
  // Cache key building
  // ─────────────────────────────────────────────────────────────────────────

  /// Generates a standardized cache key for a given URL.
  ///
  /// **Features:**
  /// *   **Normalization:** Removes volatile query params (tokens, timestamps).
  /// *   **Scoping:** Prefixes the key with [currentUserId] if [isPrivate] is true.
  ///
  /// Use this when manually interacting with the cache manager.
  String buildCacheKey(
    String url, {
    String? explicitKey,
    bool isPrivate = false,
  }) {
    return CacheKeyBuilder.build(
      url,
      explicitKey: explicitKey,
      userId: _currentUserId,
      isPrivate: isPrivate,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Cache management
  // ─────────────────────────────────────────────────────────────────────────

  /// Wipes all data from ALL cache buckets.
  ///
  /// **Warning:** This is a destructive operation that removes persistent assets
  /// like icons and avatars. Use [clear] or [clearUserCaches] for more targeted cleanup.
  Future<void> clearAll() async {
    for (final bucket in ImageCacheBucket.values) {
      await getManager(bucket).emptyCache();
    }
    _circuitBreaker.resetAll();
  }

  /// Wipes all data from a specific bucket.
  Future<void> clear(ImageCacheBucket bucket) async {
    await getManager(bucket).emptyCache();
  }

  /// Wipes all user-scoped private data.
  ///
  /// **Use Case:** Call this on logout to ensure strict data isolation between users.
  /// Clears the [ImageCacheBucket.avatar] and [ImageCacheBucket.content] buckets.
  Future<void> clearUserCaches() async {
    await clear(ImageCacheBucket.avatar);
    await clear(ImageCacheBucket.content);
  }

  /// Resets the network failure counters for all hosts.
  ///
  /// **Use Case:** Call this when the device regains connectivity (e.g., switches
  /// from offline to WiFi) to immediately retry hosts that were previously blocked
  /// by the circuit breaker.
  void resetCircuitBreakers() {
    _circuitBreaker.resetAll();
  }

  /// Returns a snapshot of the circuit breaker's internal state.
  ///
  /// Useful for debugging network resilience logic.
  Map<String,
          ({int failures, bool isOpen, bool isHalfOpen, bool probeInFlight})>
      get circuitBreakerState => _circuitBreaker.debugState;

  // ─────────────────────────────────────────────────────────────────────────
  // Private helpers
  // ─────────────────────────────────────────────────────────────────────────

  CacheManager _createManager(ImageCacheBucket bucket) {
    final config = CacheBucketConfig.configs[bucket]!;

    // Use Persistent storage for Avatars/Icons, Temp for others
    final fileSystem = switch (bucket) {
      ImageCacheBucket.avatar ||
      ImageCacheBucket.icon =>
        PersistentIOFileSystem(config.key),
      _ => IOFileSystem(config.key),
    };

    return _BucketCacheManager(
      config: config,
      fileService: ResilientFileService(
        config: config,
        circuitBreaker: _circuitBreaker,
        metricsCallback: _metricsCallback,
      ),
      fileSystem: fileSystem,
    );
  }
}

/// Per-bucket cache manager with [ImageCacheManager] mixin.
///
/// The [ImageCacheManager] mixin enables disk-cached resized variants,
/// which is required for `maxWidthDiskCache`/`maxHeightDiskCache` to work
/// in [CachedNetworkImage].
class _BucketCacheManager extends CacheManager with ImageCacheManager {
  _BucketCacheManager({
    required CacheBucketConfig config,
    required FileService fileService,
    required FileSystem fileSystem,
  }) : super(
          Config(
            config.key,
            stalePeriod: config.stalePeriod,
            maxNrOfCacheObjects: config.maxObjects,
            // Removed JsonCacheInfoRepository to default to CacheObjectProvider (SQLite)
            fileService: fileService,
            fileSystem: fileSystem,
          ),
        );
}

/// Shorthand accessor for the global image cache registry.
///
/// Usage:
/// ```dart
/// imageCaches.avatar  // Get avatar cache manager
/// imageCaches.buildCacheKey(url)  // Normalize a URL for caching
/// ```
ImageCacheRegistry get imageCaches => ImageCacheRegistry.instance;
