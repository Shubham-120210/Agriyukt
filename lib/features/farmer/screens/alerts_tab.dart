import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

// ✅ LOCALIZATION & SERVICES
import 'package:agriyukt_app/features/farmer/farmer_translations.dart';
import 'package:agriyukt_app/core/providers/language_provider.dart';
import 'package:agriyukt_app/core/services/translation_service.dart';

// ✅ FEATURE IMPORTS
import 'package:agriyukt_app/features/farmer/screens/profile_tab.dart';
import 'package:agriyukt_app/features/common/screens/wallet_screen.dart';
import 'package:agriyukt_app/features/farmer/screens/farmer_order_detail_screen.dart';
import 'package:agriyukt_app/features/farmer/screens/orders_screen.dart';

class AlertsTab extends StatefulWidget {
  const AlertsTab({super.key});

  @override
  State<AlertsTab> createState() => _AlertsTabState();
}

class _AlertsTabState extends State<AlertsTab> with WidgetsBindingObserver {
  final _supabase = Supabase.instance.client;
  Timer? _staleDataTimer;
  late final Stream<List<Map<String, dynamic>>> _notificationStream;

  // ✅ CENTRALIZED OPTIMISTIC CACHE
  final Set<String> _optimisticReadIds = {};
  final Set<String> _optimisticDeletedIds = {};
  final Map<String, String> _translationCache = {};

  List<Map<String, dynamic>> _lastKnownGoodData = [];

  // Premium UI Theme Colors
  static const Color _primaryGreen = Color(0xFF1B5E20);
  static const Color _accentGreen = Color(0xFF4CAF50);
  static const Color _backgroundColor = Color(0xFFF8F9FA);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final userId = _supabase.auth.currentUser?.id;
    if (userId != null) {
      _notificationStream = _supabase
          .from('notifications')
          .stream(primaryKey: ['id'])
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(150);
    } else {
      _notificationStream = const Stream.empty();
    }

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

  String _text(String key) => FarmerText.get(context, key);

  Future<void> _markAllRead() async {
    HapticFeedback.mediumImpact();
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await _supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', userId)
          .eq('is_read', false);
      HapticFeedback.lightImpact();
    } catch (e) {
      debugPrint("Batch Read Error: $e");
    }
  }

  String _getTranslatedText(String id, String rawText, String langCode) {
    if (langCode == 'en' || rawText.isEmpty) return rawText;
    if (_translationCache.containsKey(id)) return _translationCache[id]!;

    TranslationService.toLocal(rawText, langCode).then((translated) {
      if (mounted && !_translationCache.containsKey(id)) {
        setState(() => _translationCache[id] = translated);
      }
    }).catchError((_) {});

    return rawText;
  }

  List<dynamic> _buildFlattenedList(List<Map<String, dynamic>> notifs) {
    if (notifs.isEmpty) return [];

    final now = DateTime.now();
    final List<dynamic> flattened = [];
    String? currentHeader;

    for (var notif in notifs) {
      if (_optimisticDeletedIds.contains(notif['id'].toString())) continue;

      final dateStr = notif['created_at'];
      if (dateStr == null) continue;

      final date = DateTime.parse(dateStr).toLocal();
      String groupKey;

      if (date.year == now.year &&
          date.month == now.month &&
          date.day == now.day) {
        groupKey = _text('today') == 'today' ? 'Today' : _text('today');
      } else if (date.year == now.year &&
          date.month == now.month &&
          date.day == now.day - 1) {
        groupKey = _text('yesterday') == 'yesterday'
            ? 'Yesterday'
            : _text('yesterday');
      } else {
        groupKey = _text('earlier') == 'earlier' ? 'Earlier' : _text('earlier');
      }

      if (groupKey != currentHeader) {
        flattened.add({'isHeader': true, 'title': groupKey});
        currentHeader = groupKey;
      }
      flattened.add({'isHeader': false, 'data': notif});
    }

    return flattened;
  }

  @override
  Widget build(BuildContext context) {
    final langCode =
        Provider.of<LanguageProvider>(context).appLocale.languageCode;
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      return Scaffold(body: Center(child: Text(_text('login_required'))));
    }

    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        title: Text(_text('notifications'),
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: 24,
                color: Colors.black87,
                letterSpacing: -0.5)),
        backgroundColor: _backgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Tooltip(
              message: "Mark all read",
              child: InkWell(
                onTap: _markAllRead,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _primaryGreen.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.done_all_rounded,
                      color: _primaryGreen, size: 22),
                ),
              ),
            ),
          )
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _notificationStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              _lastKnownGoodData.isEmpty) {
            return const _PremiumSkeletonLoader();
          }

          if (snapshot.hasData) {
            _lastKnownGoodData = snapshot.data!;
          }

          final flattenedItems = _buildFlattenedList(_lastKnownGoodData);

          if (flattenedItems.isEmpty) return _buildPremiumEmptyState();

          return ListView.builder(
            padding: EdgeInsets.fromLTRB(
                16, 8, 16, MediaQuery.of(context).padding.bottom + 40),
            itemCount: flattenedItems.length,
            physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics()),
            itemBuilder: (context, index) {
              final item = flattenedItems[index];

              if (item['isHeader'] == true) {
                return Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 16, top: 24),
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 16,
                        decoration: BoxDecoration(
                            color: _accentGreen,
                            borderRadius: BorderRadius.circular(4)),
                      ),
                      const SizedBox(width: 8),
                      Text(item['title'],
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                              fontSize: 15,
                              letterSpacing: 0.2)),
                    ],
                  ),
                );
              }

              final notif = item['data'];
              final String id = notif['id'].toString();
              final String type = notif['type'] ?? 'system';
              final bool isReadOverride =
                  _optimisticReadIds.contains(id) || (notif['is_read'] == true);

              String rawBody = notif['body'] ?? '';

              if (rawBody.isEmpty) {
                // ✅ PAYMENT LOGIC: Ultra-short, punchy text format
                if (type == 'money' || type == 'payment') {
                  final amount = notif['metadata']?['amount'] ??
                      notif['metadata']?['price'] ??
                      '0';
                  final fullName = notif['metadata']?['buyer_name'] ??
                      notif['metadata']?['person_name'] ??
                      'Buyer';
                  final firstName = fullName.toString().split(' ').first;

                  // 🚀 ULTRA-SHORT FORMAT
                  rawBody =
                      "₹$amount from $firstName. Bank transfer in 24-48h.";
                }
                // ✅ CROP LOGIC
                else if (notif['metadata']?['crop_name'] != null) {
                  rawBody =
                      "${notif['metadata']['qty']}kg ${notif['metadata']['crop_name']}";
                  if (notif['metadata']['price'] != null &&
                      notif['metadata']['price'] != '0') {
                    rawBody += " • ₹${notif['metadata']['price']}";
                  }
                }
              }

              return _PremiumNotificationTile(
                key: ValueKey(id),
                notif: notif,
                isReadOverride: isReadOverride,
                translatedBody: _getTranslatedText(id, rawBody, langCode),
                primaryColor: _primaryGreen,
                textHelper: _text,
                onTap: () async {
                  HapticFeedback.selectionClick();
                  if (!isReadOverride) {
                    setState(() => _optimisticReadIds.add(id));
                    _supabase
                        .from('notifications')
                        .update({'is_read': true})
                        .eq('id', id)
                        .catchError((_) {});
                  }
                },
                onDelete: () {
                  HapticFeedback.vibrate();
                  setState(() => _optimisticDeletedIds.add(id));
                  _supabase
                      .from('notifications')
                      .delete()
                      .eq('id', id)
                      .catchError((_) {
                    if (mounted) {
                      setState(() => _optimisticDeletedIds.remove(id));
                    }
                  });
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildPremiumEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: _primaryGreen.withOpacity(0.05),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.notifications_active_outlined,
                size: 64, color: _primaryGreen.withOpacity(0.4)),
          ),
          const SizedBox(height: 24),
          Text(_text('no_notifications'),
              style: GoogleFonts.poppins(
                  color: Colors.black87,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text("You're all caught up! Check back later.",
              style: GoogleFonts.poppins(
                  color: Colors.grey.shade500, fontSize: 14)),
        ],
      ),
    );
  }
}

// ============================================================================
// ✅ ANIMATED SKELETON LOADER
// ============================================================================
class _PremiumSkeletonLoader extends StatefulWidget {
  const _PremiumSkeletonLoader();

  @override
  State<_PremiumSkeletonLoader> createState() => _PremiumSkeletonLoaderState();
}

class _PremiumSkeletonLoaderState extends State<_PremiumSkeletonLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: 0.4 + (_controller.value * 0.6),
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: 8,
            itemBuilder: (_, __) => Container(
              height: 88,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(20)),
            ),
          ),
        );
      },
    );
  }
}

// ============================================================================
// ✅ PREMIUM STATEFUL TILE & DYNAMIC ROUTING ENGINE
// ============================================================================
class _PremiumNotificationTile extends StatefulWidget {
  final Map<String, dynamic> notif;
  final bool isReadOverride;
  final String translatedBody;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final Color primaryColor;
  final String Function(String) textHelper;

  const _PremiumNotificationTile({
    required super.key,
    required this.notif,
    required this.isReadOverride,
    required this.translatedBody,
    required this.onTap,
    required this.onDelete,
    required this.primaryColor,
    required this.textHelper,
  });

  @override
  State<_PremiumNotificationTile> createState() =>
      _PremiumNotificationTileState();
}

class _PremiumNotificationTileState extends State<_PremiumNotificationTile> {
  final _supabase = Supabase.instance.client;

  void _showRejectionInfoSheet(String title, String body) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.cancel_rounded,
                  color: Colors.red.shade600, size: 48),
            ),
            const SizedBox(height: 20),
            Text(title,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87)),
            const SizedBox(height: 12),
            Text(body,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 15, color: Colors.grey[600], height: 1.5)),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                    backgroundColor: widget.primaryColor,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16))),
                child: Text(
                  widget.textHelper('dismiss') == 'dismiss'
                      ? "Dismiss"
                      : widget.textHelper('dismiss'),
                  style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- 🚀 REAL-TIME ROUTING ENGINE ---
  void _handleNavigation() async {
    widget.onTap();

    final type = widget.notif['type'] ?? 'system';
    final meta = widget.notif['metadata'] ?? {};
    final String? orderId = meta['order_id']?.toString();
    final String notifStatus = (meta['status'] ?? '').toString().toLowerCase();

    if (notifStatus == 'rejected' || notifStatus == 'cancelled') {
      final title =
          widget.notif['title'] ?? meta['person_name'] ?? 'Order Cancelled';
      _showRejectionInfoSheet(title, widget.translatedBody);
      return;
    }

    if ((type == 'order' ||
            type == 'order_update' ||
            type == 'money' ||
            type == 'payment') &&
        orderId != null) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => Center(
            child: CircularProgressIndicator(color: widget.primaryColor)),
      );

      final orderData = await _supabase
          .from('orders')
          .select('status')
          .eq('id', orderId)
          .maybeSingle();

      if (mounted) Navigator.pop(context);

      if (orderData == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Order no longer exists.",
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ));
        }
        return;
      }

      final String currentStatus =
          (orderData['status'] ?? '').toString().toLowerCase();

      final activeStates = [
        'accepted',
        'confirmed',
        'packed',
        'shipped',
        'in transit',
        'out for delivery',
        'processing',
        'trip started',
        'paid'
      ];
      final historyStates = ['delivered', 'completed', 'rejected', 'cancelled'];

      Widget targetScreen;

      if (activeStates.contains(currentStatus)) {
        targetScreen = FarmerOrderDetailScreen(orderId: orderId);
      } else if (historyStates.contains(currentStatus)) {
        targetScreen = OrdersScreen(initialIndex: 2, highlightOrderId: orderId);
      } else {
        targetScreen = OrdersScreen(initialIndex: 0, highlightOrderId: orderId);
      }

      if (mounted) {
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => targetScreen,
            transitionDuration: const Duration(milliseconds: 250),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
          ),
        );
      }
    } else if (type == 'wallet') {
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => WalletScreen(themeColor: widget.primaryColor)));
    } else if (type == 'profile') {
      Navigator.push(
          context, MaterialPageRoute(builder: (_) => const ProfileTab()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final String type = widget.notif['type'] ?? 'system';
    final Map<String, dynamic> meta = widget.notif['metadata'] ?? {};
    final String? imageUrl = meta['image'];

    final String title = widget.notif['title'] ??
        meta['person_name'] ??
        (type == 'money' || type == 'payment' ? 'Payment' : 'Alert');

    String status = (meta['status'] ?? '').toString();
    if (status.isEmpty && (type == 'money' || type == 'payment'))
      status = 'Paid';
    if (status.isEmpty) status = "Alert";

    Color statusColor = Colors.orange.shade700;
    if (['accepted', 'shipped', 'confirmed', 'packed', 'active']
        .contains(status.toLowerCase())) statusColor = const Color(0xFF1565C0);
    if (['delivered', 'completed', 'history', 'paid']
        .contains(status.toLowerCase())) statusColor = widget.primaryColor;
    if (['rejected', 'cancelled'].contains(status.toLowerCase())) {
      statusColor = Colors.red.shade700;
    }

    IconData? typeIcon;
    if (type == 'money' || type == 'payment') {
      typeIcon = Icons.account_balance_wallet_rounded;
    }
    if (type == 'profile') typeIcon = Icons.person_rounded;

    final DateTime createdAt =
        DateTime.parse(widget.notif['created_at']).toLocal();

    return RepaintBoundary(
      child: Dismissible(
        key: Key(widget.notif['id'].toString()),
        direction: DismissDirection.endToStart,
        onDismissed: (_) => widget.onDelete(),
        background: Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
              color: Colors.red.shade500,
              borderRadius: BorderRadius.circular(20)),
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text("Delete",
                  style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14)),
              const SizedBox(width: 8),
              const Icon(Icons.delete_outline_rounded,
                  color: Colors.white, size: 24),
            ],
          ),
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color:
                widget.isReadOverride ? Colors.white : const Color(0xFFF3FAEE),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: widget.isReadOverride
                    ? Colors.grey.shade200
                    : widget.primaryColor.withOpacity(0.4),
                width: 1),
            boxShadow: [
              BoxShadow(
                  color: widget.isReadOverride
                      ? Colors.black.withOpacity(0.02)
                      : widget.primaryColor.withOpacity(0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4))
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _handleNavigation,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    typeIcon != null
                        ? _buildIconBox(typeIcon, statusColor)
                        : _buildStrictImage(imageUrl, widget.isReadOverride),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  style: GoogleFonts.poppins(
                                      fontSize: 15,
                                      color: Colors.black87,
                                      fontWeight: widget.isReadOverride
                                          ? FontWeight.w600
                                          : FontWeight.bold,
                                      letterSpacing: -0.3),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Row(
                                children: [
                                  Text(DateFormat('hh:mm a').format(createdAt),
                                      style: GoogleFonts.jetBrainsMono(
                                          fontSize: 11,
                                          color: Colors.grey.shade500,
                                          fontWeight: FontWeight.w500)),
                                  if (!widget.isReadOverride) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                            color: widget.primaryColor,
                                            boxShadow: [
                                              BoxShadow(
                                                  color: widget.primaryColor
                                                      .withOpacity(0.4),
                                                  blurRadius: 4,
                                                  spreadRadius: 1)
                                            ],
                                            shape: BoxShape.circle)),
                                  ]
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.translatedBody,
                            style: GoogleFonts.poppins(
                                fontSize: 13.5,
                                fontWeight: widget.isReadOverride
                                    ? FontWeight.w400
                                    : FontWeight.w500,
                                color: widget.isReadOverride
                                    ? Colors.grey.shade600
                                    : Colors.grey.shade800,
                                height: 1.3),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6)),
                            child: Text(status.toUpperCase(),
                                style: GoogleFonts.poppins(
                                    fontSize: 10,
                                    color: statusColor,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5)),
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

  Widget _buildIconBox(IconData icon, Color color) {
    return Container(
      height: 56,
      width: 56,
      decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16)),
      child: Icon(icon, color: color, size: 28),
    );
  }

  Widget _buildStrictImage(String? url, bool isRead) {
    return SizedBox(
      height: 56,
      width: 56,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
          color: isRead
              ? Colors.grey.shade50
              : widget.primaryColor.withOpacity(0.05),
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
                  memCacheWidth: 150,
                  fadeInDuration: const Duration(milliseconds: 150),
                  placeholder: (c, u) => Container(color: Colors.transparent),
                  errorWidget: (c, u, e) => Icon(
                      Icons.notifications_active_outlined,
                      color:
                          isRead ? Colors.grey.shade400 : widget.primaryColor),
                )
              : Icon(Icons.notifications_active_outlined,
                  color: isRead ? Colors.grey.shade400 : widget.primaryColor),
        ),
      ),
    );
  }
}
