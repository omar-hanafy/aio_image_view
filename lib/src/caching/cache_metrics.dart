import 'package:flutter/foundation.dart';

/// Callback for cache metrics (useful for debugging/analytics).
typedef CacheMetricsCallback = void Function(CacheMetricEvent event);

/// Types of cache metric events.
enum CacheMetricEventType {
  /// Download started
  fetchStarted,

  /// Download completed successfully
  fetchSucceeded,

  /// Download failed
  fetchFailed,

  /// Retry attempt initiated
  retryAttempt,

  /// Circuit breaker tripped for a host
  circuitBreakerTripped,

  /// Stale content served due to network error
  staleIfErrorServed,

  /// Captive portal detected and rejected
  captivePortalDetected,
}

/// A cache metric event for tracking and debugging.
class CacheMetricEvent {
  const CacheMetricEvent({
    required this.type,
    required this.url,
    this.statusCode,
    this.attemptNumber,
    this.duration,
    this.errorMessage,
    this.host,
  });

  /// Type of event
  final CacheMetricEventType type;

  /// URL being fetched
  final String url;

  /// HTTP status code (if applicable)
  final int? statusCode;

  /// Which retry attempt this was (0-indexed)
  final int? attemptNumber;

  /// Duration of the operation
  final Duration? duration;

  /// Error message (if applicable)
  final String? errorMessage;

  /// Host that was affected (for circuit breaker events)
  final String? host;

  @override
  String toString() =>
      'CacheMetricEvent($type, url: $url, status: $statusCode, attempt: $attemptNumber)';
}

/// Debug metrics logger for development builds.
///
/// Prints cache events to console with emoji prefixes for easy scanning.
/// Only logs in debug mode.
void debugMetricsCallback(CacheMetricEvent event) {
  if (!kDebugMode) return;

  final shortUrl = _shortenUrl(event.url);

  switch (event.type) {
    case CacheMetricEventType.fetchStarted:
      // Too noisy, skip
      break;
    case CacheMetricEventType.fetchSucceeded:
      debugPrint('✅ [ImageCache] $shortUrl loaded in ${event.duration}');
      break;
    case CacheMetricEventType.fetchFailed:
      debugPrint(
        '❌ [ImageCache] $shortUrl failed: ${event.errorMessage ?? event.statusCode}',
      );
      break;
    case CacheMetricEventType.retryAttempt:
      debugPrint(
        '🔄 [ImageCache] Retry ${(event.attemptNumber ?? 0) + 1} for $shortUrl (${event.statusCode})',
      );
      break;
    case CacheMetricEventType.staleIfErrorServed:
      debugPrint('📦 [ImageCache] Serving stale for $shortUrl');
      break;
    case CacheMetricEventType.circuitBreakerTripped:
      debugPrint('🔴 [ImageCache] Circuit breaker open for ${event.host}');
      break;
    case CacheMetricEventType.captivePortalDetected:
      debugPrint('🚫 [ImageCache] Captive portal detected for $shortUrl');
      break;
  }
}

/// Shorten URL for logging (keep host + last path segment)
String _shortenUrl(String url) {
  try {
    final uri = Uri.parse(url);
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final lastSegment = segments.isNotEmpty ? segments.last : '';
    return '${uri.host}/.../$lastSegment';
  } catch (_) {
    return url.length > 50 ? '${url.substring(0, 50)}...' : url;
  }
}
