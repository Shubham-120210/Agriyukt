import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

// ✅ Screen Imports
import 'package:agriyukt_app/features/inspector/screens/add_farmer_screen.dart';
import 'package:agriyukt_app/features/inspector/screens/edit_farmer_screen.dart';
import 'package:agriyukt_app/features/inspector/screens/manage_crops/inspector_farmer_inventory_screen.dart';
import 'package:agriyukt_app/features/farmer/screens/add_crop_screen.dart'; // 🚀 FIXED IMPORT

class InspectorFarmersTab extends StatefulWidget {
  const InspectorFarmersTab({super.key});

  @override
  State<InspectorFarmersTab> createState() => _InspectorFarmersTabState();
}

class _InspectorFarmersTabState extends State<InspectorFarmersTab> {
  final _client = Supabase.instance.client;

  // 🛡️ Search & Focus Management
  String _searchQuery = "";
  final _searchCtrl = TextEditingController();
  final _searchFocusNode = FocusNode();
  Timer? _debounce;
  bool _isFetching = false;

  // State
  List<Map<String, dynamic>> _farmers = [];
  bool _isLoading = true;
  String? _errorMsg;

  // 🎨 Theme Colors
  final Color _primaryPurple = const Color(0xFF4A148C);
  final Color _accentPurple = const Color(0xFF7E57C2);
  final Color _bgWhite = const Color(0xFFF8F9FA);

  @override
  void initState() {
    super.initState();
    _fetchFarmers();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // --- 1. FULL DATA FETCH (FIXED) ---
  Future<void> _fetchFarmers({bool silent = false}) async {
    if (_isFetching) return;
    _isFetching = true;

    // Prevent double-spinner on pull-to-refresh
    if (!silent && mounted && _farmers.isEmpty) {
      setState(() {
        _isLoading = true;
        _errorMsg = null;
      });
    }

    try {
      final user = _client.auth.currentUser;
      if (user == null) throw "Authentication error. Please log in again.";

      final response = await _client
          .from('profiles')
          .select()
          .eq('inspector_id', user.id)
          .order('created_at', ascending: false)
          .limit(1000);

      final List<dynamic> rawData = response as List<dynamic>;

      final parsedFarmers = rawData
          .map((e) => e as Map<String, dynamic>)
          .where((f) =>
              (f['role']?.toString().toLowerCase().trim() ?? '') == 'farmer')
          .toList();

      if (mounted) {
        setState(() {
          _farmers = parsedFarmers;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("❌ Directory Fetch Error: $e");
      if (mounted && _farmers.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMsg = "Unable to load directory. Please check your connection.";
        });
      }
    } finally {
      _isFetching = false;
    }
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _searchQuery = query;
        });
      }
    });
  }

  // --- 2. SAFE UN-ASSIGNMENT ---
  Future<void> _deleteFarmer(String farmerId, String farmerName) async {
    HapticFeedback.mediumImpact();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Remove Farmer?",
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Text(
            "Are you sure you want to remove $farmerName from your directory? This will un-assign them from you.",
            style:
                GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade700)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text("CANCEL",
                style: GoogleFonts.poppins(
                    color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: Text("REMOVE",
                style: GoogleFonts.poppins(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final int index = _farmers.indexWhere((f) => f['id'] == farmerId);
    if (index == -1) return;

    final Map<String, dynamic> deletedFarmer = _farmers[index];
    setState(() => _farmers.removeAt(index));

    try {
      await _client
          .from('profiles')
          .update({'inspector_id': null}).eq('id', farmerId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Farmer removed successfully",
                style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
            backgroundColor: Colors.green.shade700,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            behavior: SnackBarBehavior.floating));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _farmers.insert(index, deletedFarmer));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Failed to remove farmer. Please try again.",
                style: GoogleFonts.poppins()),
            backgroundColor: Colors.red.shade700));
      }
    }
  }

  // --- 3. CLICKABLE PHONE ACTION ---
  Future<void> _makePhoneCall(String phoneNumber) async {
    if (phoneNumber.isEmpty || phoneNumber == 'Phone N/A') return;

    // Clean string (remove spaces, dashes)
    final cleanPhone = phoneNumber.replaceAll(RegExp(r'[^0-9+]'), '');
    final Uri url = Uri.parse('tel:$cleanPhone');

    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      } else {
        throw 'Could not launch $url';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                "Unable to open dialer. Please check device permissions.",
                style: GoogleFonts.poppins()),
            backgroundColor: Colors.red.shade600));
      }
    }
  }

  Color _getAvatarColor(String name) {
    if (name.isEmpty) return _primaryPurple;
    final colors = [
      Colors.blue.shade600,
      Colors.teal.shade600,
      Colors.orange.shade600,
      Colors.pink.shade600,
      Colors.indigo.shade600,
      Colors.deepOrange.shade600
    ];
    return colors[name.codeUnitAt(0) % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final filteredFarmers = _farmers.where((f) {
      final name =
          "${f['first_name'] ?? ''} ${f['last_name'] ?? ''}".toLowerCase();
      final phone = (f['phone'] ?? '').toString().toLowerCase();
      final district = (f['district'] ?? '').toString().toLowerCase();
      final query = _searchQuery.toLowerCase().trim();

      return name.contains(query) ||
          phone.contains(query) ||
          district.contains(query);
    }).toList();

    return GestureDetector(
      onTap: () => _searchFocusNode.unfocus(),
      child: Scaffold(
        backgroundColor: _bgWhite,
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            await Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AddFarmerScreen()));
            if (mounted) _fetchFarmers(silent: true);
          },
          backgroundColor: _primaryPurple,
          elevation: 6,
          icon:
              const Icon(Icons.person_add_alt_1, color: Colors.white, size: 20),
          label: Text("ADD FARMER",
              style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  fontSize: 13)),
        ),
        body: RefreshIndicator(
          onRefresh: () => _fetchFarmers(silent: true),
          color: _primaryPurple,
          backgroundColor: Colors.white,
          edgeOffset: MediaQuery.of(context).padding.top + 20,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics()),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              // 1. The Header Details
              SliverToBoxAdapter(
                child: _buildDashboardHeader(filteredFarmers.length),
              ),

              // 2. 🚀 THE PRODUCTION PINNED SEARCH BAR
              SliverPersistentHeader(
                pinned: true,
                floating: true,
                delegate: _StickySearchBarDelegate(
                  child: Container(
                    color: _bgWhite,
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                    child: _buildSearchBar(),
                  ),
                ),
              ),

              if (_isLoading)
                SliverFillRemaining(
                    child: Center(
                        child:
                            CircularProgressIndicator(color: _primaryPurple)))
              else if (_errorMsg != null)
                SliverFillRemaining(child: _buildErrorState())
              else if (filteredFarmers.isEmpty)
                SliverFillRemaining(child: _buildEmptyState())
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) =>
                          _buildAnimatedFarmerCard(filteredFarmers[i], i),
                      childCount: filteredFarmers.length,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDashboardHeader(int count) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 20,
        left: 24,
        right: 24,
        bottom: 32,
      ),
      margin: const EdgeInsets.only(bottom: 24),
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_primaryPurple, _accentPurple],
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(40)),
        boxShadow: [
          BoxShadow(
              color: _primaryPurple.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 10))
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            right: -30,
            top: -20,
            child: Icon(Icons.supervised_user_circle,
                size: 160, color: Colors.white.withOpacity(0.06)),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Directory",
                      style: GoogleFonts.poppins(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          height: 1.2,
                          letterSpacing: -0.5)),
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                            height: 6,
                            width: 6,
                            decoration: const BoxDecoration(
                                color: Colors.greenAccent,
                                shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Text("$count Active Farmers",
                            style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: Colors.white,
                                fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () => _fetchFarmers(silent: false),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.sync, color: Colors.white, size: 22),
                ),
              )
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, 8))
        ],
      ),
      child: Center(
        child: TextField(
          controller: _searchCtrl,
          focusNode: _searchFocusNode,
          onChanged: _onSearchChanged,
          style: GoogleFonts.poppins(
              fontSize: 14, color: Colors.black87, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: "Search name, phone, or location...",
            hintStyle: GoogleFonts.poppins(
                color: Colors.grey.shade400,
                fontSize: 14,
                fontWeight: FontWeight.w400),
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 16, right: 8),
              child: Icon(Icons.search, color: _primaryPurple, size: 22),
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 40),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.cancel,
                        size: 18, color: Colors.grey.shade400),
                    onPressed: () {
                      _searchCtrl.clear();
                      _onSearchChanged("");
                      _searchFocusNode.unfocus();
                    })
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedFarmerCard(Map<String, dynamic> farmer, int index) {
    return TweenAnimationBuilder<double>(
      key: ValueKey("anim_${farmer['id']}"),
      tween: Tween(begin: 0.0, end: 1.0),
      duration:
          Duration(milliseconds: 400 + (index * 50).clamp(0, 500).toInt()),
      curve: Curves.easeOutQuart,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 30 * (1 - value)),
          child: Opacity(opacity: value, child: child),
        );
      },
      child: _buildFarmerCard(farmer),
    );
  }

  Widget _buildFarmerCard(Map<String, dynamic> farmer) {
    final String safeId = farmer['id']?.toString() ?? '';
    final String firstName =
        farmer['first_name']?.toString().trim() ?? 'Unknown';
    final String lastName = farmer['last_name']?.toString().trim() ?? '';
    final name = "$firstName $lastName".trim();

    final location = farmer['district']?.toString().isNotEmpty == true
        ? farmer['district']
        : 'Location N/A';
    final phone = farmer['phone']?.toString().isNotEmpty == true
        ? farmer['phone']
        : 'Phone N/A';

    final bool isVerified =
        (farmer['verification_status']?.toString().toLowerCase() == 'verified');
    final avatarColor = _getAvatarColor(name);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => InspectorFarmerInventoryScreen(
                            farmerId: safeId, farmerName: name)))
                .then((_) => _fetchFarmers(silent: true));
          },
          highlightColor: _primaryPurple.withOpacity(0.05),
          splashColor: _primaryPurple.withOpacity(0.1),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade200, width: 1.2),
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // 👤 Avatar
                Container(
                  height: 56,
                  width: 56,
                  decoration: BoxDecoration(
                    color: avatarColor.withOpacity(0.15),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: avatarColor.withOpacity(0.3), width: 1.5),
                  ),
                  child: Center(
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : "?",
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w700,
                          color: avatarColor,
                          fontSize: 22),
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // 📄 Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                              child: Text(name,
                                  style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                      color: Colors.black87),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis)),
                          const SizedBox(width: 6),
                          if (isVerified)
                            const Icon(Icons.verified,
                                color: Colors.blue, size: 18)
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                  color: Colors.orange.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                      color: Colors.orange.shade200)),
                              child: Text("Pending",
                                  style: GoogleFonts.poppins(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.orange.shade800)),
                            )
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.location_on,
                              size: 14, color: Colors.grey.shade400),
                          const SizedBox(width: 4),
                          Expanded(
                              child: Text(location,
                                  style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                      fontWeight: FontWeight.w500),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // 🚀 Clickable Phone Number
                      GestureDetector(
                        onTap: () => _makePhoneCall(phone.toString()),
                        child: Row(
                          children: [
                            Icon(Icons.phone, size: 14, color: _primaryPurple),
                            const SizedBox(width: 4),
                            Expanded(
                                child: Text(phone,
                                    style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        color: _primaryPurple,
                                        fontWeight: FontWeight.w600),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // ⚙️ Actions
                Row(
                  children: [
                    Icon(Icons.chevron_right_rounded,
                        color: Colors.grey.shade300, size: 28),
                    Container(
                        height: 30,
                        width: 1.2,
                        color: Colors.grey.shade200,
                        margin: const EdgeInsets.symmetric(horizontal: 4)),
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert, color: Colors.grey.shade600),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      color: Colors.white,
                      elevation: 8,
                      offset: const Offset(0, 40),
                      onSelected: (value) async {
                        if (value == 'add') {
                          Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => AddCropScreen(
                                          farmerId: safeId))) // 🚀 FIXED CALL
                              .then((_) => _fetchFarmers(silent: true));
                        } else if (value == 'edit') {
                          bool? updated = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      EditFarmerScreen(farmer: farmer)));
                          if (updated == true && mounted)
                            _fetchFarmers(silent: true);
                        } else if (value == 'delete') {
                          _deleteFarmer(safeId, name);
                        }
                      },
                      itemBuilder: (context) => <PopupMenuEntry<String>>[
                        _buildPopupItem('add', 'Add New Crop',
                            Icons.add_box_rounded, Colors.green.shade600),
                        const PopupMenuDivider(),
                        _buildPopupItem('edit', 'Edit Profile',
                            Icons.edit_rounded, Colors.orange.shade600),
                        _buildPopupItem('delete', 'Remove Farmer',
                            Icons.delete_rounded, Colors.red.shade600),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PopupMenuItem<String> _buildPopupItem(
      String val, String label, IconData icon, Color color) {
    return PopupMenuItem(
      value: val,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Text(label,
              style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87)),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
              color: _primaryPurple.withOpacity(0.05), shape: BoxShape.circle),
          child: Icon(Icons.person_search_rounded,
              size: 70, color: _primaryPurple.withOpacity(0.5)),
        ),
        const SizedBox(height: 20),
        Text(
            _searchQuery.isEmpty
                ? "No farmers registered yet."
                : "No matches found.",
            style: GoogleFonts.poppins(
                color: Colors.grey.shade800,
                fontSize: 18,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(
            _searchQuery.isEmpty
                ? "Tap 'Add Farmer' below to start building\nyour directory."
                : "Try adjusting your search query.",
            style: GoogleFonts.poppins(
                color: Colors.grey.shade500, fontSize: 14, height: 1.5),
            textAlign: TextAlign.center),
      ],
    );
  }

  Widget _buildErrorState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.wifi_off_rounded, size: 60, color: Colors.red.shade300),
        const SizedBox(height: 16),
        Text("Connection Error",
            style: GoogleFonts.poppins(
                color: Colors.red.shade800,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(_errorMsg ?? "Something went wrong.",
              style: GoogleFonts.poppins(
                  color: Colors.grey.shade600, fontSize: 13),
              textAlign: TextAlign.center),
        ),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: () => _fetchFarmers(silent: false),
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: _primaryPurple,
              side: BorderSide(color: _primaryPurple.withOpacity(0.5))),
          icon: const Icon(Icons.refresh, size: 18),
          label: Text("Try Again",
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        )
      ],
    );
  }
}

// 🚀 REQUIRED DELEGATE FOR PINNED SEARCH BAR
class _StickySearchBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  _StickySearchBarDelegate({required this.child});

  @override
  double get minExtent => 72.0;
  @override
  double get maxExtent => 72.0;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return child;
  }

  @override
  bool shouldRebuild(_StickySearchBarDelegate oldDelegate) {
    return oldDelegate.child != child;
  }
}
