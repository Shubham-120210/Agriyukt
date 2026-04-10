import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

// ✅ CORE SERVICES
import 'package:agriyukt_app/core/services/notification_service.dart';

// ✅ Localization
import 'package:agriyukt_app/core/providers/language_provider.dart';
import 'package:agriyukt_app/features/farmer/farmer_translations.dart';

// ✅ SCREENS
import 'inspector_home_tab.dart';
import 'inspector_add_crop_tab.dart';
import 'inspector_orders_tab.dart';
import 'inspector_profile_tab.dart';
import 'inspector_notification_screen.dart';

// ✅ WIDGETS
import '../widgets/inspector_drawer.dart';

class InspectorLayout extends StatefulWidget {
  const InspectorLayout({super.key});

  @override
  State<InspectorLayout> createState() => _InspectorLayoutState();
}

class _InspectorLayoutState extends State<InspectorLayout> {
  int _currentIndex = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final _supabase = Supabase.instance.client;

  // 🎨 Premium Themes - Deep Purple for Inspectors
  final Color _inspectorColor = const Color(0xFF512DA8);
  final Color _accentPop =
      const Color(0xFFFF9800); // Vibrant Orange for notifications/active tabs

  // 🔔 State
  bool _hasUnreadNotifications = false;

  // 📱 Screens List
  late final List<Widget> _screens = [
    const InspectorHomeTab(),
    InspectorAddCropTab(),
    const InspectorOrdersTab(),
    const InspectorProfileTab(),
  ];

  // 🌍 Cultural Icons mapped directly to the language
  final List<Map<String, dynamic>> _supportedLanguages = [
    {
      "native": "English",
      "english": "English",
      "locale": const Locale('en'),
      "color": Colors.blue,
      "icon": Icons.language
    },
    {
      "native": "हिन्दी",
      "english": "Hindi",
      "locale": const Locale('hi'),
      "color": Colors.orange,
      "icon": Icons.temple_hindu
    },
    {
      "native": "मराठी",
      "english": "Marathi",
      "locale": const Locale('mr'),
      "color": Colors.deepOrange,
      "icon": Icons.fort
    },
    {
      "native": "বাংলা",
      "english": "Bengali",
      "locale": const Locale('bn'),
      "color": Colors.green,
      "icon": Icons.festival
    },
    {
      "native": "தமிழ்",
      "english": "Tamil",
      "locale": const Locale('ta'),
      "color": Colors.red,
      "icon": Icons.architecture
    },
    {
      "native": "తెలుగు",
      "english": "Telugu",
      "locale": const Locale('te'),
      "color": Colors.teal,
      "icon": Icons.account_balance
    },
    {
      "native": "ગુજરાતી",
      "english": "Gujarati",
      "locale": const Locale('gu'),
      "color": Colors.amber,
      "icon": Icons.celebration
    },
    {
      "native": "ಕನ್ನಡ",
      "english": "Kannada",
      "locale": const Locale('kn'),
      "color": Colors.brown,
      "icon": Icons.park
    },
    {
      "native": "മലയാളം",
      "english": "Malayalam",
      "locale": const Locale('ml'),
      "color": Colors.indigo,
      "icon": Icons.sailing
    },
    {
      "native": "ਪੰਜਾਬੀ",
      "english": "Punjabi",
      "locale": const Locale('pa'),
      "color": Colors.purple,
      "icon": Icons.agriculture
    },
  ];

  @override
  void initState() {
    super.initState();
    _checkNotifications();

    // 🚀 Real-time Listener (Safe)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) NotificationService().listenToOrders(context);
    });
  }

  @override
  void dispose() {
    NotificationService().stopListening();
    super.dispose();
  }

  Future<void> _checkNotifications() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user != null) {
        final count = await _supabase
            .from('notifications')
            .count(CountOption.exact)
            .eq('user_id', user.id)
            .eq('is_read', false);

        if (mounted) {
          setState(() => _hasUnreadNotifications = count > 0);
        }
      }
    } catch (e) {
      debugPrint("⚠️ Notification Check Error: $e");
    }
  }

  void _switchTab(int index) {
    if (index == _currentIndex) return;
    setState(() => _currentIndex = index);
  }

  String _text(String key) => FarmerText.get(context, key);

  // 🚀 HIGH-END UI: Stateful Bottom Sheet
  void _showLanguageSelector() {
    final languageProvider =
        Provider.of<LanguageProvider>(context, listen: false);
    String tempSelectedCode = 'en';

    try {
      final dynamic provider = languageProvider;
      tempSelectedCode =
          (provider.appLocale ?? const Locale('en')).languageCode;
    } catch (_) {}

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            final bottomPadding = MediaQuery.of(context).padding.bottom;

            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: Column(
                children: [
                  // --- HEADER SECTION ---
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Select App Language",
                                style: GoogleFonts.poppins(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Choose your preferred language",
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: _inspectorColor.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.public,
                              size: 36, color: _inspectorColor),
                        )
                      ],
                    ),
                  ),

                  // --- 3-COLUMN GRID ---
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: GridView.builder(
                        physics: const BouncingScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 22,
                          childAspectRatio: 0.82,
                        ),
                        itemCount: _supportedLanguages.length,
                        itemBuilder: (context, index) {
                          final lang = _supportedLanguages[index];
                          final bool isSelected =
                              tempSelectedCode == lang['locale'].languageCode;

                          return GestureDetector(
                            onTap: () {
                              setModalState(() {
                                tempSelectedCode = lang['locale'].languageCode;
                              });
                            },
                            child: Stack(
                              clipBehavior: Clip.none,
                              alignment: Alignment.center,
                              children: [
                                // Main Card Background
                                Container(
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? _inspectorColor.withOpacity(0.05)
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: isSelected
                                          ? _inspectorColor
                                          : Colors.grey.shade200,
                                      width: isSelected ? 2.0 : 1.0,
                                    ),
                                    boxShadow: [
                                      if (!isSelected)
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.04),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        )
                                    ],
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      CircleAvatar(
                                        radius: 18,
                                        backgroundColor:
                                            lang['color'].withOpacity(0.12),
                                        child: Icon(lang['icon'],
                                            size: 20, color: lang['color']),
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        lang['native'],
                                        style: GoogleFonts.poppins(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        lang['english'],
                                        style: GoogleFonts.poppins(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                      if (isSelected) const SizedBox(height: 8),
                                    ],
                                  ),
                                ),

                                // Top Right Checkmark
                                if (isSelected)
                                  Positioned(
                                    top: -6,
                                    right: -6,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: _inspectorColor,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.check,
                                          color: Colors.white,
                                          size: 12,
                                          weight: 800),
                                    ),
                                  ),

                                // Bottom Center "Selected" Badge
                                if (isSelected)
                                  Positioned(
                                    bottom: -10,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: _inspectorColor,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        "Selected",
                                        style: GoogleFonts.poppins(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                  // --- BOTTOM ACTION AREA (SAFE AREA PROTECTED) ---
                  Container(
                    padding: EdgeInsets.fromLTRB(24, 20, 24,
                        bottomPadding > 0 ? bottomPadding + 12 : 24),
                    decoration: BoxDecoration(color: Colors.white, boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, -5))
                    ]),
                    child: SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _inspectorColor,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28)),
                          elevation: 0,
                        ),
                        onPressed: () {
                          // 🚀 Apply translation and pop
                          try {
                            final dynamic provider =
                                Provider.of<LanguageProvider>(context,
                                    listen: false);
                            provider.changeLanguage(tempSelectedCode);
                          } catch (_) {}
                          Navigator.pop(context);
                        },
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text("Continue",
                                style: GoogleFonts.poppins(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white)),
                            const SizedBox(width: 8),
                            const Icon(Icons.arrow_forward,
                                color: Colors.white, size: 20),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    Provider.of<LanguageProvider>(context);

    return Scaffold(
      key: _scaffoldKey,
      drawer: InspectorDrawer(onItemSelected: _switchTab),
      appBar: AppBar(
        systemOverlayStyle: SystemUiOverlayStyle.light,
        backgroundColor: _inspectorColor,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.menu, color: Colors.white),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: Text(
          "AgriYukt",
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 22,
            letterSpacing: 0.5,
          ),
        ),
        actions: [
          // 🚀 Translate Button
          IconButton(
            icon: const Icon(Icons.g_translate_rounded,
                color: Colors.white, size: 24),
            onPressed: _showLanguageSelector,
            tooltip: "Change Language",
          ),

          // 🚀 Notifications with clean badge
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined,
                    color: Colors.white, size: 26),
                tooltip: 'Notifications',
                onPressed: () {
                  setState(() => _hasUnreadNotifications = false);
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const InspectorNotificationScreen()));
                },
              ),
              if (_hasUnreadNotifications)
                Positioned(
                  right: 12,
                  top: 12,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _accentPop, // Vibrant Orange Pop
                      shape: BoxShape.circle,
                      border: Border.all(color: _inspectorColor, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),

      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),

      // 🚀 Unifying the UI: Zepto-Style Bottom Navigation Bar
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: _switchTab,
          backgroundColor: Colors.white,
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: _inspectorColor,
          unselectedItemColor: Colors.grey.shade400,
          showUnselectedLabels: true,
          selectedLabelStyle: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
          unselectedLabelStyle: GoogleFonts.poppins(
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
          items: [
            BottomNavigationBarItem(
              icon: const Padding(
                padding: EdgeInsets.only(bottom: 4.0),
                child: Icon(Icons.home_outlined, size: 26),
              ),
              activeIcon: Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: Icon(Icons.home, size: 28, color: _inspectorColor),
              ),
              label: _text('home'),
            ),
            BottomNavigationBarItem(
              icon: const Padding(
                padding: EdgeInsets.only(bottom: 4.0),
                child: Icon(Icons.add_circle_outline, size: 26),
              ),
              activeIcon: Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: Icon(Icons.add_circle, size: 28, color: _inspectorColor),
              ),
              label: _text('add_crop'),
            ),
            BottomNavigationBarItem(
              icon: const Padding(
                padding: EdgeInsets.only(bottom: 4.0),
                child: Icon(Icons.shopping_bag_outlined, size: 26),
              ),
              activeIcon: Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child:
                    Icon(Icons.shopping_bag, size: 28, color: _inspectorColor),
              ),
              label: _text('orders'),
            ),
            BottomNavigationBarItem(
              icon: const Padding(
                padding: EdgeInsets.only(bottom: 4.0),
                child: Icon(Icons.person_outline, size: 26),
              ),
              activeIcon: Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: Icon(Icons.person, size: 28, color: _inspectorColor),
              ),
              label: _text('profile'),
            ),
          ],
        ),
      ),
    );
  }
}
