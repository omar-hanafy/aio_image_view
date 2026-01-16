import 'package:flutter_test/flutter_test.dart';
import 'package:aio_image_view/src/caching/circuit_breaker.dart';

void main() {
  group('HostCircuitBreaker', () {
    late HostCircuitBreaker breaker;

    setUp(() {
      breaker = HostCircuitBreaker(
        failureThreshold: 3,
        resetDuration: const Duration(milliseconds: 100),
      );
    });

    test('allowRequest returns true for closed circuit', () {
      expect(breaker.allowRequest('good.host'), isTrue);
    });

    test('allowRequest returns false for open circuit', () {
      // Trip the breaker
      for (var i = 0; i < 3; i++) {
        breaker.recordFailure('bad.host');
      }
      expect(breaker.allowRequest('bad.host'), isFalse);
    });

    test(
      'isOpen is side-effect free (does not transition to half-open)',
      () async {
        // 1. Trip the breaker
        for (var i = 0; i < 3; i++) {
          breaker.recordFailure('flaky.host');
        }

        // 2. Wait for reset duration
        await Future<void>.delayed(const Duration(milliseconds: 150));

        // 3. calling isOpen should NOT trigger transition or steal probe
        expect(
          breaker.isOpen('flaky.host'),
          isTrue,
          reason: 'Still reports open before probe',
        );

        // 4. allowRequest should still return true (be the probe)
        expect(
          breaker.allowRequest('flaky.host'),
          isTrue,
          reason: 'Probe allowed after isOpen check',
        );
      },
    );

    test('allowRequest gates probes in half-open state', () async {
      // 1. Trip the breaker
      for (var i = 0; i < 3; i++) {
        breaker.recordFailure('flaky.host');
      }
      expect(breaker.allowRequest('flaky.host'), isFalse);

      // 2. Wait for reset duration
      await Future<void>.delayed(const Duration(milliseconds: 150));

      // 3. First request should be allowed (Probe)
      expect(breaker.allowRequest('flaky.host'), isTrue, reason: 'First probe');

      // 4. Second request (concurrent) should be blocked while probe is in flight
      expect(
        breaker.allowRequest('flaky.host'),
        isFalse,
        reason: 'Concurrent request blocked',
      );

      // 5. If probe succeeds, circuit closes
      breaker.recordSuccess('flaky.host');
      expect(
        breaker.allowRequest('flaky.host'),
        isTrue,
        reason: 'Circuit closed',
      );
    });

    test('failed probe re-opens circuit immediately', () async {
      // 1. Trip breaker
      for (var i = 0; i < 3; i++) {
        breaker.recordFailure('flaky.host');
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));

      // 2. Send probe
      expect(breaker.allowRequest('flaky.host'), isTrue);

      // 3. Fail probe
      breaker.recordFailure('flaky.host');

      // 4. Circuit should be open again
      expect(breaker.allowRequest('flaky.host'), isFalse);
    });
  });
}
