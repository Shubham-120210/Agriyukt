import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 🚀 Added for Haptics
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

// ✅ Screen Imports
import 'package:agriyukt_app/features/auth/screens/login_screen.dart';
import 'package:agriyukt_app/features/common/screens/settings_screen.dart';
import 'package:agriyukt_app/features/common/screens/wallet_screen.dart';
import 'package:agriyukt_app/features/inspector/screens/inspector_farmers_tab.dart';
import 'package:agriyukt_app/features/common/screens/support_screens.dart';

class InspectorDrawer extends StatefulWidget {
  final Function(int) onItemSelected;
  const InspectorDrawer({super.key, required this.onItemSelected});

  @override
  State<InspectorDrawer> createState() => _InspectorDrawerState();
}

class _InspectorDrawerState extends State<InspectorDrawer> {
  final _supabase = Supabase.instance.client;
  String _userName = "Officer";
  String _shortId = "0000";
  String _email = "";

  // 🎨 Inspector Theme Colors (Deep Purple)
  final Color _primaryPurple = const Color(0xFF512DA8);

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
            _email = user.email ?? "";
            _shortId = user.id.length > 5
                ? user.id.substring(0, 4).toUpperCase()
                : "0000";

            if (data != null) {
              String fName = data['first_name'] ?? '';
              String lName = data['last_name'] ?? '';
              _userName = "$fName $lName".trim();
              if (_userName.isEmpty) _userName = "Inspector";
            }
          });
        }
      } catch (e) {
        debugPrint("Error fetching inspector data: $e");
      }
    }
  }

  void _navigate(int tabIndex, Widget? screen) {
    HapticFeedback.selectionClick(); // 🚀 Micro-Polish
    Navigator.pop(context);
    if (screen != null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    } else {
      widget.onItemSelected(tabIndex);
    }
  }

  // 🚀 PRODUCTION: Secure Logout with Confirmation
  Future<void> _handleLogout() async {
    HapticFeedback.mediumImpact();

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Log Out",
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
                  Color(0xFF7E57C2), // Lighter Purple
                  Color(0xFF512DA8), // Deep Purple
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
                        Colors.purpleAccent,
                        Colors.pinkAccent,
                        Colors.cyanAccent,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Color(0xFF512DA8), // Inner dark background
                      shape: BoxShape.circle,
                    ),
                    child: CircleAvatar(
                      radius: 32,
                      backgroundColor: Colors.transparent,
                      child: Text(
                        _userName.isNotEmpty ? _userName[0].toUpperCase() : "I",
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
                          "ID: OFF-$_shortId",
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
                _drawerItem(Icons.person_outline, "My Profile", () {
                  _navigate(3, null); // Profile Tab
                }),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Divider(thickness: 0.5, color: Color(0xFFE0E0E0)),
                ),
                _drawerItem(Icons.dashboard_outlined, "Dashboard", () {
                  _navigate(0, null); // Dashboard Tab
                }),
                _drawerItem(Icons.add_circle_outline, "Add Crop", () {
                  _navigate(1, null); // Add Crop Tab
                }, color: _primaryPurple, isBold: true),
                _drawerItem(Icons.people_outline, "Mapped Farmers", () {
                  _navigate(-1, const InspectorFarmersTab());
                }),
                _drawerItem(Icons.shopping_bag_outlined, "Monitor Orders", () {
                  _navigate(2, null); // Monitor Orders Tab
                }),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Divider(thickness: 0.5, color: Color(0xFFE0E0E0)),
                ),
                _drawerItem(Icons.account_balance_wallet_outlined, "My Wallet",
                    () {
                  _navigate(-1, WalletScreen(themeColor: _primaryPurple));
                }),
                _drawerItem(Icons.settings_outlined, "Settings", () {
                  _navigate(
                      -1,
                      SettingsScreen(
                          themeColor: _primaryPurple, role: 'inspector'));
                }),
                _drawerItem(Icons.support_agent, "Help & Support", () {
                  _navigate(
                      -1, ContactSupportScreen(themeColor: _primaryPurple));
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
                  "Logout",
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
