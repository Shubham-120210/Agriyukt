import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';

// ✅ Internal Feature Imports
import 'package:agriyukt_app/features/buyer/screens/buyer_orders_screen.dart';
import 'package:agriyukt_app/features/buyer/screens/buyer_order_detail_screen.dart';

class BuyerNotificationScreen extends StatefulWidget {
  const BuyerNotificationScreen({super.key});

  @override
  State<BuyerNotificationScreen> createState() =>
      _BuyerNotificationScreenState();
}

class _BuyerNotificationScreenState extends State<BuyerNotificationScreen>
    with WidgetsBindingObserver {
  final _supabase = Supabase.instance.client;
  Timer? _staleDataTimer;

  // ✅ ANTI-POP FIX: Cache the stream so it doesn't recreate during lifecycle changes
  late final Stream<List<Map<String, dynamic>>> _notificationStream;

  // Signature Buyer Theme Constants
  static const Color _primaryBlue = Color(0xFF1565C0);
  static const Color _surfaceBg = Color(0xFFF4F6F8);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 1. Initialize Stream EXACTLY ONCE to prevent UI flickering
    final userId = _supabase.auth.currentUser?.id;
    if (userId != null) {
      _notificationStream = _supabase
          .from('notifications')
          .stream(primaryKey: ['id'])
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(150); // High limit prevents pagination traps
    } else {
      _notificationStream = const Stream.empty();
    }

    // 2. Refresh headers every minute to keep "Today" / "Yesterday" mathematically accurate
    _staleDataTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _staleDataTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
    }
  }

  // =======================================================================
  // 🚀 120fps FLAT-LIST ENGINE: Flattens groups into a 1D array to prevent nested scrolling jank
  // =======================================================================
  List<dynamic> _flattenNotifications(List<Map<String, dynamic>> notifs) {
    List<dynamic> flatList = [];
    final now = DateTime.now();
    String? currentGroup;

    for (var notif in notifs) {
      final dateStr = notif['created_at'];
      if (dateStr == null) continue;
      final date = DateTime.parse(dateStr).toLocal();

      String groupKey;
      if (date.year == now.year &&
          date.month == now.month &&
          date.day == now.day) {
        groupKey = "Today";
      } else if (date.year == now.year &&
          date.month == now.month &&
          date.day == now.day - 1) {
        groupKey = "Yesterday";
      } else {
        groupKey = "Earlier";
      }

      // Inject header if the group changes
      if (groupKey != currentGroup) {
        flatList.add(groupKey);
        currentGroup = groupKey;
      }

      flatList.add(notif);
    }
    return flatList;
  }

  // =======================================================================
  // 🧭 INSTANT SNAP-ROUTING ENGINE (Zero Slide, Zero Fade)
  // =======================================================================
  void _handleTap(Map<String, dynamic> notif) async {
    HapticFeedback.selectionClick();
    final String id = notif['id'].toString();
    final meta = notif['metadata'] ?? {};
    final String? orderId = meta['order_id']?.toString();

    // 1. Mark as read instantly in background
    if (notif['is_read'] == false) {
      setState(() => notif['is_read'] = true);
      _supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('id', id)
          .catchError((_) {});
    }

    if (!mounted || orderId == null) return;

    try {
      // 2. Fetch absolute latest status directly from DB to prevent routing errors
      final orderData = await _supabase
          .from('orders')
          .select('status')
          .eq('id', orderId)
          .maybeSingle();
      if (!mounted) return;

      if (orderData == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Order details are no longer available.",
              style: GoogleFonts.poppins()),
          backgroundColor: Colors.red.shade800,
          behavior: SnackBarBehavior.floating,
        ));
        return;
      }

      final status =
          (orderData['status'] ?? '').toString().toLowerCase().trim();

      final activeStates = [
        'accepted',
        'confirmed',
        'packed',
        'shipped',
        'in transit',
        'out for delivery',
        'processing'
      ];
      final historyStates = ['delivered', 'completed', 'rejected', 'cancelled'];

      Widget targetScreen;

      // 3. APPLY SPECIFIC ROUTING LOGIC
      if (activeStates.contains(status)) {
        // ✅ ACCEPTED/ACTIVE: Prepare to jump straight into the details
        targetScreen = BuyerOrderDetailScreen(orderId: orderId);
      } else {
        // ✅ PENDING or REJECTED/COMPLETED: Prepare to jump to the Glowing Crop Card!
        int targetTab = historyStates.contains(status) ? 2 : 0;
        targetScreen = BuyerOrdersScreen(
            initialIndex: targetTab, highlightOrderId: orderId);
      }

      // 4. ✅ INSTANT SNAP: TransitionDuration is zero! No sliding, no fading!
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => targetScreen,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
      );
    } catch (e) {
      debugPrint("Navigation Error: $e");
    }
  }

  Future<void> _markAllRead(String uid) async {
    HapticFeedback.mediumImpact();
    await _supabase
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', uid)
        .eq('is_read', false);
  }

  @override
  Widget build(BuildContext context) {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      return const Scaffold(
          body: Center(child: Text("Authentication Required")));
    }

    return Scaffold(
      backgroundColor: _surfaceBg,
      appBar: AppBar(
        title: Text("Notifications",
            style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20)),
        backgroundColor: _primaryBlue,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all_rounded, color: Colors.white),
            onPressed: () => _markAllRead(userId),
            tooltip: "Mark all read",
          )
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream:
            _notificationStream, // Uses cached stream to prevent rebuild pops
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return _buildSkeletonLoader();
          }

          final flatList = _flattenNotifications(snapshot.data ?? []);
          if (flatList.isEmpty) return _buildEmptyState();

          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
                16, 8, 16, MediaQuery.of(context).padding.bottom + 40),
            itemCount: flatList.length,
            itemBuilder: (context, index) {
              final item = flatList[index];

              // Render Header
              if (item is String) {
                return Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 12, top: 24),
                  child: Text(item,
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade500,
                          fontSize: 13,
                          letterSpacing: 0.5)),
                );
              }

              // Render Notification Tile
              final notif = item as Map<String, dynamic>;
              return _NotificationTile(
                key: ValueKey(notif['id']
                    .toString()), // Strict key prevents list-swap jank
                notif: notif,
                onTap: () => _handleTap(notif),
                onDelete: () {
                  HapticFeedback.vibrate();
                  _supabase
                      .from('notifications')
                      .delete()
                      .eq('id', notif['id']);
                },
                primaryColor: _primaryBlue,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildSkeletonLoader() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 8,
      itemBuilder: (_, __) => Container(
        height: 88,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade200)),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.04), blurRadius: 16)
                ]),
            child: Icon(Icons.notifications_off_outlined,
                size: 50, color: _primaryBlue.withOpacity(0.5)),
          ),
          const SizedBox(height: 20),
          Text("No notifications yet",
              style: GoogleFonts.poppins(
                  color: Colors.black87,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text("We'll notify you when your orders update.",
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  color: Colors.grey.shade500, fontSize: 13)),
        ],
      ),
    );
  }
}

// ============================================================================
// ✅ ISOLATED & BOUNDED TILE: Uses RepaintBoundary for silky 120fps scrolling
// ============================================================================
class _NotificationTile extends StatelessWidget {
  final Map<String, dynamic> notif;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final Color primaryColor;

  const _NotificationTile({
    super.key,
    required this.notif,
    required this.onTap,
    required this.onDelete,
    required this.primaryColor,
  });

  @override
  Widget build(BuildContext context) {
    final bool isRead = notif['is_read'] ?? false;
    final meta = notif['metadata'] ?? {};
    final String? imageUrl = meta['image'];
    final DateTime createdAt = DateTime.parse(notif['created_at']).toLocal();

    return RepaintBoundary(
      child: Dismissible(
        key: Key("dismiss_${notif['id']}"),
        direction: DismissDirection.endToStart,
        onDismissed: (_) => onDelete(),
        background: Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
              color: Colors.red.shade500,
              borderRadius: BorderRadius.circular(20)),
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 25),
          child: const Icon(Icons.delete_sweep_rounded,
              color: Colors.white, size: 28),
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: isRead ? Colors.white : const Color(0xFFF0F7FF),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: isRead
                    ? Colors.grey.shade200
                    : primaryColor.withOpacity(0.3),
                width: 1),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 15,
                  offset: const Offset(0, 5))
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStrictImage(imageUrl, isRead),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RichText(
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            text: TextSpan(
                              style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  color: Colors.black87,
                                  height: 1.4),
                              children: [
                                TextSpan(
                                    text: "${notif['title']}  ",
                                    style: TextStyle(
                                        fontWeight: isRead
                                            ? FontWeight.w600
                                            : FontWeight.bold)),
                                TextSpan(
                                    text: notif['body'] ?? '',
                                    style:
                                        TextStyle(color: Colors.grey.shade700)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(DateFormat('hh:mm a').format(createdAt),
                                  style: GoogleFonts.jetBrainsMono(
                                      fontSize: 11,
                                      color: Colors.grey.shade500,
                                      fontWeight: FontWeight.w500)),
                              if (!isRead)
                                Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                        color: primaryColor,
                                        shape: BoxShape.circle)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ✅ STRICT IMAGE GEOMETRY: Ensures layout never collapses during image decodes
  Widget _buildStrictImage(String? url, bool isRead) {
    return SizedBox(
      height: 56,
      width: 56,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
          color: isRead ? Colors.grey.shade50 : primaryColor.withOpacity(0.05),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: (url != null && url.isNotEmpty)
              ? CachedNetworkImage(
                  imageUrl: url.startsWith('http')
                      ? url
                      : Supabase.instance.client.storage
                          .from('crop_images')
                          .getPublicUrl(url),
                  fit: BoxFit.cover,
                  memCacheWidth:
                      150, // Micro-pop fix: Decodes image small in background
                  fadeInDuration: const Duration(milliseconds: 150),
                  placeholder: (context, url) =>
                      Container(color: Colors.transparent),
                  errorWidget: (context, url, error) => Icon(
                      Icons.notifications_active_outlined,
                      color: isRead ? Colors.grey.shade400 : primaryColor),
                )
              : Icon(Icons.notifications_active_outlined,
                  color: isRead ? Colors.grey.shade400 : primaryColor),
        ),
      ),
    );
  }
}
