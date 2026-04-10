import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isNavigating = false;

  // 🚀 Hardware-accelerated background animation
  late AnimationController _bgController;
  late Animation<Alignment> _topAlignment;
  late Animation<Alignment> _bottomAlignment;

  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);

    _topAlignment = TweenSequence<Alignment>([
      TweenSequenceItem(
          tween: Tween(begin: Alignment.topLeft, end: Alignment.topRight),
          weight: 1),
      TweenSequenceItem(
          tween: Tween(begin: Alignment.topRight, end: Alignment.bottomRight),
          weight: 1),
      TweenSequenceItem(
          tween: Tween(begin: Alignment.bottomRight, end: Alignment.bottomLeft),
          weight: 1),
      TweenSequenceItem(
          tween: Tween(begin: Alignment.bottomLeft, end: Alignment.topLeft),
          weight: 1),
    ]).animate(CurvedAnimation(parent: _bgController, curve: Curves.easeInOut));

    _bottomAlignment = TweenSequence<Alignment>([
      TweenSequenceItem(
          tween: Tween(begin: Alignment.bottomRight, end: Alignment.bottomLeft),
          weight: 1),
      TweenSequenceItem(
          tween: Tween(begin: Alignment.bottomLeft, end: Alignment.topLeft),
          weight: 1),
      TweenSequenceItem(
          tween: Tween(begin: Alignment.topLeft, end: Alignment.topRight),
          weight: 1),
      TweenSequenceItem(
          tween: Tween(begin: Alignment.topRight, end: Alignment.bottomRight),
          weight: 1),
    ]).animate(CurvedAnimation(parent: _bgController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _bgController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  // 🚀 Production-Safe Navigation
  Future<void> _finishOnboarding() async {
    if (_isNavigating) return;
    setState(() => _isNavigating = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('seenOnboarding', true);

      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    } catch (e) {
      debugPrint("Error saving onboarding state: $e");
      // Fallback navigation even if prefs fail
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
    }
  }

  void _nextPage() {
    if (_currentPage < 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutQuart,
      );
    } else {
      _finishOnboarding();
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    return Scaffold(
      body: AnimatedBuilder(
        animation: _bgController,
        builder: (context, child) {
          return Container(
            width: size.width,
            height: size.height,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _currentPage == 0
                      ? Colors.green.shade50
                      : Colors.blue.shade50,
                  Colors.white,
                  _currentPage == 0
                      ? Colors.orange.shade50
                      : Colors.green.shade50,
                ],
                begin: _topAlignment.value,
                end: _bottomAlignment.value,
              ),
            ),
            child: child,
          );
        },
        child: SafeArea(
          child: Column(
            children: [
              // --- TOP BAR ---
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _finishOnboarding,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.grey.shade600,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                      ),
                      child: Text("Skip",
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600, fontSize: 15)),
                    ),
                  ],
                ),
              ),

              // --- ANIMATED PAGES ---
              Expanded(
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (index) =>
                      setState(() => _currentPage = index),
                  physics: const BouncingScrollPhysics(),
                  children: [
                    _buildPageContent(
                      title: "Direct Trade &\n3-Role System",
                      description:
                          "Farmers, Buyers, and Coordinator connect directly. No middlemen, full transparency, and maximum profit.",
                      graphic: AnimatedHandshake(isActive: _currentPage == 0),
                    ),
                    _buildPageContent(
                      title: "AI Predictions &\nSecure Trading",
                      description:
                          "Get live wholesale prices and smart AI insights in a 100% verified and secure agricultural ecosystem.",
                      graphic: AnimatedAIBrain(isActive: _currentPage == 1),
                    ),
                  ],
                ),
              ),

              // --- BOTTOM NAVIGATION AREA ---
              Container(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Dynamic Progress Indicators
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                          2, (index) => _buildDotIndicator(index)),
                    ),
                    const SizedBox(height: 32),

                    // Production-grade Button
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _currentPage == 0
                              ? Colors.green.shade700
                              : Colors.blue.shade700,
                          foregroundColor: Colors.white,
                          elevation: 4,
                          shadowColor:
                              (_currentPage == 0 ? Colors.green : Colors.blue)
                                  .withOpacity(0.5),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: _isNavigating ? null : _nextPage,
                        child: _isNavigating
                            ? const SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : Text(
                                _currentPage == 1
                                    ? "Start Trading"
                                    : "Continue",
                                style: GoogleFonts.poppins(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5),
                              ),
                      ),
                    ),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPageContent(
      {required String title,
      required String description,
      required Widget graphic}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Graphic Container (Responsive bounds)
          SizedBox(height: 280, width: double.infinity, child: graphic),
          const SizedBox(height: 40),

          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
                height: 1.3),
          ),
          const SizedBox(height: 16),
          Text(
            description,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                fontSize: 15, color: Colors.black54, height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _buildDotIndicator(int index) {
    bool isCurrent = _currentPage == index;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutQuint,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      height: 8,
      width: isCurrent ? 32 : 8,
      decoration: BoxDecoration(
        color: isCurrent
            ? (_currentPage == 0 ? Colors.green.shade600 : Colors.blue.shade600)
            : Colors.grey.shade300,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

/// ===================================================================
/// RESPONSIVE ANIMATION 1: The Handshake
/// ===================================================================
class AnimatedHandshake extends StatelessWidget {
  final bool isActive;
  const AnimatedHandshake({super.key, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final center = constraints.maxWidth / 2;
      return Stack(
        alignment: Alignment.center,
        children: [
          AnimatedOpacity(
            opacity: isActive ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 800),
            curve: const Interval(0.4, 1.0),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: Colors.green.withOpacity(0.15),
                      blurRadius: 30,
                      spreadRadius: 5)
                ],
              ),
              child: Icon(Icons.handshake_rounded,
                  size: 70, color: Colors.green.shade700),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutBack,
            left: isActive ? center - 90 : -100,
            child: _buildRoleAvatar(Icons.agriculture, Colors.orange.shade600),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutBack,
            right: isActive ? center - 90 : -100,
            child: _buildRoleAvatar(
                Icons.storefront_rounded, Colors.purple.shade600),
          ),
        ],
      );
    });
  }

  Widget _buildRoleAvatar(IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.grey.shade100, width: 2),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 15,
              offset: const Offset(0, 8))
        ],
      ),
      child: Icon(icon, size: 36, color: color),
    );
  }
}

/// ===================================================================
/// RESPONSIVE ANIMATION 2: AI Brain & Analytics
/// ===================================================================
class AnimatedAIBrain extends StatelessWidget {
  final bool isActive;
  const AnimatedAIBrain({super.key, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.8, end: isActive ? 1.2 : 0.8),
          duration: const Duration(milliseconds: 1500),
          curve: Curves
              .elasticOut, // 🚀 FIXED: Changed from easeOutElastic to elasticOut
          builder: (context, value, child) {
            return Transform.scale(
              scale: value,
              child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                            color: Colors.blue.withOpacity(0.2),
                            blurRadius: 40,
                            spreadRadius: 10)
                      ])),
            );
          },
        ),
        Icon(Icons.psychology_rounded, size: 80, color: Colors.blue.shade700),
        Positioned(
          left: 20,
          bottom: 40,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildChartBar(isActive, height: 40, delayMs: 100),
              _buildChartBar(isActive, height: 75, delayMs: 250),
              _buildChartBar(isActive, height: 50, delayMs: 400),
              _buildChartBar(isActive, height: 90, delayMs: 550),
            ],
          ),
        ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 700),
          curve: Curves.elasticOut,
          top: isActive ? 30 : -50,
          right: isActive ? 30 : -50,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 300),
            opacity: isActive ? 1.0 : 0.0,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey.shade100, width: 2),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 15,
                        offset: const Offset(0, 5))
                  ]),
              child: const Icon(Icons.security_rounded,
                  color: Colors.green, size: 30),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChartBar(bool isActive,
      {required double height, required int delayMs}) {
    return AnimatedContainer(
      duration: Duration(milliseconds: 600 + delayMs),
      curve: Curves.easeOutQuint,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      width: 12,
      height: isActive ? height : 0,
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: [Colors.blue.shade400, Colors.blue.shade700],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
        boxShadow: isActive
            ? [BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 5)]
            : [],
      ),
    );
  }
}
