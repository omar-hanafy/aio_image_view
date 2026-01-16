/// Cache key normalization and user scoping for secure, efficient caching.
///
/// Handles:
/// - Signed/tokenized URLs (Firebase, AWS S3, CloudFront)
/// - User-scoped keys for private images (security)
/// - Deterministic key generation (stable cache hits)
library;

/// A utility class for generating stable, secure cache keys.
///
/// Handles two critical problems in image caching:
/// 1.  **Cache Busting:** Removing volatile query parameters (like tokens or timestamps) so that
///     the same image doesn't get cached multiple times.
/// 2.  **Security:** Scoping sensitive images (like user profiles) to the current user ID,
///     preventing cross-user data leaks on shared devices.
abstract final class CacheKeyBuilder {
  /// Volatile query params to strip from URLs.
  ///
  /// These params change frequently but don't affect the actual image content:
  /// - Firebase Storage: `token`, `alt`
  /// - AWS SigV4: `x-amz-*` params
  /// - CloudFront: `Expires`, `Signature`, `Key-Pair-Id`, `Policy`
  /// - Generic cache busters: `t`, `ts`, `timestamp`, `cache_buster`, `_`
  static const _volatileParams = <String>{
    // Firebase Storage
    'token',
    'alt',
    // AWS SigV4 (handled separately with prefix check)
    'x-amz-signature',
    'x-amz-credential',
    'x-amz-date',
    'x-amz-expires',
    'x-amz-signedheaders',
    'x-amz-security-token',
    // CloudFront / Generic signing
    'expires',
    'signature',
    'key-pair-id',
    'policy',
    // Common cache busters
    't',
    'ts',
    'timestamp',
    'cache_buster',
    '_',
  };

  /// Normalizes a URL by stripping known volatile query parameters.
  ///
  /// **Why:** Many CDNs (Firebase, CloudFront) add short-lived tokens to URLs.
  /// Without normalization, `img.jpg?token=A` and `img.jpg?token=B` are treated as
  /// different files, causing cache misses and wasted storage.
  ///
  /// **Behavior:**
  /// *   Parses the URL.
  /// *   Removes params like `token`, `alt`, `x-amz-*`.
  /// *   Sorts remaining params alphabetically (deterministic key).
  /// *   Returns the cleaned URL string.
  ///
  /// Example:
  /// ```dart
  /// // Firebase Storage URL
  /// final url = 'https://firebasestorage.googleapis.com/image.jpg?alt=media&token=abc123';
  /// final normalized = CacheKeyBuilder.normalizeUrl(url);
  /// // Result: 'https://firebasestorage.googleapis.com/image.jpg'
  /// ```
  static String normalizeUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.queryParameters.isEmpty) return url;

    // Create a mutable copy of the parameters
    final cleanParams = Map<String, String>.from(uri.queryParameters);

    // Explicitly remove volatile keys
    cleanParams.removeWhere((key, value) {
      final lowerKey = key.toLowerCase();
      // Check exact matches
      if (_volatileParams.contains(lowerKey)) return true;
      // Check prefix matches (AWS)
      if (lowerKey.startsWith('x-amz-')) return true;
      return false;
    });

    // NOTE: We REMOVED the early return optimization here to ensure deterministic sorting.
    // Even if no volatile params were removed, we must sort the remaining params.

    // If all params were removed, return URL without query
    if (cleanParams.isEmpty) {
      return Uri(
        scheme: uri.scheme,
        userInfo: uri.userInfo,
        host: uri.host,
        port: uri.port,
        path: uri.path,
        fragment: uri.hasFragment ? uri.fragment : null,
      ).toString();
    }

    // Sort keys for deterministic output
    final sortedKeys = cleanParams.keys.toList()..sort();
    final sorted = <String, String>{
      for (final k in sortedKeys) k: cleanParams[k]!,
    };

    return uri.replace(queryParameters: sorted).toString();
  }

  /// Builds a user-scoped cache key for private images.
  ///
  /// **Format:** `u:{userId}|{normalizedUrl}`
  ///
  /// **Why:** Prevents "User A" from seeing "User B's" cached private images
  /// after a logout/login sequence on the same device.
  static String userScopedKey(String url, {required String userId}) {
    return 'u:$userId|${normalizeUrl(url)}';
  }

  /// Builds the final cache key based on configuration.
  ///
  /// **Logic:**
  /// 1.  If [explicitKey] is provided, it is returned as-is (highest priority).
  /// 2.  The [url] is normalized via [normalizeUrl].
  /// 3.  If [isPrivate] is `true` AND [userId] is present, returns a [userScopedKey].
  /// 4.  Otherwise, returns the normalized URL.
  static String build(
    String url, {
    String? explicitKey,
    String? userId,
    bool isPrivate = false,
  }) {
    // Explicit key takes precedence
    if (explicitKey != null) return explicitKey;

    final normalized = normalizeUrl(url);

    // Private images need user scoping
    if (isPrivate && userId != null && userId.isNotEmpty) {
      return userScopedKey(normalized, userId: userId);
    }

    return normalized;
  }
}
