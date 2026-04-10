import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 🚀 ADDED THIS LINE FOR HAPTIC FEEDBACK
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:agriyukt_app/core/constants/app_strings.dart';
import 'package:agriyukt_app/core/providers/language_provider.dart';

class LanguageScreen extends StatefulWidget {
  final bool fromProfile;

  const LanguageScreen({super.key, this.fromProfile = false});

  @override
  State<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends State<LanguageScreen> {
  String _selectedLanguage = 'en';
  bool _isLoading = false;

  // 🇮🇳 PAN-INDIA REGIONAL LANGUAGES
  final List<Map<String, String>> _availableLanguages = [
    {'name': 'English', 'code': 'en'},
    {'name': 'मराठी (Marathi)', 'code': 'mr'},
    {'name': 'हिंदी (Hindi)', 'code': 'hi'},
    {'name': 'ગુજરાતી (Gujarati)', 'code': 'gu'},
    {'name': 'தமிழ் (Tamil)', 'code': 'ta'},
    {'name': 'తెలుగు (Telugu)', 'code': 'te'},
    {'name': 'ಕನ್ನಡ (Kannada)', 'code': 'kn'},
    {'name': 'বাংলা (Bengali)', 'code': 'bn'},
    {'name': 'ਪੰਜਾਬੀ (Punjabi)', 'code': 'pa'},
    {'name': 'മലയാളം (Malayalam)', 'code': 'ml'},
    {'name': 'ଓଡ଼ିଆ (Odia)', 'code': 'or'},
    {'name': 'অসমীয়া (Assamese)', 'code': 'as'},
  ];

  @override
  void initState() {
    super.initState();
    _loadCurrentLanguage();
  }

  Future<void> _loadCurrentLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _selectedLanguage = prefs.getString('language_code') ?? 'en';
      });
    }
  }

  Future<void> _saveAndProceed() async {
    setState(() => _isLoading = true);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language_code', _selectedLanguage);

    // ✅ CRITICAL FIX 1: Set the flag so Splash knows language is selected
    await prefs.setBool('isLanguageSet', true);

    if (!mounted) return;

    // Update Provider
    Provider.of<LanguageProvider>(context, listen: false)
        .changeLanguage(_selectedLanguage);

    // Dynamic success message
    String successMsg = "Language Updated!";
    if (_selectedLanguage == 'mr') successMsg = "भाषा बदलली!";
    if (_selectedLanguage == 'hi') successMsg = "भाषा अपडेट की गई!";

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(successMsg, style: GoogleFonts.poppins()),
      backgroundColor: Colors.green.shade700,
      duration: const Duration(milliseconds: 800),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));

    // ✅ CRITICAL FIX 2: Navigate to Onboarding, NOT Login
    if (widget.fromProfile) {
      Navigator.pop(context, true);
    } else {
      // Use named route to ensure we hit the Onboarding Screen next
      Navigator.pushReplacementNamed(context, '/onboarding');
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Safe fallback in case translation map doesn't have the key yet
    final strings =
        AppStrings.languages[_selectedLanguage] ?? AppStrings.languages['en']!;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: widget.fromProfile
          ? AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              centerTitle: true,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
                onPressed: () => Navigator.pop(context),
              ),
              title: Text(
                _selectedLanguage == 'mr'
                    ? "भाषा निवडा"
                    : (_selectedLanguage == 'hi'
                        ? "भाषा चुनें"
                        : "Select Language"),
                style: GoogleFonts.poppins(
                    color: Colors.black, fontWeight: FontWeight.bold),
              ),
            )
          : null,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Column(
            children: [
              if (!widget.fromProfile) const SizedBox(height: 20),

              // 🎨 TOP ICON
              AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                padding: const EdgeInsets.all(25),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: Colors.green.withOpacity(0.2),
                        blurRadius: 20,
                        spreadRadius: 5)
                  ],
                ),
                child: const Icon(Icons.translate_rounded,
                    size: 60, color: Colors.green),
              ),
              const SizedBox(height: 24),

              // 📝 TITLE
              Text(
                widget.fromProfile
                    ? (_selectedLanguage == 'mr'
                        ? "भाषा बदला"
                        : (_selectedLanguage == 'hi'
                            ? "भाषा बदलें"
                            : "Change Language"))
                    : strings['welcome_msg']!,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade700),
              ),
              const SizedBox(height: 8),

              // 📝 SUBTITLE
              Text(
                strings['select_lang'] ??
                    "Please select your preferred language",
                style: GoogleFonts.poppins(
                    fontSize: 15, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 30),

              // 📜 SCROLLABLE LANGUAGE LIST (Fixes Overflow)
              Expanded(
                child: ListView.separated(
                  physics: const BouncingScrollPhysics(),
                  itemCount: _availableLanguages.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final lang = _availableLanguages[index];
                    return _buildLangOption(lang['name']!, lang['code']!);
                  },
                ),
              ),
              const SizedBox(height: 20),

              // 🚀 BOTTOM ACTION BUTTON
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15)),
                    elevation: 5,
                    shadowColor: Colors.green.withOpacity(0.4),
                  ),
                  onPressed: _isLoading ? null : _saveAndProceed,
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          widget.fromProfile
                              ? (_selectedLanguage == 'mr'
                                  ? "बदल जतन करा"
                                  : (_selectedLanguage == 'hi'
                                      ? "परिवर्तन सहेजें"
                                      : "Save Changes"))
                              : (strings['get_started'] ?? "Get Started"),
                          style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLangOption(String name, String code) {
    bool selected = _selectedLanguage == code;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() {
          _selectedLanguage = code;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        decoration: BoxDecoration(
          color: selected ? Colors.green.withOpacity(0.08) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: selected ? Colors.green.shade600 : Colors.grey.shade200,
              width: selected ? 2 : 1.5),
          boxShadow: selected
              ? [
                  BoxShadow(
                      color: Colors.green.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4))
                ]
              : [],
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                name,
                style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                    color: selected ? Colors.green.shade800 : Colors.black87),
              ),
            ),
            AnimatedScale(
              scale: selected ? 1.1 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? Colors.green.shade600 : Colors.grey.shade400,
              ),
            )
          ],
        ),
      ),
    );
  }
}
