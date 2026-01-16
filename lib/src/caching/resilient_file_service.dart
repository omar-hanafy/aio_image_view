import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:aio_image_view/src/caching/cache_config.dart';
import 'package:aio_image_view/src/caching/cache_metrics.dart';
import 'package:aio_image_view/src/caching/circuit_breaker.dart';
import 'package:pool/pool.dart';

/// A network transport layer designed for hostile network environments.
///
/// **Role:**
/// [ResilientFileService] replaces the standard `HttpFileService` in `flutter_cache_manager`.
/// It assumes the network is unreliable and actively fights to get the image through.
///
/// **Features:**
/// *   **Exponential Backoff:** Prevents retry storms.
/// *   **Stream Watchdog:** Kills connections that stall (transmit 0 bytes) for too long.
/// *   **Captive Portal Detection:** Detects if a "200 OK" response is actually a WiFi login page.
/// *   **Stale-if-Error:** If revalidation fails, returns the cached image instead of throwing.
/// *   **Circuit Breaker Integration:** Fails fast if a host is down.
class ResilientFileService extends FileService {
  ResilientFileService({
    http.Client? httpClient,
    required this.config,
    this.circuitBreaker,
    this.metricsCallback,
    this.userAgent = 'SaberApp/1.0 (Flutter)',
    Future<void> Function()? dnsProbe,
  })  : _httpClient = httpClient ?? _sharedClient,
        _dnsProbe = dnsProbe ?? _defaultDnsProbe {
    // CRITICAL: Lower concurrency prevents bandwidth death spiral on slow networks.
    // Default 10 on a 50kbps connection = 5kbps each = ALL timeout.
    // 4-6 is the sweet spot.
    concurrentFetches = config.concurrentFetches;
  }

  /// Shared HTTP client for TCP Keep-Alive.
  /// Saves 3-4 round trips (DNS + TCP + TLS handshake) per request.
  static final http.Client _sharedClient = http.Client();

  /// Global concurrency limiter shared by all instances.
  ///
  /// Prevents "bandwidth death spiral" where multiple buckets (avatar + feed + thumbnails)
  /// sum up to 14+ concurrent downloads, overwhelming a 2G connection.
  static Pool _globalPool = Pool(6);

  /// Reset the global pool (for testing only).
  static void resetGlobalPool({int capacity = 6}) {
    _globalPool = Pool(capacity);
  }

  final http.Client _httpClient;
  final CacheBucketConfig config;
  final HostCircuitBreaker? circuitBreaker;
  final CacheMetricsCallback? metricsCallback;
  final String userAgent;
  final Future<void> Function() _dnsProbe;

  final _rng = Random();

  /// Lightweight DNS probe to ensure we aren't retrying in a dead zone.
  ///
  /// **Why:** On mobile networks, the OS often reports "connected" even when
  /// the radio is dead or in a tunnel. Probing prevents wasting retry attempts.
  Future<void> _ensureConnectivity(String host) async {
    // If a custom probe is provided, use it (ignoring host arg for back-compat)
    if (_dnsProbe != _defaultDnsProbe) {
      await _dnsProbe();
      return;
    }
    // Otherwise probe the specific host
    await _defaultDnsProbe(host);
  }

  /// Default DNS probe implementation.
  ///
  /// **Strategy:** Resolves the target host.
  /// **Why:** Probing `google.com` is unreliable in regions where Google is blocked.
  /// Probing the actual target guarantees the route is open.
  static Future<void> _defaultDnsProbe([String host = 'google.com']) async {
    try {
      final result = await InternetAddress.lookup(
        host,
      ).timeout(const Duration(seconds: 4));
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) return;
    } catch (_) {
      throw const SocketException('No Internet Connectivity');
    }
  }

  /// HTTP status codes that indicate temporary issues worth retrying.
  static const _retryableStatusCodes = <int>{
    408, // Request Timeout
    429, // Too Many Requests
    500, // Internal Server Error
    502, // Bad Gateway
    503, // Service Unavailable
    504, // Gateway Timeout
    // Cloudflare/CDN specific
    520, // Web Server Returned an Unknown Error
    521, // Web Server Is Down
    522, // Connection Timed Out
    523, // Origin Is Unreachable
    524, // A Timeout Occurred
    525, // SSL Handshake Failed
  };

  /// File extensions that indicate captive portal / error pages.
  /// If server returns 200 OK with HTML content, it's likely a login page.
  static const _poisonedExtensions = <String>{'.html', '.json', '.txt', '.xml'};

  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    final uri = Uri.parse(url);
    final host = uri.host;

    // 1. Circuit breaker check - fail fast if host is known-bad
    if (!(circuitBreaker?.allowRequest(host) ?? true)) {
      metricsCallback?.call(
        CacheMetricEvent(
          type: CacheMetricEventType.circuitBreakerTripped,
          url: url,
          host: host,
        ),
      );

      // If this is a revalidation request, return stale content
      if (_isRevalidationRequest(headers)) {
        return _SyntheticNotModifiedResponse(
          validTill: DateTime.now().add(config.minFresh),
          eTag: _getETagFromHeaders(headers),
        );
      }

      throw HttpExceptionWithStatus(
        503,
        'Circuit breaker open for $host',
        uri: uri,
      );
    }

    // 2. Header optimization
    final safeHeaders = Map<String, String>.from(headers ?? {});
    safeHeaders.putIfAbsent(HttpHeaders.userAgentHeader, () => userAgent);
    safeHeaders.putIfAbsent('Accept-Encoding', () => 'gzip');

    final isRevalidation = _isRevalidationRequest(headers);
    Object? lastError;

    // Acquire global slot - wait if too many concurrent downloads
    // This is critical for Yemen-grade networks
    return _globalPool.withResource(() async {
      for (var attempt = 0; attempt < config.maxRetryAttempts; attempt++) {
        final stopwatch = Stopwatch()..start();

        try {
          // 3. Fail fast if we have no DNS resolution (on retries)
          if (attempt > 0) {
            await _ensureConnectivity(host);
          }

          metricsCallback?.call(
            CacheMetricEvent(
              type: CacheMetricEventType.fetchStarted,
              url: url,
              attemptNumber: attempt,
            ),
          );

          // 4. Adaptive timeout - more patience on later attempts
          final timeout =
              config.responseTimeout + Duration(seconds: attempt * 3);

          final response = await _fetchWithInnerService(
            url,
            safeHeaders,
            timeout,
          );

          // 5. Check for retryable status codes
          if (_retryableStatusCodes.contains(response.statusCode)) {
            await _drainSafely(response);

            metricsCallback?.call(
              CacheMetricEvent(
                type: CacheMetricEventType.retryAttempt,
                url: url,
                statusCode: response.statusCode,
                attemptNumber: attempt,
              ),
            );

            throw _RetryableStatusException(response.statusCode);
          }

          // 6. Captive portal detection (Model A's key insight)
          // If server returns 200 OK but sends HTML, it's likely a WiFi login page
          if (response.statusCode == 200) {
            final ext = response.fileExtension.toLowerCase();
            if (_poisonedExtensions.contains(ext)) {
              await _drainSafely(response);

              metricsCallback?.call(
                CacheMetricEvent(
                  type: CacheMetricEventType.captivePortalDetected,
                  url: url,
                ),
              );

              throw const HttpException(
                'Captive portal detected (HTML/JSON content-type for image)',
              );
            }
          }

          // 7. Success - wrap with stream timeout + ValidTill clamping + Sniffing
          circuitBreaker?.recordSuccess(host);

          metricsCallback?.call(
            CacheMetricEvent(
              type: CacheMetricEventType.fetchSucceeded,
              url: url,
              statusCode: response.statusCode,
              duration: stopwatch.elapsed,
            ),
          );

          return _ResilientResponse(
            inner: response,
            streamTimeout: config.streamTimeout,
            minFresh: config.minFresh,
            maxFresh: config.maxFresh,
          );
        } on TimeoutException catch (e) {
          lastError = e;
          circuitBreaker?.recordFailure(host);

          if (attempt == config.maxRetryAttempts - 1) {
            if (isRevalidation) {
              metricsCallback?.call(
                CacheMetricEvent(
                  type: CacheMetricEventType.staleIfErrorServed,
                  url: url,
                ),
              );
              return _SyntheticNotModifiedResponse(
                validTill: DateTime.now().add(config.minFresh),
                eTag: _getETagFromHeaders(headers),
              );
            }
            rethrow;
          }

          metricsCallback?.call(
            CacheMetricEvent(
              type: CacheMetricEventType.retryAttempt,
              url: url,
              attemptNumber: attempt,
              errorMessage: 'Timeout',
            ),
          );

          await _backoff(attempt);
        } on _RetryableStatusException catch (e) {
          lastError = e;
          circuitBreaker?.recordFailure(host);

          if (attempt == config.maxRetryAttempts - 1) {
            if (isRevalidation) {
              metricsCallback?.call(
                CacheMetricEvent(
                  type: CacheMetricEventType.staleIfErrorServed,
                  url: url,
                ),
              );
              return _SyntheticNotModifiedResponse(
                validTill: DateTime.now().add(config.minFresh),
                eTag: _getETagFromHeaders(headers),
              );
            }
            throw HttpExceptionWithStatus(
              e.statusCode,
              'Retry exhausted for $url (HTTP ${e.statusCode})',
              uri: uri,
            );
          }

          await _backoff(attempt);
        } on Object catch (e) {
          lastError = e;
          circuitBreaker?.recordFailure(host);

          if (!_isRetryable(e) || attempt == config.maxRetryAttempts - 1) {
            if (isRevalidation && _isRetryable(e)) {
              metricsCallback?.call(
                CacheMetricEvent(
                  type: CacheMetricEventType.staleIfErrorServed,
                  url: url,
                ),
              );
              return _SyntheticNotModifiedResponse(
                validTill: DateTime.now().add(config.minFresh),
                eTag: _getETagFromHeaders(headers),
              );
            }

            metricsCallback?.call(
              CacheMetricEvent(
                type: CacheMetricEventType.fetchFailed,
                url: url,
                errorMessage: e.toString(),
              ),
            );

            rethrow;
          }

          metricsCallback?.call(
            CacheMetricEvent(
              type: CacheMetricEventType.retryAttempt,
              url: url,
              attemptNumber: attempt,
              errorMessage: e.runtimeType.toString(),
            ),
          );

          await _backoff(attempt);
        }
      }

      // Should never reach here
      throw lastError ?? StateError('ResilientFileService failed unexpectedly');
    });
  }

  Future<FileServiceResponse> _fetchWithInnerService(
    String url,
    Map<String, String> headers,
    Duration timeout,
  ) async {
    final inner = HttpFileService(httpClient: _httpClient);
    return inner.get(url, headers: headers).timeout(timeout);
  }

  Future<void> _drainSafely(FileServiceResponse response) async {
    try {
      await response.content.drain<void>().timeout(const Duration(seconds: 5));
    } catch (_) {
      // Ignore drain errors - we're retrying anyway
    }
  }

  Future<void> _backoff(int attempt) async {
    // Exponential: 500ms, 1s, 2s, 4s...
    final expMs = 500 * (1 << attempt);
    // Jitter: +0-500ms to prevent thundering herd
    final jitterMs = _rng.nextInt(500);
    // Cap at 15 seconds
    final delayMs = (expMs + jitterMs).clamp(0, 15000).toInt();
    await Future<void>.delayed(Duration(milliseconds: delayMs));
  }

  /// Extract eTag from headers (case-insensitive).
  String? _getETagFromHeaders(Map<String, String>? headers) {
    if (headers == null) return null;
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'if-none-match') {
        return entry.value;
      }
    }
    return null;
  }

  /// Check if this is a cache revalidation request (has conditional headers).
  bool _isRevalidationRequest(Map<String, String>? headers) {
    if (headers == null) return false;
    final lowerKeys = headers.keys.map((k) => k.toLowerCase());
    return lowerKeys.contains('if-none-match') ||
        lowerKeys.contains('if-modified-since');
  }

  /// Check if an error is retryable (transient network issue).
  bool _isRetryable(Object error) {
    if (error is TimeoutException) return true;
    if (error is SocketException) return true;
    if (error is HandshakeException) return true;
    if (error is TlsException) return true;
    if (error is http.ClientException) return true;
    if (error is HttpException) return true;

    // Fallback: check error message for common patterns
    final msg = error.toString().toLowerCase();
    return msg.contains('timed out') ||
        msg.contains('timeout') ||
        msg.contains('connection reset') ||
        msg.contains('connection closed') ||
        msg.contains('handshake');
  }
}

/// Internal exception for control flow during retries.
class _RetryableStatusException implements Exception {
  _RetryableStatusException(this.statusCode);
  final int statusCode;

  @override
  String toString() => 'RetryableStatusException($statusCode)';
}

/// Wrapper that adds:
/// 1. Stream timeout (dead connection killer)
/// 2. ValidTill clamping (prevents constant revalidation)
/// 3. Content sniffing (captive portal detection)
class _ResilientResponse implements FileServiceResponse {
  _ResilientResponse({
    required this.inner,
    required this.streamTimeout,
    required this.minFresh,
    required this.maxFresh,
  });
  final FileServiceResponse inner;
  final Duration streamTimeout;
  final Duration minFresh;
  final Duration maxFresh;
  final DateTime _receivedAt = DateTime.now();

  @override
  int get statusCode => inner.statusCode;

  @override
  int? get contentLength => inner.contentLength;

  @override
  String? get eTag => inner.eTag;

  @override
  String get fileExtension => inner.fileExtension;

  @override
  Stream<List<int>> get content {
    // 1. Apply stream timeout
    final timedStream = inner.content.timeout(
      streamTimeout,
      onTimeout: (sink) {
        sink.addError(
          TimeoutException('Stream stalled (no data for $streamTimeout)'),
        );
        sink.close();
      },
    );

    // 2. Validate content signatures (sniffing)
    return _validateContentStream(timedStream);
  }

  @override
  DateTime get validTill {
    // Clamp validTill to [minFresh, maxFresh] range
    final serverValidTill = inner.validTill;
    final minTime = _receivedAt.add(minFresh);
    final maxTime = _receivedAt.add(maxFresh);

    if (serverValidTill.isBefore(minTime)) return minTime;
    if (serverValidTill.isAfter(maxTime)) return maxTime;
    return serverValidTill;
  }

  /// Sniff first chunk to detect captive portals masquerading as 200 OK.
  Stream<List<int>> _validateContentStream(Stream<List<int>> stream) async* {
    var checked = false;

    await for (final chunk in stream) {
      if (!checked && chunk.isNotEmpty) {
        // Skip leading whitespace to find the first real byte
        var i = 0;
        while (i < chunk.length && _isWhitespace(chunk[i])) {
          i++;
        }

        if (i < chunk.length) {
          final firstByte = chunk[i];
          // Check for HTML/JSON signatures
          if (firstByte == 0x3C) {
            // '<' (HTML/XML)
            throw const HttpException(
              'Captive portal detected (HTML signature in content)',
            );
          }
          if (firstByte == 0x7B) {
            // '{' (JSON object)
            throw const HttpException(
              'Captive portal detected (JSON signature in content)',
            );
          }
          if (firstByte == 0x5B) {
            // '[' (JSON array)
            throw const HttpException(
              'Captive portal detected (JSON array signature in content)',
            );
          }
        }
        checked = true;
      }
      yield chunk;
    }
  }

  bool _isWhitespace(int byte) {
    return byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D;
  }
}

/// Synthetic 304 Not Modified response for stale-if-error behavior.
///
/// When a revalidation request fails due to network issues, we return this
/// synthetic response to tell CacheManager to keep using the cached file.
/// This provides the best offline UX - showing stale content instead of errors.
class _SyntheticNotModifiedResponse implements FileServiceResponse {
  _SyntheticNotModifiedResponse({required this.validTill, this.eTag});
  @override
  final DateTime validTill;

  @override
  final String? eTag;

  @override
  int get statusCode => HttpStatus.notModified;

  @override
  Stream<List<int>> get content => const Stream.empty();

  @override
  int? get contentLength => 0;

  @override
  String get fileExtension => '';
}
