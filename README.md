# AIO Image View

A battle-hardened image rendering and caching library for Flutter, designed for high-scale applications (10M+ users) and optimized for hostile network environments (2G/3G, high latency, packet loss).

`aio_image_view` provides a unified, resilient, and feature-rich interface for displaying images from the network, assets, files, and SVGs.

## Features

*   **🛡️ Network Resilience**:
    *   **Circuit Breakers**: Prevents retry storms when a host is down.
    *   **Exponential Backoff**: Smart retry logic with jitter to prevent thundering herds.
    *   **Captive Portal Detection**: Detects and rejects HTML/JSON masquerading as images (common in public WiFi).
    *   **Stale-if-Error**: Serves cached content if the network fails, ensuring an offline-first experience.
    *   **DNS Probing**: Fails fast during retries if the device has no connectivity.

*   **⚡ Smart Caching**:
    *   **Multi-Bucket Architecture**: Separate storage policies for Avatars, Thumbnails, Content, and Icons.
    *   **Memory Optimization**: Automatically calculates optimal cache size based on widget dimensions to save RAM.
    *   **Disk Bloat Prevention**: Auto-prunes old cache versions and strictly enforces capacity limits.

*   **🔒 Secure & Private**:
    *   **User-Scoped Caching**: Securely associates private images with the current user ID.
    *   **Session Management**: Easily wipe user-specific data on logout to prevent cross-user data leaks.

*   **🎨 Unified Interface**:
    *   **One Widget**: `ImageView` handles Network URLs, Assets, Local Files, and SVGs transparently.
    *   **Built-in Effects**: Shimmer loading, circular clipping, grey-scale, and color filtering.
    *   **Zoom & Hero**: Native support for pinch-to-zoom and Hero animations.

## Installation

Add the dependency to your `pubspec.yaml`:

```yaml
dependencies:
  aio_image_view:
    path: ./ # Or git/pub dependency
```

## Setup

Initialize the cache registry once at the start of your application (e.g., in `main.dart`).

```dart
import 'package:flutter/material.dart';
import 'package:aio_image_view/aio_image_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize the global image cache registry
  imageCaches.initialize(
    // Optional: Log cache events (hits, misses, retries) to console
    metricsCallback: kDebugMode ? debugMetricsCallback : null,
  );

  runApp(const MyApp());
}
```

## Usage

### Basic Usage

The `ImageView` widget is the main entry point. It automatically determines the image source.

```dart
// Network Image
ImageView(
  url: 'https://example.com/photo.jpg',
  height: 200,
  width: double.infinity,
  fit: BoxFit.cover,
  radius: 8, // Rounded corners
)

// Asset Image
ImageView(
  asset: 'assets/images/logo.png',
  width: 100,
  height: 100,
)

// Local File
ImageView(
  path: '/storage/emulated/0/Download/image.jpg',
)

// SVG (Auto-detected from extension or flag)
ImageView(
  asset: 'assets/icons/home.svg',
  svgColor: Colors.blue, 
)
```

### Caching Strategies (Buckets)

Use `cacheBucket` to define how the image should be cached. Different buckets have different retention policies optimized for their use case.

```dart
// Avatars: Long retention (180 days), high priority
ImageView(
  url: 'https://api.app.com/users/123/avatar.jpg',
  cacheBucket: ImageCacheBucket.avatar,
  circular: true,
)

// Thumbnails: High volume, shorter retention (60 days), more concurrent fetches
ImageView(
  url: 'https://cdn.app.com/products/thumb_1.jpg',
  cacheBucket: ImageCacheBucket.thumbnail,
)

// Content/Feed: Moderate retention (30 days)
ImageView(
  url: 'https://cdn.app.com/posts/post_55.jpg',
  cacheBucket: ImageCacheBucket.content,
)
```

| Bucket | Retention | Max Objects | Use Case |
| :--- | :--- | :--- | :--- |
| `avatar` | 180 Days | 2000 | User profile pictures |
| `icon` | 365 Days | 500 | App icons, badges, logos |
| `thumbnail` | 60 Days | 3000 | List/Grid item previews |
| `content` | 30 Days | 1000 | Main feed images |
| `banner` | 90 Days | 200 | Large hero images |

### Private & User-Scoped Images

To prevent privacy leaks (e.g., User B seeing User A's cached profile picture on a shared device), use user-scoped caching.

1.  **Set User ID on Login:**

```dart
// When user logs in
imageCaches.setUserId('user_id_12345');
```

2.  **Mark Image as Private:**

```dart
ImageView(
  url: 'https://api.app.com/private/doc.jpg',
  isPrivateImage: true, // Cache key becomes "u:user_id_12345|https://..."
)
```
*Note: Images in the `avatar` bucket are marked private by default if `isPrivateImage` is not explicitly set.*

3.  **Clear on Logout (Critical):**

```dart
// When user logs out
await imageCaches.clearUserCaches(); // Clears 'avatar' and 'content' buckets
imageCaches.setUserId(null);
```

### Loading & Error States

Customize the user experience during loading or errors.

```dart
ImageView(
  url: imageUrl,
  
  // Shimmer Effect
  useShimmerEffect: true,
  shimmerConfig: ShimmerConfig(
    baseColor: Colors.grey[300]!,
    highlightColor: Colors.grey[100]!,
  ),

  // Custom Placeholders
  placeholderWidget: MyLoadingSpinner(),
  errorWidget: Column(
    children: [
      Icon(Icons.error),
      Text('Failed to load'),
    ],
  ),
)
```

### Advanced Features

#### Zooming
Enable pinch-to-zoom capability natively.

```dart
ImageView(
  url: imageUrl,
  enableZoom: true,
  minScale: 1.0,
  maxScale: 3.0,
)
```

#### Hero Animations
Seamlessly animate images between screens.

```dart
ImageView(
  url: imageUrl,
  heroTag: 'unique_tag_for_this_image',
)
```

#### Pre-caching / Prefetching
You can manually interact with the cache managers if needed.

```dart
// Manually download a file to the thumbnail cache
final file = await imageCaches.thumbnail.getSingleFile(url);
```

## Architecture Details

*   **ResilientFileService**: A custom implementation of `FileService` that wraps `http.Client`. It manages a shared connection pool, handles retries with backoff, and strictly limits global concurrency (default: 6) to protect bandwidth on poor networks.
*   **CacheKeyBuilder**: Automatically strips volatile query parameters (like tokens, timestamps, signatures) from URLs to ensure stable cache keys and avoid duplicate caching.
*   **HostCircuitBreaker**: Monitors failure rates per host. If a host fails consistently (e.g., 5 times), it "trips" and fast-fails subsequent requests for a duration (30s), sparing the network and battery.
