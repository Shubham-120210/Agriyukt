import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingController extends ChangeNotifier {
  String selectedLanguage = 'en';
  int currentPage = 0;
  final PageController pageController = PageController();

  // 1. Select Language
  void selectLanguage(String lang) {
    selectedLanguage = lang;
    notifyListeners();
  }

  // 2. Save Language & Go to Slides (Do NOT save 'seen_onboarding' yet)
  Future<void> saveLanguageAndProceed(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_lang', selectedLanguage);

    if (context.mounted) {
      Navigator.pushReplacementNamed(context, '/onboarding');
    }
  }

  // 3. Handle Page Changes
  void onPageChanged(int index) {
    currentPage = index;
    notifyListeners();
  }

  // 4. Next Button Logic
  void nextPage(BuildContext context) {
    if (currentPage == 2) {
      goToLogin(context);
    } else {
      pageController.nextPage(
          duration: const Duration(milliseconds: 300), curve: Curves.ease);
    }
  }

  // 5. Go to Login (Don't mark as "Seen" permanently, allow loop until login)
  void completeOnboarding(BuildContext context) {
    goToLogin(context);
  }

  void goToLogin(BuildContext context) {
    Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  void dispose() {
    pageController.dispose();
    super.dispose();
  }
}
