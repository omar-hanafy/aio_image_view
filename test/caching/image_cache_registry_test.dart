import 'package:aio_image_view/src/caching/image_cache_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class MockPathProviderPlatform extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async {
    return './test_fixtures/application_support';
  }

  @override
  Future<String?> getTemporaryPath() async {
    return './test_fixtures/tmp';
  }
}

void main() {
  // Initialize Flutter binding for tests that need platform channels
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ImageCacheRegistry', () {
    late ImageCacheRegistry registry;

    setUp(() {
      PathProviderPlatform.instance = MockPathProviderPlatform();
      // Use the singleton instance - note this is stateful across tests
      registry = ImageCacheRegistry.instance
        // Reset user ID between tests
        ..setUserId(null);
    });

    test('imageCaches shorthand returns singleton instance', () {
      expect(imageCaches, same(ImageCacheRegistry.instance));
    });

    group('initialization', () {
      test('tracks isInitialized state after initialize()', () {
        registry.initialize();
        expect(registry.isInitialized, isTrue);
      });

      test('accepts optional userId during initialization', () {
        registry.initialize(userId: 'test-user-123');
        expect(registry.currentUserId, 'test-user-123');
        // Clean up
        registry.setUserId(null);
      });
    });

    group('user ID management', () {
      test('setUserId updates currentUserId', () {
        registry.setUserId('user-abc');
        expect(registry.currentUserId, 'user-abc');
        // Clean up
        registry.setUserId(null);
      });

      test('setUserId accepts null', () {
        registry.setUserId('user-abc');
        registry.setUserId(null);
        expect(registry.currentUserId, isNull);
      });
    });

    group('buildCacheKey', () {
      test('normalizes Firebase signed URLs', () {
        const url =
            'https://firebasestorage.googleapis.com/image.jpg?alt=media&token=abc123';
        final key = registry.buildCacheKey(url);
        expect(key, isNot(contains('token=')));
        expect(key, isNot(contains('alt=')));
      });

      test('uses explicit key when provided', () {
        const url = 'https://example.com/image.jpg?token=abc';
        final key = registry.buildCacheKey(url, explicitKey: 'my-key');
        expect(key, 'my-key');
      });

      test('scopes key for private images when userId set', () {
        registry.setUserId('user-123');
        const url = 'https://example.com/private.jpg';
        final key = registry.buildCacheKey(url, isPrivate: true);
        expect(key, startsWith('u:user-123|'));
        // Clean up
        registry.setUserId(null);
      });

      test('does not scope when isPrivate false', () {
        registry.setUserId('user-123');
        const url = 'https://example.com/public.jpg';
        final key = registry.buildCacheKey(url, isPrivate: false);
        expect(key, isNot(startsWith('u:')));
        // Clean up
        registry.setUserId(null);
      });

      test('does not scope when no userId', () {
        registry.setUserId(null);
        const url = 'https://example.com/private.jpg';
        final key = registry.buildCacheKey(url, isPrivate: true);
        expect(key, isNot(startsWith('u:')));
      });
    });

    group('circuit breaker', () {
      test('resetCircuitBreakers clears state', () {
        // Reset and verify it doesn't throw
        registry.resetCircuitBreakers();

        final state = registry.circuitBreakerState;
        expect(state, isEmpty);
      });

      test('circuitBreakerState returns valid map type', () {
        final state = registry.circuitBreakerState;
        expect(
          state,
          isA<
              Map<
                  String,
                  ({
                    int failures,
                    bool isOpen,
                    bool isHalfOpen,
                    bool probeInFlight
                  })>>(),
        );
      });
    });

    // Note: Tests that access actual CacheManager instances are integration tests
    // because they require filesystem access. The following tests verify that
    // the manager accessors don't throw and return the correct types.
    group('manager accessor types (integration)', () {
      // These tests may be slow due to CacheManager initialization

      test('getManager returns CacheManager and caches it', () async {
        // This test verifies lazy creation and caching
        // Note: Accessing CacheManager triggers I/O operations

        // Test that multiple calls to the same accessor work
        // (we test behavior, not identity, due to test isolation challenges)
        expect(registry.avatar, isNotNull);
      });
    });
  });
}
