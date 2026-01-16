import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_shimmer_effects/flutter_shimmer_effects.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:aio_image_view/src/caching/cache_config.dart';
import 'package:aio_image_view/src/caching/image_cache_registry.dart';

export 'package:cached_network_image/cached_network_image.dart'
    show ProgressIndicatorBuilder;
export 'package:flutter_cache_manager/flutter_cache_manager.dart'
    show CacheManager;
export 'package:flutter_shimmer_effects/flutter_shimmer_effects.dart'
    show ShimmerDirection;
export 'package:flutter_svg/flutter_svg.dart' show SvgTheme;

/// Configuration for the loading shimmer effect.
///
/// Defines the visual properties of the animated skeleton loader that appears
/// while an image is being fetched.
///
/// Use this to match the shimmer style with the rest of your application's design system.
class ShimmerConfig {
  /// Creates a configuration for the shimmer effect.
  const ShimmerConfig({
    this.baseColor = const Color(0xFFEBEBF4),
    this.highlightColor = const Color(0xFFF4F4F4),
    this.period = const Duration(milliseconds: 1500),
    this.direction = ShimmerDirection.ltr,
    this.loop = 0,
  });

  /// The background color of the shimmer container.
  ///
  /// This is the "darker" color in the animation.
  /// Defaults to a light grey `Color(0xFFEBEBF4)`.
  final Color baseColor;

  /// The highlight color that moves across the component.
  ///
  /// This is the "lighter" color in the animation.
  /// Defaults to a very light grey `Color(0xFFF4F4F4)`.
  final Color highlightColor;

  /// The duration of one complete shimmer cycle.
  ///
  /// Controls the speed of the animation.
  /// Defaults to `1500ms`.
  final Duration period;

  /// The direction the shimmer highlight moves.
  ///
  /// Defaults to [ShimmerDirection.ltr] (Left to Right).
  final ShimmerDirection direction;

  /// The number of times the animation should loop.
  ///
  /// Set to `0` for infinite looping (default).
  final int loop;
}

/// Factory for creating standard placeholder and error widgets.
///
/// Provides a consistent set of UI states (loading, error, empty)
/// used by [ImageView] when the target image is unavailable.
class ImagePlaceholders {
  /// Creates an asset-based placeholder.
  ///
  /// Renders a local asset image, typically used for static placeholders like
  /// a user silhouette or a generic product icon.
  static Widget assetPlaceholder(
    String asset, {
    double? height,
    double? width,
    double? dimension,
    double opacity = 0,
    BoxFit? fit,
    String? package,
  }) =>
      Image.asset(
        asset,
        fit: fit,
        width: width ?? dimension,
        height: height ?? dimension,
        colorBlendMode: opacity > 0 ? BlendMode.modulate : null,
        color: opacity > 0 ? Colors.white.withValues(alpha: opacity) : null,
        package: package,
      );

  /// Creates a shimmer loading placeholder.
  ///
  /// Renders an animated gradient that indicates active loading state.
  /// Uses [ShimmerConfig] to determine colors and animation speed.
  static Widget shimmerPlaceholder({
    double? height,
    double? width,
    double? dimension,
    ShimmerConfig? shimmerConfig,
  }) {
    final config = shimmerConfig ??
        ShimmerConfig(
          baseColor: Colors.grey[300]!,
          highlightColor: Colors.grey[100]!,
        );

    return Shimmer.fromColors(
      baseColor: config.baseColor,
      highlightColor: config.highlightColor,
      period: config.period,
      direction: config.direction,
      loop: config.loop,
      child: Container(
        width: width ?? dimension,
        height: height ?? dimension,
        color: Colors.white,
      ),
    );
  }

  /// Creates a default circular loading indicator.
  ///
  /// Renders a [CircularProgressIndicator] centered in the container.
  /// Used when [useShimmerEffect] is false.
  static Widget loadingIndicator({
    double? height,
    double? width,
    double? dimension,
    Color? color,
    double size = 24,
    double strokeWidth = 2,
  }) {
    return Container(
      width: width ?? dimension,
      height: height ?? dimension,
      alignment: Alignment.center,
      child: SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(
          strokeWidth: strokeWidth,
          color: color,
        ),
      ),
    );
  }

  /// Creates an error placeholder with an icon and optional message.
  ///
  /// Displayed when image fetching fails and no [errorAsset] or [errorWidget]
  /// is provided.
  static Widget errorPlaceholder({
    double? height,
    double? width,
    double? dimension,
    Color? iconColor,
    String? message,
    IconData icon = Icons.image_not_supported,
    double iconSize = 32,
  }) {
    return Container(
      height: height ?? dimension,
      width: width ?? dimension,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: iconSize,
            color: iconColor ?? Colors.red.withValues(alpha: 0.8),
          ),
          if (message != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 8),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  /// Creates an empty/no content placeholder.
  ///
  /// Useful for states where no image is expected or assigned.
  static Widget emptyPlaceholder({
    double? height,
    double? width,
    double? dimension,
    IconData icon = Icons.image_not_supported_outlined,
    String? message,
    Color? backgroundColor,
    Color? borderColor,
    Color? iconColor,
    Color? textColor,
    BorderRadiusGeometry? borderRadius,
  }) {
    return Container(
      height: height ?? dimension,
      width: width ?? dimension,
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.grey.shade50,
        borderRadius: borderRadius ?? BorderRadiusDirectional.circular(8),
        border: borderColor != null
            ? Border.all(color: borderColor)
            : Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: iconColor ?? Colors.grey,
            size: (height ?? dimension ?? 60) * 0.3,
          ),
          if (message != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 8),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: textColor ?? Colors.grey.shade600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A versatile image widget that handles network, asset, and file images with various customization options.
///
/// [ImageView] is the primary entry point for displaying images in the application.
/// It abstracts away the complexity of:
/// *   **Source resolution:** Automatically handles Network (URL), File (Path), and Asset sources.
/// *   **Caching:** Intelligent multi-bucket caching via [ImageCacheRegistry].
/// *   **Resilience:** Built-in retries, circuit breakers, and offline support.
/// *   **Performance:** Automatic memory cache sizing and thumbnail generation.
/// *   **UX:** Unified placeholder, error, and shimmer states.
///
/// ## Usage
///
/// ### 1. Network Image (Most Common)
/// ```dart
/// ImageView(
///   url: 'https://example.com/photo.jpg',
///   height: 200,
///   width: 200,
///   radius: 12,
///   // Uses 'content' bucket by default
/// )
/// ```
///
/// ### 2. User Profile (Private & Cached)
/// ```dart
/// ImageView(
///   url: user.avatarUrl,
///   cacheBucket: ImageCacheBucket.avatar,
///   circular: true,
///   // Automatically scopes cache key to current userId
/// )
/// ```
///
/// ### 3. Local Asset with Shimmer
/// ```dart
/// ImageView(
///   asset: 'assets/logo.png',
///   width: 64,
///   useShimmerEffect: true,
/// )
/// ```
class ImageView extends StatelessWidget {
  /// Creates an [ImageView].
  ///
  /// Exactly one of [url], [path], or [asset] must be provided.
  const ImageView({
    super.key,
    this.url,
    this.path,
    this.asset,
    this.placeholderAsset,
    this.errorAsset,
    this.placeholderWidget,
    this.errorWidget,
    this.package,
    this.radius,
    this.borderRadius,
    this.fit,
    double? height,
    double? width = double.infinity,
    double? dimension,
    this.circular = false,
    this.isThumbnail = false,
    this.isSVG = false,
    this.isGreyedOut = false,
    this.placeHolderEnabled = true,
    this.errorEnabled = true,
    this.useShimmerEffect = false,
    this.opacity = 0,
    this.alignment = Alignment.center,
    this.semanticLabel,
    this.svgTheme,
    this.svgColor,
    this.fadeInDuration = const Duration(milliseconds: 300),
    this.cacheKey,
    this.cacheManager,
    this.memCacheWidth,
    this.memCacheHeight,
    this.onTap,
    this.enableZoom = false,
    this.maxScale = 3.0,
    this.heroTag,
    this.errorText,
    this.backgroundColor,
    this.boxFit,
    this.progressIndicatorBuilder,
    this.fadeOutDuration = const Duration(milliseconds: 300),
    this.fadeInCurve = Curves.easeIn,
    this.fadeOutCurve = Curves.easeOut,
    this.maxWidthDiskCache,
    this.maxHeightDiskCache,
    this.onError,
    this.minScale = 1.0,
    this.headers,
    this.gaplessPlayback = false,
    this.centerSlice,
    this.repeat = ImageRepeat.noRepeat,
    this.matchTextDirection = false,
    this.invertColors = false,
    this.isAntiAlias = false,
    this.useOldImageOnUrlChange = false,
    this.frameBuilder,
    this.scale = 1.0,
    this.blendMode,
    this.shimmerConfig,
    this.filterQuality = FilterQuality.low,
    this.cacheBucket = ImageCacheBucket.content,
    bool? isPrivateImage,
  })  : height = dimension ?? height,
        width = dimension ?? width,
        isPrivateImage =
            isPrivateImage ?? (cacheBucket == ImageCacheBucket.avatar),
        assert(
          url != null || path != null || asset != null,
          'At least one of url, path, or asset must be provided',
        );

  /// The remote URL of the image to display.
  ///
  /// If provided, [ImageView] will attempt to fetch, cache, and display the image.
  ///
  /// **Priority:** [path] > [asset] > [url].
  final String? url;

  /// The local file system path of the image.
  ///
  /// Takes precedence over [url] and [asset] if provided.
  /// Used for images picked from gallery or saved locally.
  final String? path;

  /// The application asset path (e.g., 'assets/images/logo.png').
  ///
  /// Takes precedence over [url] but is secondary to [path].
  final String? asset;

  /// An asset to display while the main image is loading.
  ///
  /// Used when [placeholderWidget] is null.
  final String? placeholderAsset;

  /// An asset to display if the main image fails to load.
  ///
  /// Used when [errorWidget] is null.
  final String? errorAsset;

  /// A custom widget to display while the main image is loading.
  ///
  /// Takes precedence over [placeholderAsset] and default shimmer/loaders.
  final Widget? placeholderWidget;

  /// A custom widget to display if the main image fails to load.
  ///
  /// Takes precedence over [errorAsset].
  final Widget? errorWidget;

  /// The uniform corner radius to apply to the image.
  ///
  /// If [borderRadius] is also provided, it takes precedence.
  final double? radius;

  /// How the image should be inscribed into the space allocated during layout.
  ///
  /// Defaults to `null` (depends on source, usually defaults to [BoxFit.contain] or similar).
  /// Alias: [boxFit].
  final BoxFit? fit;

  /// The height of the image widget.
  ///
  /// If null, the widget will size itself to the image's intrinsic height
  /// (subject to constraints).
  final double? height;

  /// The width of the image widget.
  ///
  /// Defaults to [double.infinity] if not specified, which tries to fill width.
  final double? width;

  /// Whether to clip the image to a perfect circle.
  ///
  /// If true, overrides [radius] and [borderRadius].
  /// Useful for avatars.
  final bool circular;

  /// Whether the [path] points to a video file that needs a thumbnail generated.
  ///
  /// If true, attempts to generate a thumbnail from the video file at [path].
  final bool isThumbnail;

  /// Whether the image source is an SVG.
  ///
  /// If true, forces the use of [SvgPicture] instead of standard [Image] widgets.
  /// Auto-detection is also performed based on file extension.
  final bool isSVG;

  /// Whether to apply a semi-transparent grey overlay on top of the image.
  ///
  /// Useful for indicating disabled states or selection.
  final bool isGreyedOut;

  /// Whether to show a placeholder widget while loading.
  ///
  /// Defaults to `true`. If `false`, shows nothing until the image is ready.
  final bool placeHolderEnabled;

  /// Whether to show an error widget if loading fails.
  ///
  /// Defaults to `true`. If `false`, shows nothing on error.
  final bool errorEnabled;

  /// Whether to use the shimmer effect as the default placeholder.
  ///
  /// If true, shows a [Shimmer] effect instead of a static loader.
  /// Configurable via [shimmerConfig].
  final bool useShimmerEffect;

  /// The opacity of the image.
  ///
  /// Value between 0.0 and 1.0.
  /// *   `0.0`: Fully transparent (invisible).
  /// *   `1.0`: Fully opaque (default, technically 0 passed to code but handled as no-op).
  /// *   `> 0`: Applies `Color.white.withValues(alpha: opacity)` with [BlendMode.modulate].
  final double opacity;

  /// How to align the image within its bounds.
  ///
  /// Defaults to [Alignment.center].
  final AlignmentGeometry alignment;

  /// Theme configuration for SVG images.
  final SvgTheme? svgTheme;

  /// Color filter to apply to SVG images.
  ///
  /// Overrides the SVG's internal colors.
  final Color? svgColor;

  /// Custom border radius.
  ///
  /// Takes precedence over [radius].
  final BorderRadiusGeometry? borderRadius;

  /// A semantic description of the image for accessibility.
  final String? semanticLabel;

  /// The package argument for [Image.asset] or [SvgPicture.asset].
  ///
  /// Used when the asset is included in a package dependency.
  final String? package;

  /// The duration of the fade-in animation when the image loads.
  ///
  /// Defaults to `300ms`.
  final Duration fadeInDuration;

  /// The duration of the fade-out animation for placeholders.
  ///
  /// Defaults to `300ms`.
  final Duration fadeOutDuration;

  /// The curve of the fade-in animation.
  ///
  /// Defaults to [Curves.easeIn].
  final Curve fadeInCurve;

  /// The curve of the fade-out animation.
  ///
  /// Defaults to [Curves.easeOut].
  final Curve fadeOutCurve;

  /// A custom cache key for network images.
  ///
  /// By default, [ImageView] generates a stable key using [ImageCacheRegistry.buildCacheKey],
  /// which strips volatile query parameters. Use this to override that behavior.
  final String? cacheKey;

  /// A custom [CacheManager] to use for network images.
  ///
  /// If null, the appropriate manager is selected from [imageCaches] based on [cacheBucket].
  final CacheManager? cacheManager;

  /// The width to decode the image to in memory.
  ///
  /// **Optimization:** If null, [ImageView] automatically calculates this based on
  /// the widget's [width] to save RAM.
  final int? memCacheWidth;

  /// The height to decode the image to in memory.
  final int? memCacheHeight;

  /// The maximum width to store the image on disk.
  ///
  /// Resizes the image before saving to disk to save storage space.
  final int? maxWidthDiskCache;

  /// The maximum height to store the image on disk.
  final int? maxHeightDiskCache;

  /// Callback fired when the user taps the image.
  final VoidCallback? onTap;

  /// Callback fired when an error occurs during image loading.
  final ValueChanged<Object>? onError;

  /// Whether to allow the user to pinch-to-zoom the image.
  ///
  /// Wraps the image in an [InteractiveViewer].
  /// Defaults to `false`.
  final bool enableZoom;

  /// The maximum scale factor for zooming.
  ///
  /// Only used if [enableZoom] is true.
  /// Defaults to `3.0`.
  final double maxScale;

  /// The minimum scale factor for zooming.
  ///
  /// Only used if [enableZoom] is true.
  /// Defaults to `1.0`.
  final double minScale;

  /// The tag for Hero animations.
  ///
  /// If provided, the image will be wrapped in a [Hero] widget.
  final String? heroTag;

  /// The text to display in the default error widget.
  ///
  /// Used when no [errorWidget] or [errorAsset] is provided.
  final String? errorText;

  /// The background color to fill the container with behind the image.
  final Color? backgroundColor;

  /// Alias for [fit].
  final BoxFit? boxFit;

  /// A builder for a custom progress indicator.
  ///
  /// Used by [CachedNetworkImage].
  final ProgressIndicatorBuilder? progressIndicatorBuilder;

  /// Custom HTTP headers to send with network image requests.
  final Map<String, String>? headers;

  /// Whether to continue showing the old image while a new one loads.
  ///
  /// Useful when updating the [url] of an existing [ImageView] to prevent flickering.
  final bool gaplessPlayback;

  /// The center slice for a nine-patch image.
  final Rect? centerSlice;

  /// How to repeat the image if it doesn't fill the layout bounds.
  ///
  /// Defaults to [ImageRepeat.noRepeat].
  final ImageRepeat repeat;

  /// Whether to paint the image in the direction of the [TextDirection].
  final bool matchTextDirection;

  /// Whether to invert the colors of the image.
  ///
  /// Useful for dark mode adaptations of simple icons.
  final bool invertColors;

  /// Whether to paint the image with anti-aliasing.
  final bool isAntiAlias;

  /// Whether to use the old image when the URL changes.
  final bool useOldImageOnUrlChange;

  /// A builder function responsible for creating the widget that represents this image frame.
  final ImageFrameBuilder? frameBuilder;

  /// The scale factor to apply to the image.
  ///
  /// Defaults to `1.0`.
  final double scale;

  /// The blend mode to apply to the image color.
  final BlendMode? blendMode;

  /// Configuration for the shimmer effect.
  ///
  /// Only used if [useShimmerEffect] is true.
  final ShimmerConfig? shimmerConfig;

  /// The rendering quality of the image.
  ///
  /// Defaults to [FilterQuality.low] for performance.
  final FilterQuality filterQuality;

  /// The cache bucket to use for network images.
  ///
  /// Controls retention policy, eviction, and network resilience settings.
  /// Defaults to [ImageCacheBucket.content].
  final ImageCacheBucket cacheBucket;

  /// Whether this is a private/user-scoped image.
  ///
  /// *   `true`: The cache key is prefixed with the current User ID (if logged in).
  /// *   `false`: The cache key is global (shared across users).
  ///
  /// Defaults to `true` if [cacheBucket] is [ImageCacheBucket.avatar], otherwise `false`.
  final bool isPrivateImage;

  /// Generate video thumbnail from local path
  Future<String> _getLocalVideoThumbnail(String videoPath) async {
    // we do not need that now.
    return '';
  }

  /// Validate and generate URL for network images
  String generateUrl() {
    if (url == null || url!.isEmpty) return '';

    try {
      final uri = Uri.parse(url!);
      if (uri.host.isEmpty) {
        return '';
      }
      return url!;
    } catch (e) {
      debugPrint('Invalid URL: $url, Error: $e');
      return '';
    }
  }

  /// Generate placeholder widget for loading and error states
  Widget generatePlaceholder({
    Object? error,
    StackTrace? stackTrace,
    bool isLoading = true,
  }) {
    if (!errorEnabled || error == null) {
      // When no error, show loading indicator if it's in loading state
      if (!isLoading) return const SizedBox.shrink();

      // Use custom placeholder widget if provided
      if (placeholderWidget != null) return placeholderWidget!;

      // Use placeholder asset if provided
      if (placeholderAsset != null) {
        return ImagePlaceholders.assetPlaceholder(
          placeholderAsset!,
          width: width,
          height: height,
          fit: fit ?? BoxFit.contain,
          package: package,
        );
      }

      // Use shimmer effect if enabled
      if (useShimmerEffect) {
        return ImagePlaceholders.shimmerPlaceholder(
          width: width,
          height: height,
          shimmerConfig: shimmerConfig,
        );
      }

      // Default loading indicator
      return ImagePlaceholders.loadingIndicator(width: width, height: height);
    }

    // When there's an error, show error widget
    if (errorWidget != null) return errorWidget!;

    // Use error asset if provided
    if (errorAsset != null) {
      return ImagePlaceholders.assetPlaceholder(
        errorAsset!,
        width: width,
        height: height,
        fit: fit ?? BoxFit.contain,
        package: package,
      );
    }

    // Default error widget
    return ImagePlaceholders.errorPlaceholder(
      width: width,
      height: height,
      message: errorText,
    );
  }

  /// Generate widget for asset image
  Widget _generateAssetImage(BuildContext context) {
    if (isSVG || (asset != null && asset!.endsWith('.svg'))) {
      return SvgPicture.asset(
        asset!,
        theme: svgTheme,
        fit: fit ?? boxFit ?? BoxFit.contain,
        width: width,
        height: height,
        colorFilter: opacity > 0
            ? ColorFilter.mode(
                Colors.white.withValues(alpha: opacity),
                BlendMode.modulate,
              )
            : svgColor != null
                ? ColorFilter.mode(svgColor!, BlendMode.srcIn)
                : null,
        package: package,
        alignment: alignment,
        placeholderBuilder:
            placeHolderEnabled ? (_) => generatePlaceholder() : null,
        semanticsLabel: semanticLabel,
      );
    } else {
      return Image.asset(
        asset!,
        fit: fit ?? boxFit,
        width: width,
        height: height,
        colorBlendMode: opacity > 0 ? BlendMode.modulate : null,
        color: opacity > 0 ? Colors.white.withValues(alpha: opacity) : null,
        package: package,
        alignment: alignment,
        errorBuilder: (_, e, st) => generatePlaceholder(error: e),
        semanticLabel: semanticLabel,
        cacheWidth: memCacheWidth,
        cacheHeight: memCacheHeight,
      );
    }
  }

  /// Generate widget for file path image
  Widget _generatePathImage(BuildContext context) {
    if (isThumbnail) {
      return FutureBuilder(
        future: _getLocalVideoThumbnail(path!),
        builder: (_, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return generatePlaceholder();
          } else if (snapshot.hasError) {
            return generatePlaceholder(error: snapshot.error);
          } else if (!snapshot.hasData || (snapshot.data ?? '').isEmpty) {
            return generatePlaceholder(error: 'Failed to generate thumbnail');
          } else {
            return Image.file(
              File(snapshot.data!),
              fit: fit ?? boxFit,
              colorBlendMode: opacity > 0 ? BlendMode.modulate : null,
              color:
                  opacity > 0 ? Colors.white.withValues(alpha: opacity) : null,
              width: width,
              height: height,
              alignment: alignment,
              errorBuilder: (_, e, st) =>
                  generatePlaceholder(error: e, stackTrace: st),
              semanticLabel: semanticLabel,
              cacheWidth: memCacheWidth,
              cacheHeight: memCacheHeight,
            );
          }
        },
      );
    } else {
      // Check if file exists first
      final file = File(path!);
      if (!file.existsSync()) {
        return generatePlaceholder(error: 'File not found');
      }

      return Image.file(
        file,
        colorBlendMode: opacity > 0 ? BlendMode.modulate : null,
        color: opacity > 0 ? Colors.white.withValues(alpha: opacity) : null,
        fit: fit ?? boxFit,
        width: width,
        height: height,
        alignment: alignment,
        errorBuilder: (context, e, s) =>
            generatePlaceholder(error: e, stackTrace: s),
        semanticLabel: semanticLabel,
        cacheWidth: memCacheWidth,
        cacheHeight: memCacheHeight,
      );
    }
  }

  /// Generate widget for network image
  Widget _generateNetworkImage(BuildContext context) {
    final imageUrl = generateUrl();
    if (imageUrl.isEmpty) {
      return generatePlaceholder(error: 'Invalid URL', isLoading: false);
    }

    if (isSVG || imageUrl.endsWith('.svg')) {
      return SvgPicture.network(
        imageUrl,
        fit: fit ?? boxFit ?? BoxFit.contain,
        theme: svgTheme,
        width: width,
        height: height,
        alignment: alignment,
        headers: headers,
        colorFilter: opacity > 0
            ? ColorFilter.mode(
                Colors.white.withValues(alpha: opacity),
                BlendMode.modulate,
              )
            : svgColor != null
                ? ColorFilter.mode(svgColor!, BlendMode.srcIn)
                : null,
        placeholderBuilder:
            placeHolderEnabled ? (_) => generatePlaceholder() : null,
        semanticsLabel: semanticLabel,
      );
    } else {
      return CachedNetworkImage(
        fit: fit ?? boxFit,
        cacheManager: cacheManager ?? imageCaches.getManager(cacheBucket),
        width: width,
        height: height,
        imageUrl: imageUrl,
        colorBlendMode: opacity > 0 ? BlendMode.modulate : blendMode,
        color: opacity > 0 ? Colors.white.withValues(alpha: opacity) : null,
        alignment: alignment.resolve(Directionality.of(context)),
        errorWidget: (context, url, e) => generatePlaceholder(error: e),
        placeholder:
            placeHolderEnabled ? (context, url) => generatePlaceholder() : null,
        placeholderFadeInDuration:
            placeHolderEnabled ? fadeInDuration : Duration.zero,
        fadeInDuration: fadeInDuration,
        fadeOutDuration: fadeOutDuration,
        fadeInCurve: fadeInCurve,
        fadeOutCurve: fadeOutCurve,
        cacheKey: cacheKey ??
            imageCaches.buildCacheKey(imageUrl, isPrivate: isPrivateImage),
        memCacheWidth: memCacheWidth ?? _calculateMemCacheWidth(),
        memCacheHeight: memCacheHeight,
        maxWidthDiskCache: maxWidthDiskCache,
        maxHeightDiskCache: maxHeightDiskCache,
        progressIndicatorBuilder: progressIndicatorBuilder,
        httpHeaders: headers,
        errorListener: onError,
        useOldImageOnUrlChange: useOldImageOnUrlChange,
        filterQuality: filterQuality,
        repeat: repeat,
        matchTextDirection: matchTextDirection,
      );
    }
  }

  /// Calculate optimal memory cache width based on widget width.
  ///
  /// This prevents loading a 1080p image into RAM when displaying
  /// a 50x50 thumbnail, which would waste memory.
  int? _calculateMemCacheWidth() {
    if (width != null && width!.isFinite) {
      // 2x for retina/high-DPI displays, clamped to reasonable bounds
      return (width! * 2).toInt().clamp(50, 2000);
    }

    // SAFETY NET: If width is infinite, default to 1080px.
    // Returning null here loads full-res images, crashing low-end Androids.
    return 1080;
  }

  @override
  Widget build(BuildContext context) {
    Widget image;

    // Determine image source
    if (path != null) {
      image = _generatePathImage(context);
    } else if (asset != null) {
      image = _generateAssetImage(context);
    } else {
      image = _generateNetworkImage(context);
    }

    // Apply frame builder if provided
    if (frameBuilder != null) {
      image = Builder(
        builder: (context) => frameBuilder!(context, image, 0, true),
      );
    }

    // Apply background color if specified
    if (backgroundColor != null) {
      image = ColoredBox(color: backgroundColor!, child: image);
    }

    // Apply clipping if needed
    if (circular) {
      image = ClipOval(child: image);
    } else if (radius != null || borderRadius != null) {
      image = ClipRRect(
        borderRadius: borderRadius ?? BorderRadius.circular(radius!),
        child: image,
      );
    }

    // Apply color inversion if needed
    if (invertColors) {
      image = ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          -1,
          0,
          0,
          0,
          255,
          0,
          -1,
          0,
          0,
          255,
          0,
          0,
          -1,
          0,
          255,
          0,
          0,
          0,
          1,
          0,
        ]),
        child: image,
      );
    }

    // Apply grey overlay if needed
    if (isGreyedOut) {
      image = Stack(
        children: [
          image,
          Positioned.fill(
            child: ColoredBox(color: Colors.grey.withValues(alpha: 0.7)),
          ),
        ],
      );
    }

    // Apply hero animation if tag provided
    if (heroTag != null) {
      image = Hero(tag: heroTag!, child: image);
    }

    // Apply zoom functionality if enabled
    if (enableZoom) {
      image = InteractiveViewer(
        maxScale: maxScale,
        minScale: minScale,
        child: image,
      );
    }

    // Apply tap handler if provided
    if (onTap != null) {
      image = GestureDetector(onTap: onTap, child: image);
    }

    return image;
  }
}
