/// A battle-hardened image rendering and caching library for Flutter.
///
/// [ImageView] is designed for high-scale applications (10M+ users) operating in
/// hostile network environments. It provides a unified interface for network,
/// asset, file, and SVG images with built-in resilience strategies.
///
/// ## Features
///
/// *   **Resilient Caching:** Multi-bucket architecture (avatar, content, icon) with
///     optimized eviction policies.
/// *   **Network Resilience:** Circuit breakers, exponential backoff, and
///     captive portal detection.
/// *   **Smart Placeholders:** Shimmer effects, asset placeholders, and error widgets.
/// *   **Memory Optimization:** Automatic memory cache sizing based on widget dimensions.
///
/// ## Usage
///
/// ### Basic Network Image
/// ```dart
/// ImageView(
///   url: 'https://example.com/image.jpg',
///   height: 200,
///   width: 200,
///   radius: 8,
/// )
/// ```
///
/// ### Private User Content (Auth-Scoped)
/// ```dart
/// ImageView(
///   url: 'https://api.example.com/user/avatar.jpg',
///   cacheBucket: ImageCacheBucket.avatar,
///   isPrivateImage: true, // Keys cache to current userId
///   circular: true,
/// )
/// ```
///
/// ### App Lifecycle
/// Initialize the cache registry at startup:
/// ```dart
/// void main() {
///   imageCaches.initialize(
///     metricsCallback: kDebugMode ? debugMetricsCallback : null,
///   );
///   runApp(MyApp());
/// }
/// ```
///
/// On login/logout, manage user scope:
/// ```dart
/// // Login
/// imageCaches.setUserId('user_123');
///
/// // Logout
/// await imageCaches.clearUserCaches();
/// imageCaches.setUserId(null);
/// ```
library;

export 'src/aio_image_view.dart';
export 'src/caching/cache_config.dart';
export 'src/caching/cache_metrics.dart';
export 'src/caching/image_cache_registry.dart';
