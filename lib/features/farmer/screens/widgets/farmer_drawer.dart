import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 🚀 Added for Haptics
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

// ✅ LOCALIZATION IMPORT
import 'package:agriyukt_app/features/farmer/farmer_translations.dart';

// Screens
import 'package:agriyukt_app/features/auth/screens/login_screen.dart';
import 'package:agriyukt_app/features/farmer/screens/add_crop_screen.dart';
import 'package:agriyukt_app/features/common/screens/settings_screen.dart';
import 'package:agriyukt_app/features/farmer/screens/orders_screen.dart';
import 'package:agriyukt_app/features/farmer/screens/profile_tab.dart';
import 'package:agriyukt_app/features/common/screens/support_screens.dart';

class FarmerDrawer extends StatefulWidget {
  final Function(int)? onTabChange;

  const FarmerDrawer({super.key, this.onTabChange});

  @override
  State<FarmerDrawer> createState() => _FarmerDrawerState();
}

class _FarmerDrawerState extends State<FarmerDrawer> {
  final _supabase = Supabase.instance.client;
  String _userName = "Farmer";
  String _shortId = "0000";

  final Color _primaryGreen = const Color(0xFF1B5E20);

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  // ✅ Helper for Localized Text
  String _text(String key) => FarmerText.get(context, key);

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
                : "0000";

            if (data != null) {
              _userName =
                  "${data['first_name'] ?? ''} ${data['last_name'] ?? ''}"
                      .trim();
              if (_userName.isEmpty) _userName = "Farmer";
            }
          });
        }
      } catch (e) {
        debugPrint("Error fetching drawer data: $e");
      }
    }
  }

  void _navigate(int tabIndex, Widget? screen) {
    HapticFeedback.selectionClick(); // 🚀 Micro-Polish
    Navigator.pop(context);
    if (widget.onTabChange != null) {
      widget.onTabChange!(tabIndex);
    } else if (screen != null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    }
  }

  // 🚀 PRODUCTION: Secure Logout with Confirmation
  Future<void> _handleLogout() async {
    HapticFeedback.mediumImpact();

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_text('logout'),
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Text("Are you sure you want to log out of AgriYukt?",
            style: GoogleFonts.poppins()),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child:
                Text("Cancel", style: GoogleFonts.poppins(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child:
                Text("Logout", style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _supabase.auth.signOut();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text("Logout failed. Try again.", style: GoogleFonts.poppins()),
          backgroundColor: Colors.red,
        ));
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
                  Color(0xFF4CAF50), // Lighter Green
                  Color(0xFF1B5E20), // Deep Green
                ],
              ),
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
                        Colors.lightGreenAccent,
                        Colors.greenAccent,
                        Colors.tealAccent,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Color(0xFF1B5E20), // Inner dark background
                      shape: BoxShape.circle,
                    ),
                    child: CircleAvatar(
                      radius: 32,
                      backgroundColor: Colors.transparent,
                      child: Text(
                        _userName.isNotEmpty ? _userName[0].toUpperCase() : "F",
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
                        "${_text('namaste')} 👋",
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        _userName,
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 18,
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
                          "ID: FRM-$_shortId",
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
                _drawerItem(Icons.person_outline, _text('My Profile'), () {
                  _navigate(3, const ProfileTab());
                }),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Divider(thickness: 0.5, color: Color(0xFFE0E0E0)),
                ),

                // 🚀 UPDATED: Now uses proper home icon
                _drawerItem(Icons.home_outlined, _text('Home'), () {
                  _navigate(0, null);
                }),

                _drawerItem(Icons.add_circle_outline, _text('Add Crop'), () {
                  HapticFeedback.selectionClick();
                  Navigator.pop(context);
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const AddCropScreen()));
                }, color: _primaryGreen, isBold: true),
                _drawerItem(Icons.grass_outlined, _text('My Crops'), () {
                  _navigate(1, null);
                }),
                _drawerItem(Icons.shopping_bag_outlined, _text('Orders'), () {
                  _navigate(2, const OrdersScreen());
                }),

                // 🚀 REMOVED: Bank Details Section Removed

                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Divider(thickness: 0.5, color: Color(0xFFE0E0E0)),
                ),
                _drawerItem(Icons.settings_outlined, _text('Settings'), () {
                  HapticFeedback.selectionClick();
                  Navigator.pop(context);
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => SettingsScreen(
                              themeColor: _primaryGreen, role: 'Farmer')));
                }),
                _drawerItem(Icons.support_agent, _text('Help & Support'), () {
                  HapticFeedback.selectionClick();
                  Navigator.pop(context);
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              ContactSupportScreen(themeColor: _primaryGreen)));
                }),
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
                  _text('Logout'),
                  style: GoogleFonts.poppins(
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                trailing: Icon(Icons.chevron_right_rounded,
                    color: Colors.red.shade700, size: 24),
                onTap: _handleLogout,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Helper Widget for Menu Items ---
  Widget _drawerItem(IconData icon, String text, VoidCallback onTap,
      {Color color = Colors.black87, bool isBold = false}) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 2),
      visualDensity: VisualDensity.compact,
      leading: Icon(icon, color: color, size: 26),
      title: Text(
        text,
        style: GoogleFonts.poppins(
          color: color,
          fontSize: 16,
          fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
        ),
      ),
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
    );
  }
}
