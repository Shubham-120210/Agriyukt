import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

// ✅ CORRECT IMPORT: Points to the Inspector Order Screen
import 'package:agriyukt_app/features/inspector/screens/inspector_order_detail_screen.dart';

class InspectorNotificationScreen extends StatefulWidget {
  const InspectorNotificationScreen({super.key});

  @override
  State<InspectorNotificationScreen> createState() =>
      _InspectorNotificationScreenState();
}

class _InspectorNotificationScreenState
    extends State<InspectorNotificationScreen> {
  final _supabase = Supabase.instance.client;

  // ✅ Theme: Deep Purple (Inspector Identity)
  final Color _primaryColor = const Color(0xFF512DA8);
  final Color _bgSurface = const Color(0xFFF4F6F8);

  final Set<String> _hiddenItems = {};

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 2), _markAllAsRead);
  }

  // ---------------------------------------------------------------------------
  // ⚡ LOGIC ENGINE
  // ---------------------------------------------------------------------------

  Future<void> _markAllAsRead() async {
    if (!mounted) return;
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await _supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', userId)
          .eq('is_read', false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("All notifications marked as read",
                style: GoogleFonts.poppins()),
            backgroundColor: Colors.grey.shade800,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _deleteNotification(String id) async {
    try {
      await _supabase.from('notifications').delete().eq('id', id);
    } catch (_) {}
  }

  Future<void> _handleTap(Map<String, dynamic> notif) async {
    final String id = notif['id'].toString();
    final meta = notif['metadata'] ?? {};
    final String? orderId = meta['order_id']?.toString();

    if (notif['is_read'] == false) {
      try {
        await _supabase
            .from('notifications')
            .update({'is_read': true}).eq('id', id);
      } catch (_) {}
    }

    if (orderId != null) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => Center(
            child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: const CircularProgressIndicator(color: Color(0xFF512DA8)),
        )),
      );

      try {
        final orderData = await _supabase.from('orders').select('''
              *,
              buyer:profiles!orders_buyer_id_fkey(id, first_name, last_name, phone, district, state, latitude, longitude),
              farmer:profiles!orders_farmer_id_fkey(id, first_name, last_name, phone, district, state, latitude, longitude),
              crop:crops!orders_crop_id_fkey(image_url, crop_name, unit, variety, grade, harvest_date, price, description)
            ''').eq('id', orderId).single();

        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => InspectorOrderDetailScreen(order: orderData),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text("Could not load details. Order may be deleted.",
                  style: GoogleFonts.poppins()),
              backgroundColor: Colors.red));
        }
      }
    }
  }

  String _formatTime(String? iso) {
    if (iso == null) return "Now";
    try {
      final date = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final diff = now.difference(date);
      if (diff.inMinutes < 1) return "Just now";
      if (diff.inMinutes < 60) return "${diff.inMinutes}m ago";
      if (diff.inHours < 24) return "${diff.inHours}h ago";
      if (diff.inDays == 1) return "Yesterday";
      return DateFormat('dd MMM').format(date);
    } catch (_) {
      return "Recent";
    }
  }

  // ---------------------------------------------------------------------------
  // 🖥️ UI BUILD
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      return const Scaffold(body: Center(child: Text("Login Required")));
    }

    return Scaffold(
      backgroundColor: _bgSurface,
      appBar: AppBar(
        title: Text("Alerts & Activity",
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontSize: 20)),
        backgroundColor: _primaryColor,
        elevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            onPressed: _markAllAsRead,
            icon: const Icon(Icons.done_all_rounded, color: Colors.white),
            tooltip: "Mark all as read",
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _supabase
            .from('notifications')
            .stream(primaryKey: ['id'])
            .eq('user_id', userId)
            .order('created_at', ascending: false)
            .limit(50),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
                child: CircularProgressIndicator(color: _primaryColor));
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: _primaryColor.withOpacity(0.05),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.notifications_paused_outlined,
                        size: 60, color: _primaryColor.withOpacity(0.5)),
                  ),
                  const SizedBox(height: 24),
                  Text("All caught up!",
                      style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87)),
                  const SizedBox(height: 8),
                  Text("No new alerts or updates for you.",
                      style: GoogleFonts.poppins(color: Colors.grey)),
                ],
              ),
            );
          }

          final rawList = snapshot.data!;
          final notifications = rawList
              .where((n) => !_hiddenItems.contains(n['id'].toString()))
              .toList();

          final unread =
              notifications.where((n) => n['is_read'] == false).toList();
          final read =
              notifications.where((n) => n['is_read'] == true).toList();

          if (notifications.isEmpty) return const SizedBox.shrink();

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              if (unread.isNotEmpty) ...[
                _buildHeader("New"),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _buildAnimItem(unread[index]),
                    childCount: unread.length,
                  ),
                ),
              ],
              if (read.isNotEmpty) ...[
                _buildHeader("Earlier"),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _buildAnimItem(read[index]),
                    childCount: read.length,
                  ),
                ),
              ],
              const SliverPadding(padding: EdgeInsets.only(bottom: 40)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(String title) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
        child: Row(
          children: [
            Text(title,
                style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade600,
                    letterSpacing: 1.0)),
            const SizedBox(width: 8),
            Expanded(child: Divider(color: Colors.grey.shade300)),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimItem(Map<String, dynamic> notif) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Dismissible(
        key: Key(notif['id'].toString()),
        direction: DismissDirection.endToStart,
        onDismissed: (direction) {
          final String nId = notif['id'].toString();
          setState(() => _hiddenItems.add(nId));
          _deleteNotification(nId);
        },
        background: Container(
          decoration: BoxDecoration(
            color: Colors.red.shade400,
            borderRadius: BorderRadius.circular(16),
          ),
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 24),
          child: const Icon(Icons.delete_outline, color: Colors.white),
        ),
        child: notif['type'] == 'money'
            ? _SmartMoneyCard(
                notif: notif,
                supabase: _supabase,
                onTap: () => _handleTap(notif),
                timeFormatter: _formatTime)
            : _buildStandardCard(notif),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 📝 STANDARD CARD UI (Orders, Alerts, System)
  // ---------------------------------------------------------------------------
  Widget _buildStandardCard(Map<String, dynamic> notif) {
    final bool isRead = notif['is_read'] ?? false;
    final meta = notif['metadata'] ?? {};
    final String type = notif['type'] ?? 'system';

    final String title = notif['title'] ?? 'Notification';
    final String body = notif['body'] ?? '';
    final String? status = meta['status']?.toString();

    IconData iconData;
    Color iconColor;
    Color bgIconColor;
    Color borderColor = Colors.transparent;

    if (type == 'alert' || title.toLowerCase().contains('rejected')) {
      iconData = Icons.warning_rounded;
      iconColor = Colors.red;
      bgIconColor = Colors.red.shade50;
      borderColor = isRead ? Colors.transparent : Colors.red.shade100;
    } else if (type == 'order_update' || type == 'order') {
      iconData = Icons.local_shipping_rounded;
      iconColor = _primaryColor;
      bgIconColor = _primaryColor.withOpacity(0.1);
      borderColor =
          isRead ? Colors.transparent : _primaryColor.withOpacity(0.2);
    } else if (title.toLowerCase().contains('verified')) {
      iconData = Icons.verified_user_rounded;
      iconColor = Colors.teal;
      bgIconColor = Colors.teal.shade50;
    } else {
      iconData = Icons.notifications_active_rounded;
      iconColor = Colors.grey.shade700;
      bgIconColor = Colors.grey.shade100;
    }

    return InkWell(
      onTap: () => _handleTap(notif),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: isRead ? Colors.grey.shade200 : borderColor,
              width: isRead ? 1 : 1.5),
          boxShadow: [
            BoxShadow(
                color: isRead
                    ? Colors.black.withOpacity(0.02)
                    : iconColor.withOpacity(0.08),
                blurRadius: 8,
                offset: const Offset(0, 3))
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Container(
                  height: 48,
                  width: 48,
                  decoration: BoxDecoration(
                      color: bgIconColor,
                      borderRadius: BorderRadius.circular(14)),
                  child: Icon(iconData, color: iconColor, size: 24),
                ),
                if (!isRead)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                          color: Colors.red,
                          border: Border.all(color: Colors.white, width: 2),
                          shape: BoxShape.circle),
                    ),
                  )
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                                fontWeight:
                                    isRead ? FontWeight.w600 : FontWeight.bold,
                                fontSize: 15,
                                color: Colors.black87)),
                      ),
                      const SizedBox(width: 8),
                      Text(_formatTime(notif['created_at']),
                          style: GoogleFonts.poppins(
                              fontSize: 11, color: Colors.grey.shade400)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                          fontSize: 13,
                          color: isRead
                              ? Colors.grey.shade600
                              : Colors.grey.shade800,
                          height: 1.4)),
                  if (status != null && status.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text("Status: ${status.toUpperCase()}",
                          style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade700)),
                    ),
                  ]
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 💰 STATEFUL SMART MONEY CARD (Full Names Logic)
// ============================================================================
class _SmartMoneyCard extends StatefulWidget {
  final Map<String, dynamic> notif;
  final VoidCallback onTap;
  final SupabaseClient supabase;
  final String Function(String?) timeFormatter;

  const _SmartMoneyCard({
    required this.notif,
    required this.onTap,
    required this.supabase,
    required this.timeFormatter,
  });

  @override
  State<_SmartMoneyCard> createState() => _SmartMoneyCardState();
}

class _SmartMoneyCardState extends State<_SmartMoneyCard> {
  String? buyerName;
  String? farmerName;

  @override
  void initState() {
    super.initState();
    _resolveNames();
  }

  // ✅ Helper to construct FULL name cleanly
  String _combineName(String? first, String? last) {
    final f = (first ?? '').trim();
    final l = (last ?? '').trim();
    if (f.isEmpty && l.isEmpty) return "";
    if (l.isEmpty) return f;
    return "$f $l"; // Returns Full Name: "Ramesh Kumar"
  }

  Future<void> _resolveNames() async {
    final meta = widget.notif['metadata'] ?? {};

    // Attempt 1: Fetch directly from metadata if present
    final String? mBuyer =
        meta['buyer_name']?.toString() ?? meta['buyer_first_name']?.toString();
    final String? mFarmer = meta['farmer_name']?.toString() ??
        meta['farmer_first_name']?.toString();

    if (mBuyer != null &&
        mFarmer != null &&
        mBuyer.isNotEmpty &&
        mFarmer.isNotEmpty) {
      if (mounted) {
        setState(() {
          buyerName = mBuyer;
          farmerName = mFarmer;
        });
      }
      return;
    }

    // Attempt 2: Fetch missing names + LAST NAME silently from DB
    final orderId = meta['order_id']?.toString();
    if (orderId != null && orderId.isNotEmpty) {
      try {
        final data = await widget.supabase.from('orders').select('''
            buyer:profiles!orders_buyer_id_fkey(first_name, last_name),
            farmer:profiles!orders_farmer_id_fkey(first_name, last_name)
        ''').eq('id', orderId).single();

        if (mounted) {
          setState(() {
            if (data['buyer'] is Map) {
              buyerName = _combineName(
                  data['buyer']['first_name'], data['buyer']['last_name']);
            }
            if (data['farmer'] is Map) {
              farmerName = _combineName(
                  data['farmer']['first_name'], data['farmer']['last_name']);
            }
          });
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = widget.notif['metadata'] ?? {};
    final bool isRead = widget.notif['is_read'] ?? false;

    final rawAmount = meta['amount']?.toString() ?? '0';
    final num parsedAmount = num.tryParse(rawAmount) ?? 0;
    final String formattedAmount = NumberFormat('#,##0').format(parsedAmount);

    final String bName =
        (buyerName != null && buyerName!.isNotEmpty) ? buyerName! : "Buyer";
    final String fName =
        (farmerName != null && farmerName!.isNotEmpty) ? farmerName! : "Farmer";

    // ✅ EXACT REQUESTED SENTENCE: "₹X received from Buyer(Full Name) and credited to Farmer(Full Name)"
    final String titleText =
        "₹$formattedAmount received from $bName and credited to $fName.";

    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isRead ? Colors.white : Colors.green.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: isRead ? Colors.grey.shade200 : Colors.green.shade200,
              width: 1),
          boxShadow: [
            BoxShadow(
                color: Colors.green.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4))
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: isRead ? Colors.green.shade50 : Colors.white,
                      shape: BoxShape.circle),
                  child: const Icon(Icons.account_balance_wallet_rounded,
                      color: Colors.green, size: 26),
                ),
                if (!isRead)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                          color: Colors.red,
                          border: Border.all(
                              color:
                                  isRead ? Colors.white : Colors.green.shade50,
                              width: 2),
                          shape: BoxShape.circle),
                    ),
                  )
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // ✅ FULLY READABLE SENTENCE DISPLAY
                      Expanded(
                        child: Text(titleText,
                            style: GoogleFonts.poppins(
                                fontSize: 13,
                                color: Colors.black87,
                                fontWeight:
                                    isRead ? FontWeight.w500 : FontWeight.bold,
                                height: 1.4),
                            maxLines: 3,
                            softWrap: true,
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 8),
                      Text(widget.timeFormatter(widget.notif['created_at']),
                          style: GoogleFonts.poppins(
                              fontSize: 10, color: Colors.grey.shade500)),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // ✅ SUCCESS BADGE & AMOUNT
                  Row(
                    children: [
                      Text("₹$formattedAmount",
                          style: GoogleFonts.jetBrainsMono(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade800)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(6)),
                        child: const Text("PAYMENT SUCCESSFUL",
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
