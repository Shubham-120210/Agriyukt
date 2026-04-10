import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

// ✅ Screen Imports
import 'package:agriyukt_app/features/auth/screens/login_screen.dart';
import 'package:agriyukt_app/features/common/screens/settings_screen.dart';
import 'package:agriyukt_app/features/buyer/screens/buyer_favorites_screen.dart';
import 'package:agriyukt_app/features/common/screens/support_screens.dart';

class BuyerDrawer extends StatefulWidget {
  final Function(int) onTabChange;
  const BuyerDrawer({super.key, required this.onTabChange});

  @override
  State<BuyerDrawer> createState() => _BuyerDrawerState();
}

class _BuyerDrawerState extends State<BuyerDrawer> {
  final _supabase = Supabase.instance.client;
  String _userName = "Buyer";
  String _shortId = "0000";

  // ✅ Premium Buyer Blue Theme
  final Color _buyerBlue = const Color(0xFF1565C0);

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    final user = _supabase.auth.currentUser;
    if (user != null) {
      try {
        final data = await _supabase
            .from('profiles')
            .select('first_name, last_name')
            .eq('id', user.id)
            .maybeSingle();

        if (mounted) {
          setState(() {
            _shortId = user.id.length > 4
                ? user.id.substring(0, 4).toUpperCase()
                : "0778";

            if (data != null) {
              _userName =
                  "${data['first_name'] ?? ''} ${data['last_name'] ?? ''}"
                      .trim();
              if (_userName.isEmpty) _userName = "Buyer";
            }
          });
        }
      } catch (e) {
        debugPrint("Error fetching drawer data: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      child: Column(
        children: [
          // ==========================================
          // 1. CRISP PREMIUM HEADER
          // ==========================================
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(
                20, MediaQuery.of(context).padding.top + 20, 20, 30),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF2979FF), // Lighter Blue
                  Color(0xFF0D47A1), // Deep Blue
                ],
              ),
              // 🚀 FIX: Clean, symmetrical bottom border instead of a weird blurry wave
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 🌟 Clean Glowing Avatar Ring
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        Colors.cyanAccent,
                        Colors.blueAccent,
                        Colors.purpleAccent
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Color(0xFF0D47A1), // Inner dark background
                      shape: BoxShape.circle,
                    ),
                    child: CircleAvatar(
                      radius: 32, // Slightly adjusted to fit perfectly
                      backgroundColor: Colors.transparent,
                      child: Text(
                        _userName.isNotEmpty ? _userName[0].toUpperCase() : "B",
                        style: GoogleFonts.poppins(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // 📝 User Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Namaste 👋",
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      // 🚀 FIX: Surname cutting off is fixed by maxLines: 2
                      Text(
                        _userName,
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 18, // Font scaled perfectly
                          fontWeight: FontWeight.bold,
                          height: 1.2,
                        ),
                        maxLines: 2, // Allows long names to wrap elegantly
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      // 🆔 Crisp ID Pill
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white
                              .withOpacity(0.2), // Clean translucent
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          "ID: BUY-$_shortId",
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ==========================================
          // 2. MENU ITEMS
          // ==========================================
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 10),
              physics: const BouncingScrollPhysics(),
              children: [
                _drawerItem(
                  icon: Icons.person_outline,
                  text: "My Profile",
                  onTap: () {
                    Navigator.pop(context);
                    widget.onTabChange(3); // Profile Tab
                  },
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Divider(thickness: 0.5, color: Color(0xFFE0E0E0)),
                ),
                _drawerItem(
                  icon: Icons.home_outlined,
                  text: "Home",
                  onTap: () {
                    Navigator.pop(context);
                    widget.onTabChange(0); // Home Tab
                  },
                ),
                _drawerItem(
                  icon: Icons.storefront_outlined,
                  text: "Market",
                  onTap: () {
                    Navigator.pop(context);
                    widget.onTabChange(1); // Market Tab
                  },
                ),
                _drawerItem(
                  icon: Icons.favorite_border,
                  text: "My Favorites",
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const BuyerFavoritesScreen()),
                    );
                  },
                ),
                _drawerItem(
                  icon: Icons.receipt_long_outlined,
                  text: "My Orders",
                  onTap: () {
                    Navigator.pop(context);
                    widget.onTabChange(2); // Orders Tab
                  },
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Divider(thickness: 0.5, color: Color(0xFFE0E0E0)),
                ),
                _drawerItem(
                  icon: Icons.settings_outlined,
                  text: "Settings",
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SettingsScreen(
                          themeColor: _buyerBlue,
                          role: 'buyer',
                        ),
                      ),
                    );
                  },
                ),
                _drawerItem(
                  icon: Icons.support_agent,
                  text: "Help & Support",
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            ContactSupportScreen(themeColor: _buyerBlue),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          // ==========================================
          // 3. PREMIUM LOGOUT BUTTON
          // ==========================================
          SafeArea(
            bottom: true,
            child: Container(
              margin: const EdgeInsets.fromLTRB(20, 10, 20, 24),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF0F0), // Very light red
                borderRadius: BorderRadius.circular(16),
              ),
              child: ListTile(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                leading: Icon(Icons.logout_rounded,
                    color: Colors.red.shade700, size: 24),
                title: Text(
                  "Logout",
                  style: GoogleFonts.poppins(
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                trailing: Icon(Icons.chevron_right_rounded,
                    color: Colors.red.shade700, size: 24),
                onTap: () async {
                  await _supabase.auth.signOut();
                  if (context.mounted) {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                      (route) => false,
                    );
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Helper Widget for Menu Items ---
  Widget _drawerItem({
    required IconData icon,
    required String text,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 2),
      visualDensity: VisualDensity.compact,
      leading: Icon(icon, color: Colors.black87, size: 26),
      title: Text(
        text,
        style: GoogleFonts.poppins(
          color: Colors.black87,
          fontSize: 16,
          fontWeight: FontWeight.w600, // Slightly bolder to match screenshot
        ),
      ),
      onTap: onTap,
    );
  }
}
