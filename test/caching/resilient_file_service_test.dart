import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:aio_image_view/src/caching/cache_config.dart';
import 'package:aio_image_view/src/caching/circuit_breaker.dart';
import 'package:aio_image_view/src/caching/resilient_file_service.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';

class MockHttpClient extends Mock implements http.Client {}

class MockStreamedResponse extends Mock implements http.StreamedResponse {}

class FakeUri extends Fake implements Uri {}

class FakeBaseRequest extends Fake implements http.BaseRequest {}

CacheBucketConfig testConfig({
  int maxRetryAttempts = 3,
  Duration responseTimeout = const Duration(milliseconds: 100),
}) {
  return CacheBucketConfig(
    key: 'test-cache',
    stalePeriod: const Duration(days: 1),
    maxObjects: 100,
    minFresh: const Duration(hours: 1),
    maxFresh: const Duration(days: 1),
    concurrentFetches: 2,
    responseTimeout: responseTimeout,
    streamTimeout: const Duration(milliseconds: 100),
    maxRetryAttempts: maxRetryAttempts,
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeUri());
    registerFallbackValue(FakeBaseRequest());
  });

  group('ResilientFileService', () {
    late MockHttpClient mockClient;
    late CacheBucketConfig config;

    setUp(() {
      ResilientFileService.resetGlobalPool();
      mockClient = MockHttpClient();
      config = testConfig();
    });

    test('performs DNS probe before retrying', () async {
      var dnsChecks = 0;
      final service = ResilientFileService(
        httpClient: mockClient,
        config: config,
        dnsProbe: () async {
          dnsChecks++;
        },
      );

      // Fail first attempt, succeed second
      var callCount = 0;
      when(() => mockClient.send(any())).thenAnswer((_) async {
        callCount++;
        if (callCount == 1) throw const SocketException('Network error');

        final response = MockStreamedResponse();
        when(() => response.statusCode).thenReturn(200);
        when(() => response.headers).thenReturn({});
        when(() => response.contentLength).thenReturn(0);
        when(() => response.stream).thenAnswer(
          (_) => http.ByteStream(Stream.value(Uint8List(0))),
        );
        return response;
      });

      await service.get('https://example.com/image.jpg');

      // DNS probe should happen before retry (attempt > 0)
      expect(dnsChecks, greaterThan(0));
    });

    test('fails fast if DNS probe fails', () async {
      final service = ResilientFileService(
        httpClient: mockClient,
        config: config,
        dnsProbe: () async {
          throw const SocketException('No DNS');
        },
      );

      when(() => mockClient.send(any())).thenAnswer((_) {
        return Future.error(const SocketException('Fail 1'));
      });

      expect(
        () => service.get('https://example.com/image.jpg'),
        throwsA(isA<SocketException>()),
      );
    });

    test('retries on TlsException', () async {
      final service = ResilientFileService(
        httpClient: mockClient,
        config: config,
        dnsProbe: () async {},
      );

      // Fail 1st with TlsException, succeed 2nd
      var callCount = 0;
      when(() => mockClient.send(any())).thenAnswer((_) async {
        callCount++;
        if (callCount == 1) throw const TlsException('Handshake failed');

        final response = MockStreamedResponse();
        when(() => response.statusCode).thenReturn(200);
        when(() => response.headers).thenReturn({});
        when(() => response.contentLength).thenReturn(0);
        when(() => response.stream).thenAnswer(
          (_) => http.ByteStream(Stream.value(Uint8List(0))),
        );
        return response;
      });

      await service.get('https://example.com/image.jpg');

      // Should have tried twice
      verify(() => mockClient.send(any())).called(2);
    });

    test('uses circuit breaker allowRequest', () async {
      final breaker = HostCircuitBreaker(failureThreshold: 1);
      final service = ResilientFileService(
        httpClient: mockClient,
        config: config,
        circuitBreaker: breaker,
      );

      // Trip the breaker
      breaker.recordFailure('example.com');

      expect(
        () => service.get('https://example.com/image.jpg'),
        throwsA(isA<HttpExceptionWithStatus>()),
      );

      verifyNever(() => mockClient.send(any()));
    });

    test('preserves eTag in synthetic 304 response', () async {
      final service = ResilientFileService(
        httpClient: mockClient,
        config: config,
        dnsProbe: () async {}, // Mock DNS probe
      );

      // Setup failure to trigger synthetic response
      when(() => mockClient.send(any())).thenThrow(
        const SocketException('Offline'),
      );

      final headers = {'If-None-Match': '"cached-etag"'};

      // Perform request that looks like a revalidation
      final response = await service.get(
        'https://example.com/image.jpg',
        headers: headers,
      );

      expect(response.statusCode, 304);
      expect(response.eTag, '"cached-etag"');
    });
    test('throws HttpException when captive portal (HTML) is detected',
        () async {
      final service = ResilientFileService(
        httpClient: mockClient,
        config: config,
        dnsProbe: () async {},
      );

      when(() => mockClient.send(any())).thenAnswer((_) async {
        final response = MockStreamedResponse();
        when(() => response.statusCode).thenReturn(200);
        when(() => response.headers).thenReturn({});
        when(() => response.contentLength).thenReturn(100);
        // Stream starts with HTML signature
        when(() => response.stream).thenAnswer(
          (_) => http.ByteStream(
            Stream.value(Uint8List.fromList(
                '<html><body>Login</body></html>'.codeUnits)),
          ),
        );
        return response;
      });

      final response = await service.get('https://example.com/image.jpg');

      expect(
        response.content.drain(),
        throwsA(isA<HttpException>().having(
          (e) => e.message,
          'message',
          contains('Captive portal detected'),
        )),
      );
    });
  });
}
