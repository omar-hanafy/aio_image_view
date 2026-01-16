import 'package:flutter_test/flutter_test.dart';
import 'package:aio_image_view/src/caching/cache_metrics.dart';

void main() {
  group('CacheMetricEventType', () {
    test('has all required event types', () {
      const types = CacheMetricEventType.values;
      expect(types, contains(CacheMetricEventType.fetchStarted));
      expect(types, contains(CacheMetricEventType.fetchSucceeded));
      expect(types, contains(CacheMetricEventType.fetchFailed));
      expect(types, contains(CacheMetricEventType.retryAttempt));
      expect(types, contains(CacheMetricEventType.circuitBreakerTripped));
      expect(types, contains(CacheMetricEventType.staleIfErrorServed));
      expect(types, contains(CacheMetricEventType.captivePortalDetected));
    });
  });

  group('CacheMetricEvent', () {
    test('stores all required fields', () {
      const event = CacheMetricEvent(
        type: CacheMetricEventType.fetchSucceeded,
        url: 'https://example.com/image.jpg',
        statusCode: 200,
        attemptNumber: 0,
        duration: Duration(milliseconds: 500),
        errorMessage: null,
        host: 'example.com',
      );

      expect(event.type, CacheMetricEventType.fetchSucceeded);
      expect(event.url, 'https://example.com/image.jpg');
      expect(event.statusCode, 200);
      expect(event.attemptNumber, 0);
      expect(event.duration, const Duration(milliseconds: 500));
      expect(event.errorMessage, isNull);
      expect(event.host, 'example.com');
    });

    test('allows nullable fields', () {
      const event = CacheMetricEvent(
        type: CacheMetricEventType.fetchStarted,
        url: 'https://example.com/image.jpg',
      );

      expect(event.statusCode, isNull);
      expect(event.attemptNumber, isNull);
      expect(event.duration, isNull);
      expect(event.errorMessage, isNull);
      expect(event.host, isNull);
    });

    test('toString has correct format', () {
      const event = CacheMetricEvent(
        type: CacheMetricEventType.retryAttempt,
        url: 'https://api.example.com/photos/123.jpg',
        statusCode: 503,
        attemptNumber: 2,
      );

      final str = event.toString();
      expect(str, contains('CacheMetricEvent'));
      expect(str, contains('retryAttempt'));
      expect(str, contains('url:'));
      expect(str, contains('status: 503'));
      expect(str, contains('attempt: 2'));
    });

    test('stores error message for failed events', () {
      const event = CacheMetricEvent(
        type: CacheMetricEventType.fetchFailed,
        url: 'https://example.com/broken.jpg',
        errorMessage: 'Connection reset by peer',
      );

      expect(event.errorMessage, 'Connection reset by peer');
    });

    test('stores host for circuit breaker events', () {
      const event = CacheMetricEvent(
        type: CacheMetricEventType.circuitBreakerTripped,
        url: 'https://cdn.example.com/asset.png',
        host: 'cdn.example.com',
      );

      expect(event.host, 'cdn.example.com');
    });
  });

  // Note: debugMetricsCallback is not easily testable since it only logs
  // in kDebugMode and has no return value. We focus on testing the event
  // model and URL shortening logic.
}
