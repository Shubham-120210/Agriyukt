import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart'; // For Haptics & Clipboard
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart'; // 🚀 FOR RATE APP & POLICIES

// ✅ LOCALIZATION & PROVIDERS
import 'package:agriyukt_app/features/farmer/farmer_translations.dart';
import 'package:agriyukt_app/core/providers/language_provider.dart';

// ✅ SCREEN IMPORTS
import 'package:agriyukt_app/features/auth/screens/login_screen.dart';
import 'package:agriyukt_app/features/buyer/screens/buyer_edit_profile_screen.dart';
import 'package:agriyukt_app/features/common/screens/settings_screen.dart';
import 'package:agriyukt_app/features/common/screens/support_chat_screen.dart';
import 'package:agriyukt_app/features/common/screens/invite_friend_screen.dart';
import 'package:agriyukt_app/features/common/screens/wallet_screen.dart';

class BuyerProfileScreen extends StatefulWidget {
  const BuyerProfileScreen({super.key});

  @override
  State<BuyerProfileScreen> createState() => _BuyerProfileScreenState();
}

class _BuyerProfileScreenState extends State<BuyerProfileScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  String _name = "Buyer";

  // Internal status tracker
  String _internalStatus = "Pending";

  // Theme Colors (Buyer Blue)
  final Color _buyerColor = const Color(0xFF1565C0);
  final Color _lightBlue = const Color(0xFF42A5F5);
  final Color _bgOffWhite = const Color(0xFFF4F6F8);

  @override
  void initState() {
    super.initState();
    _fetchProfileData();
  }

  // ✅ Helper for Localized Text
  String _text(String key) => FarmerText.get(context, key);

  Future<void> _fetchProfileData() async {
    // UX Polish: Only show full loader on FIRST load.
    if (_name == "Buyer") {
      setState(() => _isLoading = true);
    }

    final user = _supabase.auth.currentUser;
    if (user != null) {
      try {
        final data = await _supabase
            .from('profiles')
            .select(
                'first_name, last_name, verification_status, aadhar_front_url, aadhar_back_url, aadhar_number')
            .eq('id', user.id)
            .maybeSingle();

        if (mounted) {
          setState(() {
            if (data != null) {
              String fName = data['first_name'] ?? '';
              String lName = data['last_name'] ?? '';
              _name = "$fName $lName".trim();
              if (_name.isEmpty) _name = "Buyer";

              // ✅ ROBUST STATUS CHECK
              String dbStatus =
                  (data['verification_status'] ?? 'Pending').toString();
              String? frontUrl = data['aadhar_front_url'];
              String? backUrl = data['aadhar_back_url'];
              String? num = data['aadhar_number'];

              if (dbStatus.toLowerCase() == 'verified') {
                _internalStatus = "Verified";
              } else if (frontUrl != null &&
                  frontUrl.isNotEmpty &&
                  backUrl != null &&
                  backUrl.isNotEmpty &&
                  num != null &&
                  num.isNotEmpty) {
                _internalStatus = "Under Review";
              } else {
                _internalStatus = "Pending";
              }
            }
            _isLoading = false;
          });
        }
      } catch (e) {
        debugPrint("Error fetching profile: $e");
        if (mounted) setState(() => _isLoading = false);
      }
    } else {
      if (mounted) _logout();
    }
  }

  String _getShortId() {
    final uid = _supabase.auth.currentUser?.id ?? "";
    if (uid.length < 5) return "0000";
    return uid.substring(0, 5).toUpperCase();
  }

  // 🚀 PRODUCTION: Secure Logout with Confirmation
  Future<void> _logout() async {
    HapticFeedback.mediumImpact();

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(_text('logout'),
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Text("Are you sure you want to log out?",
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
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700, elevation: 0),
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
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Logout failed. Check internet.",
                style: GoogleFonts.poppins()),
            backgroundColor: Colors.red));
      }
    }
  }

  // ---------------------------------------------------------------------------
  // 🌟 APP INFO & RATING LOGIC
  // ---------------------------------------------------------------------------
  Future<void> _rateApp() async {
    HapticFeedback.mediumImpact();
    // 🚀 LIVE PLAY STORE LINK
    final Uri url = Uri.parse(
        'https://play.google.com/store/apps/details?id=com.agriyukt.app');

    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        throw "Could not launch store.";
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text("Could not open app store.", style: GoogleFonts.poppins()),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _openLink(String urlString) async {
    HapticFeedback.lightImpact();
    final Uri url = Uri.parse(urlString);

    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        throw "Could not launch link.";
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Could not open link.", style: GoogleFonts.poppins()),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showAboutApp() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 5,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10)),
              ),
              Container(
                height: 80,
                width: 80,
                decoration: BoxDecoration(
                  color: _buyerColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(24),
                  border:
                      Border.all(color: _buyerColor.withOpacity(0.2), width: 2),
                ),
                child: Icon(Icons.eco_rounded, size: 40, color: _buyerColor),
              ),
              const SizedBox(height: 16),
              Text("AgriYukt",
                  style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                      letterSpacing: -0.5)),
              Text("Version 1.0.0 (Production)",
                  style: GoogleFonts.jetBrainsMono(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 24),
              Text(
                "Empowering farmers, buyers, and inspectors with a seamless, transparent, and technology-driven agricultural supply chain.",
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 14, color: Colors.grey.shade600, height: 1.6),
              ),
              const SizedBox(height: 32),

              // 🚀 GITHUB PAGES LINKS
              _buildAboutLinkRow(
                  Icons.description_outlined,
                  "Terms of Service",
                  () => _openLink(
                      'https://agriyukt.github.io/agriyukt-legal/terms.html')),
              const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Divider(height: 1)),
              _buildAboutLinkRow(
                  Icons.privacy_tip_outlined,
                  "Privacy Policy",
                  () => _openLink(
                      'https://agriyukt.github.io/agriyukt-legal/privacy.html')),

              const SizedBox(height: 32),
              Text("Made with ❤️ in India",
                  style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade400)),
              SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAboutLinkRow(IconData icon, String title, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Colors.grey.shade600),
            const SizedBox(width: 12),
            Expanded(
                child: Text(title,
                    style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: Colors.black87,
                        fontWeight: FontWeight.w500))),
            Icon(Icons.arrow_forward_ios_rounded,
                size: 14, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Provider.of<LanguageProvider>(context);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: _bgOffWhite,
        body: Center(child: CircularProgressIndicator(color: _buyerColor)),
      );
    }

    final memberId = _getShortId();

    return Scaffold(
      backgroundColor: _bgOffWhite,
      appBar: AppBar(
        backgroundColor: _bgOffWhite,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        title: Text("My Profile",
            style: GoogleFonts.poppins(
                color: Colors.black87,
                fontSize: 24,
                fontWeight: FontWeight.bold)),
      ),
      body: RefreshIndicator(
        onRefresh: _fetchProfileData,
        color: _buyerColor,
        backgroundColor: Colors.white,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics()),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),

                // ==========================================
                // 1. PREMIUM DIGITAL ID CARD (BUYER THEME)
                // ==========================================
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [_buyerColor, _lightBlue],
                      begin: Alignment.bottomLeft,
                      end: Alignment.topRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: _buyerColor.withOpacity(0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      )
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 35,
                            backgroundColor: Colors.white,
                            child: Text(
                                _name.isNotEmpty ? _name[0].toUpperCase() : "B",
                                style: GoogleFonts.poppins(
                                    color: _buyerColor,
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("${_text('namaste')} 👋",
                                    style: GoogleFonts.poppins(
                                        color: Colors.white70, fontSize: 14)),
                                Text(_name,
                                    style: GoogleFonts.poppins(
                                        color: Colors.white,
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text("BUY-$memberId",
                                        style: GoogleFonts.jetBrainsMono(
                                            color:
                                                Colors.white.withOpacity(0.9),
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600)),
                                    const SizedBox(width: 8),
                                    GestureDetector(
                                      onTap: () {
                                        HapticFeedback.selectionClick();
                                        Clipboard.setData(ClipboardData(
                                            text: "BUY-$memberId"));
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(SnackBar(
                                          content: Text("ID Copied!",
                                              style: GoogleFonts.poppins()),
                                          duration: const Duration(
                                              milliseconds: 1000),
                                          behavior: SnackBarBehavior.floating,
                                        ));
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                            color:
                                                Colors.white.withOpacity(0.2),
                                            shape: BoxShape.circle),
                                        child: const Icon(Icons.copy,
                                            size: 12, color: Colors.white),
                                      ),
                                    )
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Divider(color: Colors.white24, height: 1),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("KYC Status",
                              style: GoogleFonts.poppins(
                                  color: Colors.white.withOpacity(0.9),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500)),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                                color: _internalStatus == "Verified"
                                    ? Colors.white
                                    : (_internalStatus == "Under Review"
                                        ? Colors.white.withOpacity(0.9)
                                        : Colors.orange.shade50),
                                borderRadius: BorderRadius.circular(20)),
                            child: Row(
                              children: [
                                Icon(
                                    _internalStatus == "Verified"
                                        ? Icons.verified_rounded
                                        : (_internalStatus == "Under Review"
                                            ? Icons.hourglass_top_rounded
                                            : Icons.error_outline_rounded),
                                    size: 14,
                                    color: _internalStatus == "Verified"
                                        ? Colors.green.shade700
                                        : (_internalStatus == "Under Review"
                                            ? _buyerColor
                                            : Colors.orange.shade800)),
                                const SizedBox(width: 4),
                                Text(
                                  _internalStatus == "Verified"
                                      ? "VERIFIED"
                                      : (_internalStatus == "Under Review"
                                          ? "UNDER REVIEW"
                                          : "PENDING"),
                                  style: GoogleFonts.poppins(
                                      color: _internalStatus == "Verified"
                                          ? Colors.green.shade700
                                          : (_internalStatus == "Under Review"
                                              ? _buyerColor
                                              : Colors.orange.shade800),
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5),
                                ),
                              ],
                            ),
                          )
                        ],
                      )
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // ==========================================
                // 2. ACCOUNT & FINANCE GROUP
                // ==========================================
                Text("Account",
                    style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade600,
                        letterSpacing: 1)),
                const SizedBox(height: 8),
                _buildMenuGroup([
                  _buildMenuItem(
                    icon: Icons.person_outline_rounded,
                    title: "Personal Details",
                    subtitle: "Update your profile & KYC documents",
                    onTap: () async {
                      await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const BuyerEditProfileScreen()));
                      if (mounted) _fetchProfileData();
                    },
                  ),
                  _buildDivider(),
                  _buildMenuItem(
                    icon: Icons.account_balance_wallet_outlined,
                    title: "Wallet & Payments",
                    subtitle: "Manage your linked bank accounts",
                    onTap: () {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  WalletScreen(themeColor: _buyerColor)));
                    },
                  ),
                ]),
                const SizedBox(height: 24),

                // ==========================================
                // 3. HELP & COMMUNITY GROUP
                // ==========================================
                Text("Support & Community",
                    style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade600,
                        letterSpacing: 1)),
                const SizedBox(height: 8),
                _buildMenuGroup([
                  _buildMenuItem(
                    icon: Icons.support_agent_rounded,
                    title: "AgriBot",
                    subtitle: "24/7 intelligent farming assistant",
                    iconColor: Colors.teal.shade600,
                    onTap: () {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  const SupportChatScreen(role: 'buyer')));
                    },
                  ),
                  _buildDivider(),
                  _buildMenuItem(
                    icon: Icons.card_giftcard_rounded,
                    title: "Invite a Friend",
                    subtitle: "Share AgriYukt and grow the community",
                    iconColor: Colors.orange.shade600,
                    onTap: () {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const InviteFriendScreen()));
                    },
                  ),
                ]),
                const SizedBox(height: 24),

                // ==========================================
                // 4. APP SETTINGS GROUP
                // ==========================================
                Text("Preferences",
                    style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade600,
                        letterSpacing: 1)),
                const SizedBox(height: 8),
                _buildMenuGroup([
                  _buildMenuItem(
                    icon: Icons.settings_outlined,
                    title: "Settings",
                    subtitle: "Notifications, security & theme",
                    onTap: () {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => SettingsScreen(
                                  themeColor: _buyerColor, role: 'buyer')));
                    },
                  ),
                ]),
                const SizedBox(height: 24),

                // ==========================================
                // 🚀 5. APP INFO & RATING SECTION
                // ==========================================
                Text("App Info",
                    style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade600,
                        letterSpacing: 1)),
                const SizedBox(height: 8),
                _buildMenuGroup([
                  _buildMenuItem(
                    icon: Icons.star_border_rounded,
                    title: "Rate Us",
                    subtitle: "Love AgriYukt? Leave a review!",
                    iconColor: Colors.amber.shade600,
                    onTap: _rateApp,
                  ),
                  _buildDivider(),
                  _buildMenuItem(
                    icon: Icons.info_outline_rounded,
                    title: "About App",
                    subtitle: "Version, Terms & Privacy",
                    iconColor: _buyerColor,
                    onTap: _showAboutApp,
                  ),
                ]),
                const SizedBox(height: 32),

                // ==========================================
                // 6. LOGOUT BUTTON
                // ==========================================
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: OutlinedButton.icon(
                    onPressed: _logout,
                    icon:
                        Icon(Icons.logout_rounded, color: Colors.red.shade700),
                    label: Text("Log Out",
                        style: GoogleFonts.poppins(
                            color: Colors.red.shade700,
                            fontWeight: FontWeight.bold,
                            fontSize: 16)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.red.shade200, width: 1.5),
                      backgroundColor: Colors.red.shade50,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),

                // APP VERSION FOOTER
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      "AgriYukt Version 1.0.0",
                      style: GoogleFonts.poppins(
                          color: Colors.grey.shade400,
                          fontSize: 11,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- UI BUILDER HELPERS ---

  Widget _buildMenuGroup(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        children: children,
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        borderRadius: BorderRadius.circular(20), // Matches group radius
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (iconColor ?? _buyerColor).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor ?? _buyerColor, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Padding(
      padding:
          const EdgeInsets.only(left: 60, right: 16), // Indents past the icon
      child: Divider(height: 1, thickness: 1, color: Colors.grey.shade100),
    );
  }
}
