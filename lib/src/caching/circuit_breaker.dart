/// Per-host circuit breaker for network resilience.
///
/// Prevents retry storms when a CDN POP is down or DNS is flaky.
/// Instead of doing 5 retries × 100 images = 500 failed requests,
/// the circuit breaker opens after a few failures and fast-fails subsequent requests.
library;

/// Per-host circuit breaker to prevent retry storms.
///
/// States:
/// - **Closed**: Normal operation, requests pass through
/// - **Open**: Failures exceeded threshold, requests fail fast
/// - **Half-Open**: After reset duration, allows ONE probe request.
///   - If probe succeeds: Circuit closes (resets)
///   - If probe fails: Circuit re-opens immediately
class HostCircuitBreaker {
  HostCircuitBreaker({
    this.failureThreshold = 5,
    this.resetDuration = const Duration(seconds: 30),
  });

  /// Number of consecutive failures before opening the circuit
  final int failureThreshold;

  /// How long the circuit stays open before allowing a probe
  final Duration resetDuration;

  final Map<String, _HostState> _states = {};

  /// Check if we can proceed with a request to [host].
  ///
  /// Returns `true` if request is allowed (Closed or Half-Open probe).
  /// Returns `false` if circuit is Open (fail fast).
  ///
  /// This method handles the state transition from Open -> Half-Open.
  bool allowRequest(String host) {
    final state = _states[host];
    if (state == null) return true; // No history, allow

    // 1. If Open, check if we can transition to Half-Open
    if (state.isOpen) {
      final openedAt = state.openedAt;
      if (openedAt != null &&
          DateTime.now().difference(openedAt) >= resetDuration) {
        // Transition to Half-Open
        state.isOpen = false;
        state.isHalfOpen = true;
        state.probeInFlight = false; // Ready for a probe
      } else {
        return false; // Still open and waiting
      }
    }

    // 2. If Half-Open, allow exactly ONE probe
    if (state.isHalfOpen) {
      if (state.probeInFlight) {
        return false; // Probe already active, block others
      }
      state.probeInFlight = true;
      return true; // You are the probe
    }

    // 3. Closed (Normal operation)
    return true;
  }

  /// Check if circuit is open for a host (legacy/debug accessor).
  ///
  /// Pure state check - does NOT trigger transitions.
  bool isOpen(String host) {
    return _states[host]?.isOpen ?? false;
  }

  /// Check if circuit is in half-open state.
  bool isHalfOpen(String host) {
    return _states[host]?.isHalfOpen ?? false;
  }

  /// Record a successful request (resets circuit to closed).
  void recordSuccess(String host) {
    _states[host] = _HostState(); // Clear state (reset to closed)
  }

  /// Record a failed request (may open circuit).
  void recordFailure(String host) {
    final state = _states.putIfAbsent(host, _HostState.new);

    // If in half-open and probe failed, re-open immediately
    if (state.isHalfOpen) {
      state.isHalfOpen = false;
      state.probeInFlight = false;
      state.isOpen = true;
      state.openedAt = DateTime.now();
      return;
    }

    state.consecutiveFailures++;

    if (state.consecutiveFailures >= failureThreshold) {
      state.isOpen = true;
      state.openedAt = DateTime.now();
    }
  }

  /// Manually reset circuit for a specific host.
  void reset(String host) {
    _states.remove(host);
  }

  /// Reset all circuits (e.g., on network change).
  void resetAll() {
    _states.clear();
  }

  /// Get current state for debugging.
  Map<String,
          ({int failures, bool isOpen, bool isHalfOpen, bool probeInFlight})>
      get debugState {
    return _states.map(
      (host, state) => MapEntry(
        host,
        (
          failures: state.consecutiveFailures,
          isOpen: state.isOpen,
          isHalfOpen: state.isHalfOpen,
          probeInFlight: state.probeInFlight,
        ),
      ),
    );
  }
}

class _HostState {
  int consecutiveFailures = 0;
  bool isOpen = false;
  bool isHalfOpen = false;
  bool probeInFlight = false;
  DateTime? openedAt;
}
