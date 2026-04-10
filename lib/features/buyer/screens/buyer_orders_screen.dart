import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

// ✅ LOCALIZATION IMPORTS
import 'package:agriyukt_app/features/farmer/farmer_translations.dart';
import 'package:agriyukt_app/core/providers/language_provider.dart';
import 'package:agriyukt_app/features/buyer/screens/buyer_order_detail_screen.dart';

class BuyerOrdersScreen extends StatefulWidget {
  final int initialIndex;
  final String? highlightOrderId;

  const BuyerOrdersScreen({
    super.key,
    this.initialIndex = 0,
    this.highlightOrderId,
  });

  @override
  State<BuyerOrdersScreen> createState() => _BuyerOrdersScreenState();
}

class _BuyerOrdersScreenState extends State<BuyerOrdersScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _supabase = Supabase.instance.client;
  late TabController _tabController;

  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _allOrders = [];

  final int _limit = 1000;

  String _searchQuery = "";
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  final ScrollController _pendingScroll = ScrollController();
  final ScrollController _activeScroll = ScrollController();
  final ScrollController _historyScroll = ScrollController();
  bool _hasScrolled = false;

  RealtimeChannel? _ordersChannel;

  static const Color _primaryBlue = Color(0xFF1565C0);
  static const Color _surfaceBg = Color(0xFFF4F6F8);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(
        length: 3, vsync: this, initialIndex: widget.initialIndex);

    // 🔒 LOOPHOLE CLOSED: Keyboard Trap Prevention
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        FocusScope.of(context).unfocus();
        HapticFeedback.selectionClick();
      }
    });

    _fetchOrders();
    _setupRealtimeSubscription();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _fetchOrders(isSilent: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    if (_ordersChannel != null) _supabase.removeChannel(_ordersChannel!);
    _searchController.dispose();
    _tabController.dispose();
    _pendingScroll.dispose();
    _activeScroll.dispose();
    _historyScroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _setupRealtimeSubscription();
      _fetchOrders(isSilent: true);
    }
  }

  void _setupRealtimeSubscription() {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    if (_ordersChannel != null) _supabase.removeChannel(_ordersChannel!);

    _ordersChannel = _supabase
        .channel('public:orders_buyer_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'buyer_id',
              value: userId),
          callback: (payload) async {
            if (payload.eventType == PostgresChangeEvent.delete) {
              final oldId = payload.oldRecord['id'];
              if (mounted) {
                setState(() => _allOrders.removeWhere((o) => o['id'] == oldId));
              }
              return;
            }

            final newRec = payload.newRecord;
            if (newRec == null || newRec['id'] == null) return;

            try {
              final updatedOrder = await _supabase
                  .from('orders')
                  .select(
                      '*, farmer:profiles!farmer_id(first_name, last_name, district, state), crop:crops!crop_id(image_url, crop_name, variety)')
                  .eq('id', newRec['id'])
                  .maybeSingle()
                  .timeout(
                      const Duration(seconds: 10)); // 🚀 Timeout protection

              if (updatedOrder != null && mounted) {
                setState(() {
                  final index = _allOrders
                      .indexWhere((o) => o['id'] == updatedOrder['id']);
                  if (index != -1) {
                    _allOrders[index] = updatedOrder;
                  } else {
                    _allOrders.insert(0, updatedOrder);
                  }
                });
              }
            } catch (_) {
              _fetchOrders(isSilent: true);
            }
          },
        );
    _ordersChannel?.subscribe();
  }

  Future<void> _fetchOrders({bool isSilent = false}) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      if (!isSilent && _allOrders.isEmpty && mounted) {
        setState(() {
          _isLoading = true;
          _errorMessage = null;
        });
      }

      // 🚀 TIMEOUT GUARD: Prevents infinite loading loops
      final response = await _supabase
          .from('orders')
          .select('''
            *,
            farmer:profiles!farmer_id(first_name, last_name, district, state),
            crop:crops!crop_id(image_url, crop_name, variety) 
          ''')
          .eq('buyer_id', user.id)
          .order('created_at', ascending: false)
          .limit(_limit)
          .timeout(const Duration(seconds: 15));

      if (mounted) {
        setState(() {
          _allOrders = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
          _errorMessage = null;
        });

        if (widget.highlightOrderId != null && !_hasScrolled) {
          _attemptAutoScroll();
        }
      }
    } catch (e) {
      debugPrint("🚨 SUPABASE FETCH ERROR: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          if (_allOrders.isEmpty) {
            _errorMessage = "Connection error. Please pull to refresh.";
          }
        });
      }
    }
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      setState(() => _searchQuery = query);
    });
  }

  List<Map<String, dynamic>> _getActiveOrders() => _allOrders.where((o) {
        final status = (o['status'] ?? '').toString().toLowerCase().trim();
        return [
              'accepted',
              'confirmed',
              'packed',
              'shipped',
              'in transit',
              'out for delivery',
              'processing'
            ].contains(status) &&
            _matchesSearch(o);
      }).toList();

  List<Map<String, dynamic>> _getCompletedOrders() => _allOrders.where((o) {
        final status = (o['status'] ?? '').toString().toLowerCase().trim();
        return ['delivered', 'completed', 'rejected', 'cancelled']
                .contains(status) &&
            _matchesSearch(o);
      }).toList();

  List<Map<String, dynamic>> _getPendingOrders() => _allOrders.where((o) {
        final status = (o['status'] ?? '').toString().toLowerCase().trim();
        final isActive = [
          'accepted',
          'confirmed',
          'packed',
          'shipped',
          'in transit',
          'out for delivery',
          'processing'
        ].contains(status);
        final isCompleted = ['delivered', 'completed', 'rejected', 'cancelled']
            .contains(status);
        return !isActive && !isCompleted && _matchesSearch(o);
      }).toList();

  bool _matchesSearch(Map<String, dynamic> o) {
    if (_searchQuery.isEmpty) return true;
    final q = _searchQuery.toLowerCase().trim();

    final crop = o['crop'] is Map ? o['crop'] as Map<String, dynamic> : {};
    final farmer =
        o['farmer'] is Map ? o['farmer'] as Map<String, dynamic> : {};

    final cropName =
        (crop['crop_name'] ?? o['crop_name'] ?? '').toString().toLowerCase();
    final variety = (crop['variety'] ?? '').toString().toLowerCase();
    final farmerName =
        "${farmer['first_name'] ?? ''} ${farmer['last_name'] ?? ''}"
            .toLowerCase();
    final orderIdStr = o['id'].toString().toLowerCase();

    return cropName.contains(q) ||
        variety.contains(q) ||
        farmerName.contains(q) ||
        orderIdStr.contains(q);
  }

  // =======================================================================
  // 🚀 EXACT MATH JUMP ENGINE (Zero Visual Hunting)
  // =======================================================================
  void _attemptAutoScroll() {
    if (widget.highlightOrderId == null || _hasScrolled) return;
    final targetOrderIndex = _allOrders
        .indexWhere((o) => o['id'].toString() == widget.highlightOrderId);
    if (targetOrderIndex == -1) return;

    final targetOrder = _allOrders[targetOrderIndex];
    final statusLower =
        (targetOrder['status'] ?? '').toString().toLowerCase().trim();

    int targetTab = 0;
    ScrollController? targetController;

    if ([
      'accepted',
      'confirmed',
      'packed',
      'shipped',
      'in transit',
      'out for delivery',
      'processing'
    ].contains(statusLower)) {
      targetTab = 1;
      targetController = _activeScroll;
    } else if (['delivered', 'completed', 'rejected', 'cancelled']
        .contains(statusLower)) {
      targetTab = 2;
      targetController = _historyScroll;
    } else {
      targetTab = 0;
      targetController = _pendingScroll;
    }

    if (_tabController.index != targetTab) {
      _tabController.index = targetTab; // Instant Tab Update
    }

    List<Map<String, dynamic>> targetList = targetTab == 0
        ? _getPendingOrders()
        : targetTab == 1
            ? _getActiveOrders()
            : _getCompletedOrders();
    final indexInList = targetList
        .indexWhere((o) => o['id'].toString() == widget.highlightOrderId);

    if (indexInList != -1) {
      _hasScrolled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (targetController != null && targetController.hasClients) {
          // 🔒 EXACT MATH: New Card Height (290) + Separator (16) = 306.0 pixels exactly
          targetController.jumpTo(indexInList * 306.0);
        }
      });
    }
  }

  Future<void> _cancelOrder(String orderId) async {
    HapticFeedback.mediumImpact();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: Colors.red.shade50, shape: BoxShape.circle),
              child: const Icon(Icons.warning_amber_rounded,
                  color: Colors.redAccent, size: 28),
            ),
            const SizedBox(height: 12),
            Text("Cancel Order?",
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Colors.black87)),
          ],
        ),
        content: Text("Are you sure you want to cancel this pending request?",
            textAlign: TextAlign.center,
            style:
                GoogleFonts.poppins(color: Colors.grey.shade600, fontSize: 13)),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.only(bottom: 16, left: 16, right: 16),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12)),
                  child: Text("Keep It",
                      style: GoogleFonts.poppins(
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade600,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                  child: Text("Cancel",
                      style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final messenger = ScaffoldMessenger.of(context);
      showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const Center(
              child: CircularProgressIndicator(color: Colors.white)));

      try {
        // 🚀 TIMEOUT GUARD ADDED
        await _supabase
            .from('orders')
            .update({'status': 'cancelled'})
            .eq('id', orderId)
            .timeout(const Duration(seconds: 10));

        if (mounted) {
          setState(() {
            final orderIndex =
                _allOrders.indexWhere((o) => o['id'].toString() == orderId);
            if (orderIndex != -1) {
              final updatedCard =
                  Map<String, dynamic>.from(_allOrders[orderIndex]);
              updatedCard['status'] = 'cancelled';
              _allOrders[orderIndex] = updatedCard;
            }
          });
        }

        if (mounted) Navigator.pop(context);
        HapticFeedback.lightImpact();

        messenger.showSnackBar(SnackBar(
          content: Row(children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Text("Request cancelled successfully.",
                style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
          ]),
          backgroundColor: Colors.grey.shade900,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ));
      } catch (e) {
        if (mounted) Navigator.pop(context); // Close loading dialog
        HapticFeedback.heavyImpact(); // 🚀 ANTI-SILENT FAILURE
        messenger.showSnackBar(SnackBar(
          content: Text("Action Failed. Please check connection.",
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.red.shade800,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  String _text(String key) => FarmerText.get(context, key);

  @override
  Widget build(BuildContext context) {
    Provider.of<LanguageProvider>(context);
    final myId = _supabase.auth.currentUser?.id;

    if (myId == null) {
      return Scaffold(body: Center(child: Text(_text('login_required'))));
    }

    final pending = _getPendingOrders();
    final active = _getActiveOrders();
    final history = _getCompletedOrders();

    return Scaffold(
      backgroundColor: _surfaceBg,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: _primaryBlue,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 16,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Container(
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 3))
            ],
          ),
          child: TextField(
            controller: _searchController,
            style: GoogleFonts.poppins(color: Colors.black87, fontSize: 13),
            onChanged: _onSearchChanged,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => FocusScope.of(context).unfocus(),
            decoration: InputDecoration(
              hintText: "Search crop, variety, or order ID...",
              hintStyle: GoogleFonts.poppins(
                  color: Colors.grey.shade400, fontSize: 13),
              prefixIcon: Icon(Icons.search_rounded,
                  color: Colors.grey.shade400, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.cancel_rounded,
                          color: Colors.grey.shade400, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged("");
                        FocusScope.of(context).unfocus();
                      })
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withOpacity(0.6),
          labelStyle:
              GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 13),
          unselectedLabelStyle:
              GoogleFonts.poppins(fontWeight: FontWeight.w500, fontSize: 13),
          tabs: [
            Tab(text: _text('requests')),
            Tab(text: _text('active')),
            const Tab(text: "History")
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _OrderList(
            orders: pending,
            isLoading: _isLoading,
            controller: _pendingScroll,
            onRefresh: _fetchOrders,
            onCancel: _cancelOrder,
            emptyMsg: "No pending requests",
            emptySubMsg: "Orders waiting for farmer approval will appear here.",
            icon: Icons.hourglass_empty_rounded,
            errorMessage: _errorMessage,
            highlightOrderId: widget.highlightOrderId,
            tabType: 'pending',
          ),
          _OrderList(
            orders: active,
            isLoading: _isLoading,
            controller: _activeScroll,
            onRefresh: _fetchOrders,
            onCancel: _cancelOrder,
            emptyMsg: "No active orders",
            emptySubMsg: "Track your confirmed and shipped orders here.",
            icon: Icons.local_shipping_outlined,
            errorMessage: _errorMessage,
            highlightOrderId: widget.highlightOrderId,
            tabType: 'active',
          ),
          _OrderList(
            orders: history,
            isLoading: _isLoading,
            controller: _historyScroll,
            onRefresh: _fetchOrders,
            onCancel: _cancelOrder,
            emptyMsg: "No order history",
            emptySubMsg: "Delivered and cancelled orders will be saved here.",
            icon: Icons.inventory_2_outlined,
            errorMessage: _errorMessage,
            highlightOrderId: widget.highlightOrderId,
            tabType: 'history',
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// ✅ THE LIST ENGINE
// ============================================================================
class _OrderList extends StatefulWidget {
  final List<Map<String, dynamic>> orders;
  final bool isLoading;
  final String? errorMessage;
  final ScrollController controller;
  final Future<void> Function({bool isSilent}) onRefresh;
  final Function(String) onCancel;
  final String emptyMsg;
  final String emptySubMsg;
  final String tabType;
  final IconData icon;
  final String? highlightOrderId;

  const _OrderList({
    required this.orders,
    required this.isLoading,
    this.errorMessage,
    required this.controller,
    required this.onRefresh,
    required this.onCancel,
    required this.emptyMsg,
    required this.emptySubMsg,
    required this.tabType,
    required this.icon,
    this.highlightOrderId,
  });

  @override
  State<_OrderList> createState() => _OrderListState();
}

class _OrderListState extends State<_OrderList>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return RefreshIndicator(
      onRefresh: () async {
        HapticFeedback.lightImpact();
        await widget.onRefresh(isSilent: true);
      },
      color: const Color(0xFF1565C0),
      backgroundColor: Colors.white,
      child: ListView.separated(
        key: PageStorageKey('list_${widget.tabType}'),
        controller: widget.controller,
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, MediaQuery.of(context).padding.bottom + 40),
        itemCount: widget.isLoading && widget.orders.isEmpty
            ? 4
            : widget.orders.isEmpty
                ? 1
                : widget.orders.length,
        separatorBuilder: (_, __) =>
            const SizedBox(height: 16), // Accounts for 16px exact math
        itemBuilder: (context, index) {
          if (widget.errorMessage != null && widget.orders.isEmpty) {
            return SizedBox(
              height: MediaQuery.of(context).size.height * 0.5,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline,
                      size: 50, color: Colors.red.shade300),
                  const SizedBox(height: 16),
                  Text("Database Error",
                      style: GoogleFonts.poppins(
                          color: Colors.red.shade800,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(widget.errorMessage!,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                          color: Colors.grey.shade600, fontSize: 13)),
                ],
              ),
            );
          }

          if (widget.isLoading && widget.orders.isEmpty) {
            return const _SkeletonOrderCard();
          }

          if (widget.orders.isEmpty) {
            return SizedBox(
              height: MediaQuery.of(context).size.height * 0.5,
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
                                color: Colors.black.withOpacity(0.04),
                                blurRadius: 16)
                          ]),
                      child: Icon(widget.icon,
                          size: 50,
                          color: const Color(0xFF1565C0).withOpacity(0.5))),
                  const SizedBox(height: 20),
                  Text(widget.emptyMsg,
                      style: GoogleFonts.poppins(
                          color: Colors.black87,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(widget.emptySubMsg,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                          color: Colors.grey.shade500, fontSize: 13)),
                ],
              ),
            );
          }

          final order = widget.orders[index];
          final isHighlighted =
              order['id'].toString() == widget.highlightOrderId;

          return _PremiumOrderCard(
            key: ValueKey(order['id'].toString()),
            order: order,
            tabType: widget.tabType,
            onCancel: widget.onCancel,
            isHighlighted: isHighlighted,
          );
        },
      ),
    );
  }
}

// ============================================================================
// ✅ THE PERFECT GEOMETRY SKELETON
// ============================================================================
class _SkeletonOrderCard extends StatelessWidget {
  const _SkeletonOrderCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 290, // 🚀 UPDATED: Taller Parent Card
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 🚀 FLUID HEADER
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [
                  Container(
                      height: 24,
                      width: 24,
                      decoration: BoxDecoration(
                          color: Colors.grey.shade200, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Container(height: 14, width: 100, color: Colors.grey.shade200)
                ]),
                Container(
                    height: 20,
                    width: 60,
                    decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(100))),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFFF0F0F0)),
          // 🚀 FLUID BODY (Expanded acts as a shock absorber)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                      height: 110, // 🚀 UPDATED: Larger skeleton image
                      width: 110,
                      decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(12))),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                            height: 16,
                            width: double.infinity,
                            color: Colors.grey.shade200),
                        const SizedBox(height: 8),
                        Container(
                            height: 16,
                            width: 120,
                            color: Colors.grey.shade200),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFFF0F0F0)),
          // 🚀 FLUID FOOTER
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                        height: 12, width: 100, color: Colors.grey.shade200),
                    const SizedBox(height: 6),
                    Container(
                        height: 10, width: 140, color: Colors.grey.shade200),
                  ],
                ),
                Container(
                    height: 38,
                    width: 120,
                    decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(100))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// ✅ THE UNCOMPROMISED PREMIUM BUYER CARD (HARDWARE GEOMETRY LOCKED)
// ============================================================================
class _PremiumOrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final String tabType;
  final Function(String) onCancel;
  final bool isHighlighted;

  const _PremiumOrderCard({
    super.key,
    required this.order,
    required this.tabType,
    required this.onCancel,
    this.isHighlighted = false,
  });

  String _formatRelativeDate(String? isoDate) {
    if (isoDate == null) return 'Unknown Date';
    final DateTime? date = DateTime.tryParse(isoDate)?.toLocal();
    if (date == null) return 'Unknown Date';

    final DateTime now = DateTime.now();
    final int diffDays = DateTime(now.year, now.month, now.day)
        .difference(DateTime(date.year, date.month, date.day))
        .inDays;

    if (diffDays == 0) return "Today, ${DateFormat('jm').format(date)}";
    if (diffDays == 1) return "Yesterday, ${DateFormat('jm').format(date)}";
    return DateFormat('dd MMM yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final String fullId = order['id'].toString();
    final rawStatus = order['status'] ?? 'Pending';
    final statusLower = rawStatus.toString().toLowerCase().trim();

    final List<String> validActiveStates = [
      'accepted',
      'confirmed',
      'packed',
      'shipped',
      'in transit',
      'out for delivery',
      'processing',
      'delivered',
      'completed'
    ];
    final bool isAccepted = validActiveStates.contains(statusLower);
    final bool isPending = !isAccepted &&
        !['delivered', 'completed', 'rejected', 'cancelled']
            .contains(statusLower);

    String displayStatus = rawStatus.toString().toUpperCase();
    Color statusColor = const Color(0xFFF57C00);
    Color statusBg = const Color(0xFFFFF3E0);
    IconData statusIcon = Icons.pending_actions_rounded;

    if (isPending) {
      displayStatus = "AWAITING APPROVAL";
      statusIcon = Icons.hourglass_top_rounded;
    } else if (['delivered', 'completed'].contains(statusLower)) {
      displayStatus = "DELIVERED";
      statusColor = const Color(0xFF2E7D32);
      statusBg = const Color(0xFFE8F5E9);
      statusIcon = Icons.check_circle_rounded;
    } else if (['rejected', 'cancelled'].contains(statusLower)) {
      displayStatus = "CANCELLED";
      statusColor = const Color(0xFFD32F2F);
      statusBg = const Color(0xFFFFEBEE);
      statusIcon = Icons.cancel_rounded;
    } else {
      displayStatus =
          (order['tracking_status'] ?? rawStatus).toString().toUpperCase();
      statusColor = const Color(0xFF1565C0);
      statusBg = const Color(0xFFE8F0FE);
      statusIcon = Icons.local_shipping_rounded;
    }

    final farmer =
        order['farmer'] is Map ? order['farmer'] as Map<String, dynamic> : {};
    final String farmerName =
        "${farmer['first_name'] ?? ''} ${farmer['last_name'] ?? ''}".trim();

    final String orderDate = _formatRelativeDate(order['created_at']);
    final String orderIdDisplay = "#${fullId.substring(0, 8).toUpperCase()}";

    final priceRaw = order['price_offered'];
    final price =
        priceRaw != null ? (num.tryParse(priceRaw.toString()) ?? 0) : 0;
    final String formattedPrice =
        NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
            .format(price);

    final qtyRaw = order['quantity_kg'];
    final qty = qtyRaw != null ? (num.tryParse(qtyRaw.toString()) ?? 0) : 0;

    final crop =
        order['crop'] is Map ? order['crop'] as Map<String, dynamic> : {};
    String cropName = crop['crop_name'] ?? order['crop_name'] ?? "Crop Item";
    String cropVariety = crop['variety'] ?? '';
    String? imgUrl = crop['image_url'];

    String displayCropName = cropName;
    if (cropVariety.isNotEmpty && cropVariety.toLowerCase() != 'null') {
      displayCropName = "$cropName : $cropVariety";
    }

    return RepaintBoundary(
      child: Container(
        height: 290, // 🚀 UPDATED: Taller Parent Card
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: isHighlighted
                  ? const Color(0xFF1565C0)
                  : Colors.grey.shade200,
              width: isHighlighted ? 2.5 : 1),
          boxShadow: [
            BoxShadow(
                color: isHighlighted
                    ? const Color(0xFF1565C0).withOpacity(0.15)
                    : Colors.black.withOpacity(0.03),
                blurRadius: isHighlighted ? 20 : 15,
                offset: const Offset(0, 6))
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: isAccepted
                ? () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            BuyerOrderDetailScreen(orderId: fullId)))
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 🚀 FLUID HEADER
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: isHighlighted
                        ? const Color(0xFF1565C0).withOpacity(0.05)
                        : Colors.grey.shade50,
                    borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(15),
                        topRight: Radius.circular(15)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            CircleAvatar(
                                radius: 12,
                                backgroundColor:
                                    const Color(0xFF1565C0).withOpacity(0.1),
                                child: Text(
                                    farmerName.isNotEmpty
                                        ? farmerName[0].toUpperCase()
                                        : "F",
                                    style: GoogleFonts.poppins(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: const Color(0xFF1565C0)))),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                  farmerName.isNotEmpty
                                      ? farmerName
                                      : "Unknown Farmer",
                                  style: GoogleFonts.poppins(
                                      fontSize: 14, // 🚀 Increased font
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                            color: statusBg,
                            borderRadius: BorderRadius.circular(100)),
                        child: Row(
                          children: [
                            Icon(statusIcon, size: 10, color: statusColor),
                            const SizedBox(width: 4),
                            Text(displayStatus,
                                style: GoogleFonts.poppins(
                                    color: statusColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 10, // 🚀 Adjusted Size
                                    letterSpacing: 0.5)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(
                    height: 1, thickness: 1, color: Color(0xFFF0F0F0)),
                // 🚀 FLUID BODY (Expanded absorbs variations)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          height: 110, // 🚀 UPDATED: Larger Crop Image
                          width: 110,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(11),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(11),
                                // 🔒 LOOPHOLE CLOSED: Unique Hero Tag per Tab
                                child: Hero(
                                  tag: 'buyer_order_img_${tabType}_$fullId',
                                  child: (imgUrl != null && imgUrl.isNotEmpty)
                                      ? CachedNetworkImage(
                                          imageUrl: imgUrl.startsWith('http')
                                              ? imgUrl
                                              : Supabase.instance.client.storage
                                                  .from('crop_images')
                                                  .getPublicUrl(imgUrl),
                                          fit: BoxFit.cover,
                                          memCacheWidth: 300,
                                          memCacheHeight: 300,
                                          fadeInDuration:
                                              const Duration(milliseconds: 150),
                                          placeholder: (c, u) => Container(
                                              color: Colors.grey.shade100),
                                          errorWidget: (context, url, error) =>
                                              const Icon(
                                                  Icons.image_not_supported,
                                                  color: Colors.grey),
                                        )
                                      : Image.asset(
                                          'assets/images/placeholder_crop.png',
                                          fit: BoxFit.cover),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Flexible(
                                child: Text(displayCropName,
                                    style: GoogleFonts.poppins(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                        letterSpacing: -0.5,
                                        height: 1.2),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Text(formattedPrice,
                                      style: GoogleFonts.poppins(
                                          fontSize: 18, // 🚀 Increased Size
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black87)),
                                  const SizedBox(width: 6),
                                  Text("•  $qty kg",
                                      style: GoogleFonts.poppins(
                                          fontSize: 13, // 🚀 Increased Size
                                          fontWeight: FontWeight.w500,
                                          color: Colors.grey.shade600)),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (isAccepted)
                          Padding(
                            padding: const EdgeInsets.only(left: 8.0),
                            child: Icon(Icons.arrow_forward_ios_rounded,
                                color: Colors.grey.shade400, size: 16),
                          ),
                      ],
                    ),
                  ),
                ),
                const Divider(
                    height: 1, thickness: 1, color: Color(0xFFF0F0F0)),
                // 🚀 FLUID FOOTER
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Ordered: $orderDate",
                                style: GoogleFonts.poppins(
                                    fontSize: 12, // 🚀 Scaled up
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade600)),
                            const SizedBox(height: 2),
                            // 🚀 HIGHLIGHTED, HIGH-CONTRAST ORDER ID PILL
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE3F2FD),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(orderIdDisplay,
                                  style: GoogleFonts.jetBrainsMono(
                                      fontSize:
                                          11, // 🚀 Increased Order ID Font
                                      color: const Color(0xFF1565C0),
                                      fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ),
                      ),
                      if (isAccepted)
                        ElevatedButton(
                          onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      BuyerOrderDetailScreen(orderId: fullId))),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1565C0),
                              elevation: 0,
                              minimumSize:
                                  const Size(120, 38), // 🚀 Safe button height
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(100)),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 0)),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text("View Details",
                                  style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white)),
                            ],
                          ),
                        )
                      else if (isPending)
                        TextButton(
                          onPressed: () => onCancel(fullId),
                          style: TextButton.styleFrom(
                              foregroundColor: Colors.red.shade700,
                              backgroundColor: Colors.red.shade50,
                              minimumSize:
                                  const Size(0, 38), // 🚀 Safe button height
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(100)),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 0)),
                          child: Text("Cancel Order",
                              style: GoogleFonts.poppins(
                                  fontSize: 12, fontWeight: FontWeight.bold)),
                        )
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
