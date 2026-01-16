import 'package:flutter/material.dart';
import 'package:aio_image_view/aio_image_view.dart';

void main() {
  // Initialize the cache registry at startup
  imageCaches.initialize(metricsCallback: debugMetricsCallback);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AIO Image View Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'AIO Image View Demo'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  // Simulate a user ID for auth-scoped caching
  final String _userId = 'user_123';
  bool _isLoggedIn = true;

  @override
  void initState() {
    super.initState();
    if (_isLoggedIn) {
      imageCaches.setUserId(_userId);
    }
  }

  void _toggleLogin() {
    setState(() {
      _isLoggedIn = !_isLoggedIn;
      if (_isLoggedIn) {
        imageCaches.setUserId(_userId);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Logged In: Cache scoped to user_123')),
        );
      } else {
        imageCaches.clearUserCaches();
        imageCaches.setUserId(null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Logged Out: User caches cleared')),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: Icon(_isLoggedIn ? Icons.logout : Icons.login),
            onPressed: _toggleLogin,
            tooltip: _isLoggedIn ? 'Logout' : 'Login',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader('Standard Network Image'),
            const SizedBox(height: 10),
            const Center(
              child: ImageView(
                url:
                    'https://images.unsplash.com/photo-1682687220742-aba13b6e50ba?w=500&auto=format&fit=crop&q=60',
                height: 200,
                width: double.infinity,
                radius: 12,
                cacheBucket: ImageCacheBucket.content,
                placeholderWidget: Center(child: CircularProgressIndicator()),
                fit: BoxFit.cover,
              ),
            ),

            const SizedBox(height: 24),
            const _SectionHeader('Circular Avatar (User Scoped)'),
            const Text(
              'Try logging out to clear this cache.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 10),
            Center(
              child: ImageView(
                // Using a random user image
                url:
                    'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=200&auto=format&fit=crop&q=60',
                height: 100,
                width: 100,
                circular: true,
                cacheBucket: ImageCacheBucket.avatar,
                isPrivateImage: true, // Keys cache to current userId
                fit: BoxFit.cover,
                errorWidget: const Icon(Icons.person, size: 50),
              ),
            ),

            const SizedBox(height: 24),
            const _SectionHeader('Error Handling & Circuit Breaker'),
            const SizedBox(height: 10),
            const Center(
              child: ImageView(
                url: 'https://invalid-url-example.com/image.jpg',
                height: 150,
                width: 150,
                radius: 8,
                backgroundColor: Colors.grey,
                errorText: 'Failed to load',
                cacheBucket: ImageCacheBucket.thumbnail,
              ),
            ),

            const SizedBox(height: 24),
            const _SectionHeader('Shimmer Effect Placeholder'),
            const SizedBox(height: 10),
            const Center(
              child: ImageView(
                // A large image to ensure loading takes a moment
                url:
                    'https://images.unsplash.com/photo-1472214103451-9374bd1c798e?w=1000&auto=format&fit=crop&q=60',
                height: 200,
                width: double.infinity,
                radius: 12,
                useShimmerEffect: true,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 24),
            const _SectionHeader('SVG Image'),
            const SizedBox(height: 10),
            const Center(
              child: ImageView(
                url:
                    'https://dev.w3.org/SVG/tools/svgweb/samples/svg-files/android.svg',
                height: 100,
                width: 100,
                isSVG: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
    );
  }
}
