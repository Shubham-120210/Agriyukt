import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

// Localization
import 'package:agriyukt_app/core/providers/language_provider.dart';
import 'package:agriyukt_app/features/farmer/farmer_translations.dart'; // Reusing your global dictionary

// Screens
import '../widgets/buyer_drawer.dart';
import 'buyer_home_screen.dart';
import 'buyer_marketplace_screen.dart';
import 'buyer_profile_screen.dart';
import 'buyer_orders_screen.dart';
import 'buyer_favorites_screen.dart';
import 'package:agriyukt_app/features/buyer/screens/buyer_notification_screen.dart';

class BuyerDashboard extends StatefulWidget {
  const BuyerDashboard({super.key});

  @override
  State<BuyerDashboard> createState() => _BuyerDashboardState();
}

class _BuyerDashboardState extends State<BuyerDashboard> {
  int _currentIndex = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final _supabase = Supabase.instance.client;

  Stream<List<Map<String, dynamic>>>? _notificationStream;

  // 🎨 Premium Themes - AgriYukt Buyer Blue
  final Color _primaryColor = const Color(0xFF1565C0);
  final Color _notificationBadge =
      const Color(0xFFFF3D00); // Red strictly for the badge pop

  final List<Widget> _screens = [
    const BuyerHomeScreen(),
    const BuyerMarketplaceScreen(),
    const BuyerOrdersScreen(),
    const BuyerProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _initializeNotificationStream();
  }

  // 🚀 PERFORMANCE FIX: Initialize stream once to prevent infinite rebuild queries
  void _initializeNotificationStream() {
    final userId = _supabase.auth.currentUser?.id;
    if (userId != null && userId.isNotEmpty) {
      _notificationStream = _supabase
          .from('notifications')
          .stream(primaryKey: ['id'])
          .eq('user_id', userId)
          .order('created_at', ascending: false);
    }
  }

  void _onTabChange(int index) {
    if (_currentIndex == index) return;
    setState(() {
      _currentIndex = index;
    });
  }

  String _text(String key) => FarmerText.get(context, key);

  @override
  Widget build(BuildContext context) {
    Provider.of<LanguageProvider>(context); // Listens to translation changes

    return Scaffold(
      key: _scaffoldKey,
      drawer: BuyerDrawer(onTabChange: _onTabChange),
      appBar: AppBar(
        systemOverlayStyle: SystemUiOverlayStyle.light,
        backgroundColor: _primaryColor,
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
          // 🚀 1. Buyer Favorites Icon
          IconButton(
            icon: const Icon(Icons.favorite_border_rounded,
                color: Colors.white, size: 24),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BuyerFavoritesScreen()),
              );
            },
          ),

          // 🚀 2. Buyer Notification Stream
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
                      icon: const Icon(Icons.notifications_outlined,
                          color: Colors.white, size: 26),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const BuyerNotificationScreen()),
                        );
                      },
                    ),
                    if (unreadCount > 0)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.all(
                              4), // Even padding for a perfect circle
                          decoration: BoxDecoration(
                            color: _notificationBadge, // Perfect red circle pop
                            shape: BoxShape.circle,
                            border:
                                Border.all(color: _primaryColor, width: 1.5),
                          ),
                          child: Text(
                            // Format text to "+4", "+9", etc.
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

      // 🚀 Unifying the UI: Footer strictly using Buyer Blue (_primaryColor)
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
          onTap: _onTabChange,
          backgroundColor: Colors.white,
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: _primaryColor, // ✅ UPDATED: Header Blue
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
                child: Icon(Icons.home,
                    size: 28, color: _primaryColor), // ✅ UPDATED
              ),
              label: _text('home'),
            ),
            BottomNavigationBarItem(
              icon: const Padding(
                padding: EdgeInsets.only(bottom: 4.0),
                child: Icon(Icons.storefront_outlined, size: 26),
              ),
              activeIcon: Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: Icon(Icons.storefront,
                    size: 28, color: _primaryColor), // ✅ UPDATED
              ),
              label: 'Market', // Specific to Buyer
            ),
            BottomNavigationBarItem(
              icon: const Padding(
                padding: EdgeInsets.only(bottom: 4.0),
                child: Icon(Icons.receipt_long_outlined, size: 26),
              ),
              activeIcon: Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: Icon(Icons.receipt_long,
                    size: 28, color: _primaryColor), // ✅ UPDATED
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
                child: Icon(Icons.person,
                    size: 28, color: _primaryColor), // ✅ UPDATED
              ),
              label: _text('profile'),
            ),
          ],
        ),
      ),
    );
  }
}
