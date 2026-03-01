import 'dart:async';
import 'package:flutter/material.dart';
// IMPORTANT: Import your main.dart or wherever AuthGate is located
import '../main.dart';

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

    _controller = AnimationController(
      duration: const Duration(milliseconds: 2800),
      vsync: this,
    );

    // 1. ZOOM ANIMATION
    _zoomAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.1)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 60,
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(1.1),
        weight: 15,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.1, end: 25.0)
            .chain(CurveTween(curve: Curves.easeInExpo)),
        weight: 25,
      ),
    ]).animate(_controller);

    // 2. OPACITY ANIMATION
    _opacityAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.0),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(1.0),
        weight: 60,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.0),
        weight: 20,
      ),
    ]).animate(_controller);

    _controller.forward();

    // 3. NAVIGATION LOGIC (The Persistence Fix)
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            PageRouteBuilder(
              // Target AuthGate instead of RoleSelection
              pageBuilder: (context, anim1, anim2) => const AuthGate(),
              transitionsBuilder: (context, anim1, anim2, child) {
                return FadeTransition(opacity: anim1, child: child);
              },
              transitionDuration: const Duration(milliseconds: 600),
            ),
          );
        }
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
    // Determine if we are in Dark Mode to adjust text color
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      // Match the scaffold background of your app for a seamless transition
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
                    // The Logo
                    Image.asset(
                      'assets/icon/app_icon.png',
                      width: 180,
                      height: 180,
                      // Error handling if asset is missing
                      errorBuilder: (context, error, stackTrace) =>
                      const Icon(Icons.sync, size: 100, color: Colors.indigo),
                    ),
                    const SizedBox(height: 24),
                    // The App Name
                    //Text(
                      //"CLASS SYNC",
                      //style: TextStyle(
                        //fontSize: 28,
                        //fontWeight: FontWeight.bold,
                        //letterSpacing: 4,
                        //color: isDarkMode ? Colors.white : Colors.indigo[900],
                      //),
                    //),
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