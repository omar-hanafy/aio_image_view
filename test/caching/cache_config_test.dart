import 'package:flutter_test/flutter_test.dart';
import 'package:aio_image_view/src/caching/cache_config.dart';

void main() {
  group('ImageCacheBucket', () {
    test('has all 5 required buckets', () {
      const buckets = ImageCacheBucket.values;
      expect(buckets.length, 5);
      expect(buckets, contains(ImageCacheBucket.avatar));
      expect(buckets, contains(ImageCacheBucket.icon));
      expect(buckets, contains(ImageCacheBucket.thumbnail));
      expect(buckets, contains(ImageCacheBucket.content));
      expect(buckets, contains(ImageCacheBucket.banner));
    });
  });

  group('CacheBucketConfig', () {
    test('configs map covers all enum values', () {
      for (final bucket in ImageCacheBucket.values) {
        expect(
          CacheBucketConfig.configs.containsKey(bucket),
          isTrue,
          reason: 'Missing config for $bucket',
        );
      }
    });

    test('all keys are unique', () {
      final keys = CacheBucketConfig.configs.values.map((c) => c.key).toList();
      final uniqueKeys = keys.toSet();
      expect(keys.length, uniqueKeys.length, reason: 'Duplicate keys found');
    });

    test('all keys follow versioning pattern', () {
      for (final config in CacheBucketConfig.configs.values) {
        expect(
          config.key,
          matches(RegExp(r'-v\d+$')),
          reason: 'Key "${config.key}" should end with version suffix like -v1',
        );
      }
    });

    test('minFresh is less than maxFresh for all configs', () {
      for (final entry in CacheBucketConfig.configs.entries) {
        final config = entry.value;
        expect(
          config.minFresh < config.maxFresh,
          isTrue,
          reason: 'minFresh >= maxFresh for ${entry.key}',
        );
      }
    });

    test('stalePeriod is greater than maxFresh for all configs', () {
      for (final entry in CacheBucketConfig.configs.entries) {
        final config = entry.value;
        expect(
          config.stalePeriod > config.maxFresh,
          isTrue,
          reason: 'stalePeriod <= maxFresh for ${entry.key}',
        );
      }
    });

    test('concurrentFetches is positive for all configs', () {
      for (final entry in CacheBucketConfig.configs.entries) {
        final config = entry.value;
        expect(
          config.concurrentFetches > 0,
          isTrue,
          reason: 'concurrentFetches <= 0 for ${entry.key}',
        );
      }
    });

    test('maxObjects is positive for all configs', () {
      for (final entry in CacheBucketConfig.configs.entries) {
        final config = entry.value;
        expect(
          config.maxObjects > 0,
          isTrue,
          reason: 'maxObjects <= 0 for ${entry.key}',
        );
      }
    });

    group('Yemen-optimized defaults', () {
      test('avatar config has long stalePeriod', () {
        final config = CacheBucketConfig.configs[ImageCacheBucket.avatar]!;
        expect(
          config.stalePeriod.inDays,
          greaterThanOrEqualTo(90),
          reason: 'Avatar stalePeriod should be long for hostile networks',
        );
      });

      test('icon config has very long stalePeriod', () {
        final config = CacheBucketConfig.configs[ImageCacheBucket.icon]!;
        expect(
          config.stalePeriod.inDays,
          greaterThanOrEqualTo(180),
          reason: 'Icon stalePeriod should be very long',
        );
      });

      test('thumbnail config has high maxObjects', () {
        final config = CacheBucketConfig.configs[ImageCacheBucket.thumbnail]!;
        expect(
          config.maxObjects,
          greaterThanOrEqualTo(2000),
          reason: 'Thumbnail cache should hold many objects',
        );
      });

      test('content config has extended streamTimeout', () {
        final config = CacheBucketConfig.configs[ImageCacheBucket.content]!;
        expect(
          config.streamTimeout.inSeconds,
          greaterThanOrEqualTo(45),
          reason: 'Content streamTimeout should be generous for large files',
        );
      });

      test('banner config has low concurrentFetches', () {
        final config = CacheBucketConfig.configs[ImageCacheBucket.banner]!;
        expect(
          config.concurrentFetches,
          lessThanOrEqualTo(4),
          reason: 'Banner concurrentFetches should be low for large downloads',
        );
      });
    });
  });
}
