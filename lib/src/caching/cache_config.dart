/// Cache bucket configurations for different image categories.
///
/// This file defines the multi-bucket caching architecture optimized for:
/// - 10M+ users at scale
/// - Hostile networks (Yemen-grade 2G/3G, high latency, packet loss)
/// - Diverse image types (avatars, thumbnails, content, icons, banners)
library;

/// Cache buckets for different image categories.
///
/// Using separate buckets prevents cache thrashing where important small images
/// (avatars, icons) get evicted by large noisy images (feed content).
enum ImageCacheBucket {
  /// User avatars and profile pictures.
  ///
  /// **Strategy:** Long-lived, persistent storage.
  /// **Why:** Losing these degrades the personal feel of the app.
  avatar,

  /// App icons, badges, and logos.
  ///
  /// **Strategy:** Extremely long-lived (almost permanent).
  /// **Why:** These rarely change and should always be available offline.
  icon,

  /// Small thumbnails for lists and grids.
  ///
  /// **Strategy:** High volume, medium retention, aggressive concurrency.
  /// **Why:** Users scroll fast; we need to fetch many small files quickly.
  thumbnail,

  /// Main feed content (photos, posts).
  ///
  /// **Strategy:** Large size, moderate retention, standard concurrency.
  /// **Why:** High churn; old feed content is rarely revisited.
  content,

  /// Large hero images and banners.
  ///
  /// **Strategy:** Very large size, low concurrency, long retention.
  /// **Why:** These are "heavy" downloads; we don't want to re-fetch them often.
  banner,
}

/// Configuration for a cache bucket.
///
/// Defines the rules of engagement for network fetching and disk retention
/// for a category of images.
class CacheBucketConfig {
  /// Creates a configuration for a cache bucket.
  const CacheBucketConfig({
    required this.key,
    required this.stalePeriod,
    required this.maxObjects,
    required this.minFresh,
    required this.maxFresh,
    required this.concurrentFetches,
    this.responseTimeout = const Duration(seconds: 15),
    this.streamTimeout = const Duration(seconds: 45),
    this.maxRetryAttempts = 4,
  });

  /// The unique string identifier for this cache on disk.
  ///
  /// Includes a version suffix (e.g., `-v1`) to allow for
  /// clean-slate migrations when cache structures change.
  final String key;

  /// The duration after which an accessed file is considered eligible for deletion.
  ///
  /// Used by the eviction strategy to clean up disk space.
  final Duration stalePeriod;

  /// The hard limit on the number of files in this bucket.
  ///
  /// Once exceeded, the Least Recently Used (LRU) files are evicted.
  final int maxObjects;

  /// The minimum duration a file is considered fresh, ignoring server headers.
  ///
  /// **Why:** Prevents excessive revalidation (304 checks) on volatile networks,
  /// even if the server says `no-cache` or `max-age=0`.
  final Duration minFresh;

  /// The maximum duration a file is considered fresh, forcing revalidation.
  ///
  /// **Why:** Ensures that even with aggressive caching, we eventually check
  /// for updates (e.g., a user changed their avatar).
  final Duration maxFresh;

  /// The maximum number of simultaneous network requests allowed for this bucket.
  ///
  /// **Why:** Prevents "thundering herd" issues where hundreds of thumbnails
  /// choke the bandwidth, causing timeouts for everyone.
  final int concurrentFetches;

  /// The maximum time to wait for the initial server response headers.
  ///
  /// Defaults to 15 seconds.
  final Duration responseTimeout;

  /// The maximum time to wait for a chunk of data during download.
  ///
  /// **Why:** Kills "zombie" connections that are open but transferring zero data.
  /// Defaults to 45 seconds.
  final Duration streamTimeout;

  /// The number of times to retry a failed request before giving up.
  ///
  /// Retries use exponential backoff.
  /// Defaults to 4.
  final int maxRetryAttempts;

  /// Yemen-optimized default configurations.
  ///
  /// These defaults are tuned for:
  /// - Slow/unreliable networks (longer timeouts, more retries)
  /// - Expensive data (longer cache retention)
  /// - Offline-first UX (generous stale periods)
  static const Map<ImageCacheBucket, CacheBucketConfig> configs = {
    ImageCacheBucket.avatar: CacheBucketConfig(
      key: 'img-avatar-v1',
      stalePeriod: Duration(days: 180),
      maxObjects: 2000,
      minFresh: Duration(hours: 12),
      maxFresh: Duration(days: 30),
      concurrentFetches: 4,
    ),
    ImageCacheBucket.icon: CacheBucketConfig(
      key: 'img-icon-v1',
      stalePeriod: Duration(days: 365),
      maxObjects: 500,
      minFresh: Duration(days: 30),
      maxFresh: Duration(days: 90),
      concurrentFetches: 4,
    ),
    ImageCacheBucket.thumbnail: CacheBucketConfig(
      key: 'img-thumb-v1',
      stalePeriod: Duration(days: 60),
      maxObjects: 3000,
      minFresh: Duration(days: 3),
      maxFresh: Duration(days: 14),
      concurrentFetches: 6,
    ),
    ImageCacheBucket.content: CacheBucketConfig(
      key: 'img-content-v1',
      stalePeriod: Duration(days: 30),
      maxObjects: 1000,
      minFresh: Duration(days: 1),
      maxFresh: Duration(days: 7),
      concurrentFetches: 4,
      streamTimeout: Duration(seconds: 60), // Larger files need more time
    ),
    ImageCacheBucket.banner: CacheBucketConfig(
      key: 'img-banner-v1',
      stalePeriod: Duration(days: 90),
      maxObjects: 200,
      minFresh: Duration(days: 7),
      maxFresh: Duration(days: 30),
      concurrentFetches: 2, // Fewer, larger downloads
      streamTimeout: Duration(seconds: 60),
    ),
  };
}
