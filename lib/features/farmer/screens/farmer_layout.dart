import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

// Localization
import 'package:agriyukt_app/features/farmer/farmer_translations.dart';
import 'package:agriyukt_app/core/providers/language_provider.dart';

// Screens
import 'package:agriyukt_app/features/farmer/screens/farmer_home_screen.dart';
import 'package:agriyukt_app/features/farmer/screens/my_crops_tab.dart';
import 'package:agriyukt_app/features/farmer/screens/orders_screen.dart';
import 'package:agriyukt_app/features/farmer/screens/profile_tab.dart';

// ✅ Hide OrdersScreen from alerts_tab to prevent conflict
import 'package:agriyukt_app/features/farmer/screens/alerts_tab.dart'
    hide OrdersScreen;
import 'package:agriyukt_app/features/farmer/screens/widgets/farmer_drawer.dart';

class FarmerLayout extends StatefulWidget {
  final int initialIndex;

  const FarmerLayout({super.key, this.initialIndex = 0});

  @override
  State<FarmerLayout> createState() => _FarmerLayoutState();
}

class _FarmerLayoutState extends State<FarmerLayout> {
  late int _currentIndex;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  Stream<List<Map<String, dynamic>>>? _notificationStream;

  late final List<Widget> _screens = [
    const FarmerHomeScreen(),
    const MyCropsTab(),
    const OrdersScreen(),
    const ProfileTab(),
  ];

  // 🎨 Premium Themes
  final Color _primaryGreen = const Color(0xFF1B5E20);
  final Color _notificationBadge =
      const Color(0xFFFF3D00); // Red strictly for the badge pop

  // 🌍 Production Ready: Cultural Icons mapped directly to the language
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
    _currentIndex = widget.initialIndex;
    _initializeNotificationStream();
  }

  void _initializeNotificationStream() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null && userId.isNotEmpty) {
      _notificationStream = Supabase.instance.client
          .from('notifications')
          .stream(primaryKey: ['id'])
          .eq('user_id', userId)
          .order('created_at', ascending: false);
    }
  }

  void _switchTab(int index) {
    if (_currentIndex == index) return;
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
                            color: Colors.green.shade50,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.public,
                              size: 36, color: Colors.green),
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
                                Container(
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? Colors.green.shade50
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: isSelected
                                          ? _primaryGreen
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
                                if (isSelected)
                                  Positioned(
                                    top: -6,
                                    right: -6,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF1B5E20),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.check,
                                          color: Colors.white,
                                          size: 12,
                                          weight: 800),
                                    ),
                                  ),
                                if (isSelected)
                                  Positioned(
                                    bottom: -10,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF1B5E20),
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

                  // --- BOTTOM ACTION AREA ---
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
                          backgroundColor: _primaryGreen,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28)),
                          elevation: 0,
                        ),
                        onPressed: () {
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
      drawer: FarmerDrawer(onTabChange: _switchTab),
      appBar: AppBar(
        systemOverlayStyle: SystemUiOverlayStyle.light,
        backgroundColor: _primaryGreen,
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
          IconButton(
            icon: const Icon(Icons.g_translate_rounded,
                color: Colors.white, size: 24),
            onPressed: _showLanguageSelector,
            tooltip: "Change Language",
          ),
          if (_notificationStream != null)
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: _notificationStream,
              builder: (context, snapshot) {
                final notifications = snapshot.data ?? [];
                final unreadCount =
                    notifications.where((n) => n['is_read'] == false).length;

                return Stack(
                  alignment: Alignment.center,
                  children: [
                    IconButton(
                      // ✅ Reverted back to the standard notification bell
                      icon: const Icon(Icons.notifications_outlined,
                          color: Colors.white, size: 26),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AlertsTab()),
                      ),
                    ),
                    if (unreadCount > 0)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.all(
                              4), // Even padding for a perfect circle
                          decoration: BoxDecoration(
                            color: _notificationBadge,
                            shape: BoxShape.circle, // ✅ Perfect red circle
                            border:
                                Border.all(color: _primaryGreen, width: 1.5),
                          ),
                          child: Text(
                            // ✅ Format text to "+4", "+9", etc.
                            unreadCount > 9 ? '+9' : '+$unreadCount',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize:
                                  9, // Slightly smaller to fit the plus sign neatly
                              fontWeight: FontWeight.w800,
                              height: 1.0,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                  ],
                );
              },
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(index: _currentIndex, children: _screens),
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
          selectedItemColor: _primaryGreen,
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
                child: Icon(Icons.home, size: 28, color: _primaryGreen),
              ),
              label: _text('home'),
            ),
            BottomNavigationBarItem(
              icon: const Padding(
                padding: EdgeInsets.only(bottom: 4.0),
                child: Icon(Icons.grass_outlined, size: 26),
              ),
              activeIcon: Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: Icon(Icons.grass, size: 28, color: _primaryGreen),
              ),
              label: _text('my_crops').contains(' ')
                  ? _text('my_crops').split(' ').last
                  : _text('my_crops'),
            ),
            BottomNavigationBarItem(
              icon: const Padding(
                padding: EdgeInsets.only(bottom: 4.0),
                child: Icon(Icons.shopping_bag_outlined, size: 26),
              ),
              activeIcon: Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: Icon(Icons.shopping_bag, size: 28, color: _primaryGreen),
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
                child: Icon(Icons.person, size: 28, color: _primaryGreen),
              ),
              label: _text('profile'),
            ),
          ],
        ),
      ),
    );
  }
}
