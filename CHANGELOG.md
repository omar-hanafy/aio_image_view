# Changelog

## [1.0.0] - 2026-01-16

### Initial Release

**Core Features:**
- **Battle-Hardened Networking:** Built for hostile network environments (2G/3G) with exponential backoff, circuit breakers, and captive portal detection.
- **Multi-Bucket Caching:** Specialized cache strategies for Avatars, Content, Icons, Thumbnails, and Banners to prevent cache thrashing.
- **Unified ImageView:** A single widget handling Network, Asset, File, and SVG sources with automatic type detection.
- **Smart Memory Management:** Automatic memory cache sizing based on widget render dimensions to prevent OOM errors.
- **Security & Privacy:** Built-in support for private, user-scoped cached images (preventing cross-user data leaks).

**UX & Performance:**
- **Shimmer Effects:** Integrated highly configurable shimmer placeholders.
- **SVG Support:** First-class support for SVG rendering from all sources.
- **Auto-Retry:** Intelligent retry logic with jitter and connectivity probing.
