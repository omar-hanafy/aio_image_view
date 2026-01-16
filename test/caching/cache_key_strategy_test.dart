import 'package:flutter_test/flutter_test.dart';
import 'package:aio_image_view/src/caching/cache_key_strategy.dart';

void main() {
  group('CacheKeyBuilder.normalizeUrl', () {
    test('returns original URL if no query params', () {
      const url = 'https://example.com/image.jpg';
      expect(CacheKeyBuilder.normalizeUrl(url), url);
    });

    test('returns sorted URL if no volatile params', () {
      const url = 'https://example.com/image.jpg?width=100&height=100';
      // Expect deterministic alphabetical sorting: height before width
      expect(
        CacheKeyBuilder.normalizeUrl(url),
        'https://example.com/image.jpg?height=100&width=100',
      );
    });

    test('strips Firebase Storage token param', () {
      const url =
          'https://firebasestorage.googleapis.com/image.jpg?alt=media&token=abc123';
      final result = CacheKeyBuilder.normalizeUrl(url);
      expect(result, 'https://firebasestorage.googleapis.com/image.jpg');
    });

    test('strips AWS SigV4 params', () {
      const url = 'https://s3.amazonaws.com/image.jpg'
          '?X-Amz-Algorithm=AWS4-HMAC-SHA256'
          '&X-Amz-Credential=AKID'
          '&X-Amz-Date=20230101T000000Z'
          '&X-Amz-Expires=3600'
          '&X-Amz-Signature=abc123'
          '&X-Amz-SignedHeaders=host';
      final result = CacheKeyBuilder.normalizeUrl(url);
      expect(result, 'https://s3.amazonaws.com/image.jpg');
    });

    test('strips CloudFront signing params', () {
      const url = 'https://cdn.example.com/image.jpg'
          '?Expires=1234567890'
          '&Signature=abc123'
          '&Key-Pair-Id=APKAI'
          '&Policy=base64policy';
      final result = CacheKeyBuilder.normalizeUrl(url);
      expect(result, 'https://cdn.example.com/image.jpg');
    });

    test('strips common cache buster params', () {
      const url = 'https://example.com/image.jpg'
          '?t=1234567890'
          '&ts=now'
          '&timestamp=123'
          '&_=xyz';
      final result = CacheKeyBuilder.normalizeUrl(url);
      expect(result, 'https://example.com/image.jpg');
    });

    test('preserves version params', () {
      const url = 'https://example.com/image.jpg'
          '?v=2'
          '&version=1.0';
      final result = CacheKeyBuilder.normalizeUrl(url);
      expect(result, contains('v=2'));
      expect(result, contains('version=1.0'));
    });

    test('preserves non-volatile params', () {
      const url = 'https://example.com/image.jpg'
          '?width=100'
          '&height=100'
          '&quality=80'
          '&token=abc123';
      final result = CacheKeyBuilder.normalizeUrl(url);
      expect(result, contains('width=100'));
      expect(result, contains('height=100'));
      expect(result, contains('quality=80'));
      expect(result, isNot(contains('token=abc123')));
    });

    test('sorts query params deterministically', () {
      const url1 = 'https://example.com/image.jpg?z=1&a=2&m=3';
      const url2 = 'https://example.com/image.jpg?a=2&m=3&z=1';
      expect(
        CacheKeyBuilder.normalizeUrl(url1),
        CacheKeyBuilder.normalizeUrl(url2),
      );
    });

    test('handles invalid URL gracefully', () {
      const invalid = 'not-a-valid-url';
      expect(CacheKeyBuilder.normalizeUrl(invalid), invalid);
    });

    test('case-insensitive param matching', () {
      const url = 'https://example.com/image.jpg'
          '?Token=abc123'
          '&X-AMZ-SIGNATURE=xyz';
      final result = CacheKeyBuilder.normalizeUrl(url);
      expect(result, 'https://example.com/image.jpg');
    });
  });

  group('CacheKeyBuilder.userScopedKey', () {
    test('creates user-scoped key with correct format', () {
      const url = 'https://example.com/image.jpg';
      final result = CacheKeyBuilder.userScopedKey(url, userId: 'user123');
      expect(result, 'u:user123|https://example.com/image.jpg');
    });

    test('normalizes URL before scoping', () {
      const url = 'https://example.com/image.jpg?token=abc123';
      final result = CacheKeyBuilder.userScopedKey(url, userId: 'user456');
      expect(result, 'u:user456|https://example.com/image.jpg');
    });
  });

  group('CacheKeyBuilder.build', () {
    test('explicit key takes highest priority', () {
      const url = 'https://example.com/image.jpg?token=abc123';
      final result = CacheKeyBuilder.build(
        url,
        explicitKey: 'my-explicit-key',
        userId: 'user123',
        isPrivate: true,
      );
      expect(result, 'my-explicit-key');
    });

    test('user-scoped key when isPrivate and userId provided', () {
      const url = 'https://example.com/private/image.jpg?token=abc';
      final result = CacheKeyBuilder.build(
        url,
        userId: 'user789',
        isPrivate: true,
      );
      expect(result, startsWith('u:user789|'));
      expect(result, contains('https://example.com/private/image.jpg'));
      expect(result, isNot(contains('token=')));
    });

    test('normalized URL when isPrivate but no userId', () {
      const url = 'https://example.com/image.jpg?token=abc123';
      final result = CacheKeyBuilder.build(
        url,
        isPrivate: true,
        // userId is null
      );
      expect(result, 'https://example.com/image.jpg');
      expect(result, isNot(startsWith('u:')));
    });

    test('normalized URL when userId but not isPrivate', () {
      const url = 'https://example.com/image.jpg?token=abc123';
      final result = CacheKeyBuilder.build(
        url,
        userId: 'user123',
        isPrivate: false,
      );
      expect(result, 'https://example.com/image.jpg');
      expect(result, isNot(startsWith('u:')));
    });

    test('normalized URL when neither private nor userId', () {
      const url = 'https://example.com/image.jpg?token=abc123';
      final result = CacheKeyBuilder.build(url);
      expect(result, 'https://example.com/image.jpg');
    });

    test('handles empty userId string', () {
      const url = 'https://example.com/image.jpg';
      final result = CacheKeyBuilder.build(
        url,
        userId: '',
        isPrivate: true,
      );
      // Empty userId should not create scoped key
      expect(result, isNot(startsWith('u:')));
    });
  });
}
