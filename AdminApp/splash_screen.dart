import 'package:flutter/material.dart';
import 'main.dart'; // To access AdminAuthGate

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _zoomAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();

    // Total duration of the splash sequence
    _controller = AnimationController(
      duration: const Duration(milliseconds: 2800),
      vsync: this,
    );

    // 1. ZOOM ANIMATION (The "Break the Glass" Effect)
    _zoomAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.1)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 60, // Entrance and bounce
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(1.1),
        weight: 15, // Brief "calm before the storm" pause
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.1, end: 25.0)
            .chain(CurveTween(curve: Curves.easeInExpo)), // Rapid zoom past user
        weight: 25,
      ),
    ]).animate(_controller);

    // 2. OPACITY ANIMATION
    _opacityAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.0),
        weight: 20, // Fade in
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(1.0),
        weight: 60, // Stay solid
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.0),
        weight: 20, // Fade out as it zooms past
      ),
    ]).animate(_controller);

    _controller.forward();

    // 3. NAVIGATION (To Admin Auth Logic)
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            // Navigates to AdminAuthGate defined in your main.dart
            pageBuilder: (context, anim1, anim2) => const AdminAuthGate(),
            transitionsBuilder: (context, anim1, anim2, child) {
              return FadeTransition(opacity: anim1, child: child);
            },
            transitionDuration: const Duration(milliseconds: 600),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Center(
            child: Transform.scale(
              scale: _zoomAnimation.value,
              child: Opacity(
                opacity: _opacityAnimation.value,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Admin App Logo
                    Image.asset(
                      'assets/icon/app_icon.png',
                      width: 220,
                      height: 220,
                    ),
                    const SizedBox(height: 20),
                    // Admin Branding
                    const Text(
                      'ClassSync ADMIN',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                        color: Color(0xFFB71C1C), // Deep Red for Admin
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Management Portal',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}