import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

// ✅ LOCALIZATION IMPORTS
import 'package:agriyukt_app/features/farmer/farmer_translations.dart';
import 'package:agriyukt_app/core/providers/language_provider.dart';
import 'package:agriyukt_app/features/farmer/screens/farmer_order_detail_screen.dart';

class OrdersScreen extends StatefulWidget {
  final int initialIndex;
  final String? highlightOrderId;

  const OrdersScreen({
    super.key,
    this.initialIndex = 0,
    this.highlightOrderId,
  });

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _supabase = Supabase.instance.client;
  late TabController _tabController;

  // ✅ STATE ENGINE
  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _allOrders = [];

  // ✅ SEARCH ENGINE
  String _searchQuery = "";
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  // ✅ INDEPENDENT SCROLL CONTROLLERS
  final ScrollController _pendingScroll = ScrollController();
  final ScrollController _activeScroll = ScrollController();
  final ScrollController _historyScroll = ScrollController();
  bool _hasScrolled = false;

  RealtimeChannel? _ordersChannel;

  // Signature Farmer Theme
  static const Color _primaryGreen = Color(0xFF1B5E20);
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
    _searchController.dispose();
    if (_ordersChannel != null) _supabase.removeChannel(_ordersChannel!);
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

  // =======================================================================
  // 📦 REALTIME MACRO-FETCH ENGINE
  // =======================================================================
  void _setupRealtimeSubscription() {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    if (_ordersChannel != null) _supabase.removeChannel(_ordersChannel!);

    _ordersChannel = _supabase
        .channel('public:orders_farmer_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'farmer_id',
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
              final updatedOrder = await _supabase.from('orders').select('''
                    *,
                    buyer:profiles!buyer_id(first_name, last_name, phone, district, state),
                    crop:crops!crop_id(image_url, crop_name, variety, grade)
                  ''').eq('id', newRec['id']).maybeSingle();

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
        )
        .subscribe();
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

      final response = await _supabase
          .from('orders')
          .select('''
            *,
            buyer:profiles!buyer_id(first_name, last_name, phone, district, state),
            crop:crops!crop_id(image_url, crop_name, variety, grade)
          ''')
          .eq('farmer_id', user.id)
          .order('created_at', ascending: false)
          .limit(1000);

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
      debugPrint("🚨 DB FETCH ERROR: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          if (_allOrders.isEmpty) {
            _errorMessage = "Connection error. Pull to refresh.";
          }
        });
      }
    }
  }

  // =======================================================================
  // 🧭 SEARCH, FILTER & INSTANT SNAP NAVIGATION ENGINE
  // =======================================================================
  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _searchQuery = query);
    });
  }

  bool _matchesSearch(Map<String, dynamic> o) {
    if (_searchQuery.isEmpty) return true;
    final q = _searchQuery.toLowerCase().trim();

    final rawCrop = o['crop'];
    final crop = rawCrop is Map
        ? rawCrop
        : (rawCrop is List && rawCrop.isNotEmpty ? rawCrop[0] : {});

    final rawBuyer = o['buyer'];
    final buyer = rawBuyer is Map
        ? rawBuyer
        : (rawBuyer is List && rawBuyer.isNotEmpty ? rawBuyer[0] : {});

    final cropName =
        (crop['crop_name'] ?? o['crop_name'] ?? '').toString().toLowerCase();
    final variety = (crop['variety'] ?? '').toString().toLowerCase();
    final buyerName = "${buyer['first_name'] ?? ''} ${buyer['last_name'] ?? ''}"
        .toLowerCase();
    final orderIdStr = o['id'].toString().toLowerCase();

    return cropName.contains(q) ||
        variety.contains(q) ||
        buyerName.contains(q) ||
        orderIdStr.contains(q);
  }

  List<Map<String, dynamic>> _getPendingOrders() => _allOrders.where((o) {
        final status = (o['status'] ?? '').toString().toLowerCase().trim();
        return (status == 'pending' || status == 'requested') &&
            _matchesSearch(o);
      }).toList();

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
      _tabController.index = targetTab;
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
      _safeScrollTo(targetController, indexInList);
    }
  }

  void _safeScrollTo(ScrollController? controller, int index) {
    if (controller == null) return;
    int retries = 0;
    Timer.periodic(const Duration(milliseconds: 20), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (controller.hasClients) {
        controller.jumpTo(index * 306.0);
        timer.cancel();
      } else if (retries > 25) {
        timer.cancel();
      }
      retries++;
    });
  }

  // =======================================================================
  // 🛡️ STATUS MUTATION LOGIC (WITH ANTI-CORRUPTION TRANSACTIONS)
  // =======================================================================
  Future<bool> _updateStatus(dynamic orderId, String newStatus) async {
    HapticFeedback.mediumImpact();
    try {
      // 🔒 LOOPHOLE CLOSED: Secure the Order Data first!
      // If we deduct crop inventory first and the order API fails, the stock is lost forever.
      await _supabase
          .from('orders')
          .update({'status': newStatus, 'tracking_status': newStatus}).eq(
              'id', orderId);

      // 1️⃣ DEDUCT INVENTORY LOGIC (Only runs if order successfully accepted)
      if (newStatus.toLowerCase() == 'accepted') {
        try {
          final orderData = _allOrders
              .firstWhere((o) => o['id'].toString() == orderId.toString());
          final String cropId = orderData['crop_id'].toString();

          final double orderQty = double.tryParse(orderData['quantity_kg']
                      ?.toString()
                      .replaceAll(RegExp(r'[^0-9.]'), '') ??
                  orderData['quantity']
                      ?.toString()
                      .replaceAll(RegExp(r'[^0-9.]'), '') ??
                  '0') ??
              0.0;

          final cropRes =
              await _supabase.from('crops').select().eq('id', cropId).single();
          final bool hasNewColumn = cropRes.containsKey('quantity_kg');

          double currentStock = 0.0;
          if (hasNewColumn && cropRes['quantity_kg'] != null) {
            currentStock = (cropRes['quantity_kg'] as num).toDouble();
          } else {
            final String legacyQty = cropRes['quantity']?.toString() ?? '0';
            currentStock =
                double.tryParse(legacyQty.replaceAll(RegExp(r'[^0-9.]'), '')) ??
                    0.0;
          }

          double newStock = currentStock - orderQty;
          if (newStock < 0) newStock = 0.0;

          String cropStatus = cropRes['status'];
          if (newStock <= 0) cropStatus = 'Sold';

          final Map<String, dynamic> cropUpdateData = {
            'quantity': newStock.toString(),
            'status': cropStatus,
          };
          if (hasNewColumn) cropUpdateData['quantity_kg'] = newStock;

          await _supabase.from('crops').update(cropUpdateData).eq('id', cropId);
        } catch (cropError) {
          // Even if crop deduction fails due to schema issues, the order is safely accepted.
          debugPrint(
              "Warning: Crop deduction failed, but order accepted. $cropError");
        }
      }

      // 2️⃣ UPDATE LOCAL UI STATE INSTANTLY (Optimistic UI)
      if (mounted) {
        setState(() {
          final orderIndex = _allOrders
              .indexWhere((o) => o['id'].toString() == orderId.toString());
          if (orderIndex != -1) {
            final updatedCard =
                Map<String, dynamic>.from(_allOrders[orderIndex]);
            updatedCard['status'] = newStatus;
            updatedCard['tracking_status'] = newStatus;
            _allOrders[orderIndex] = updatedCard;
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: [
              Icon(
                  newStatus.toLowerCase() == 'accepted'
                      ? Icons.check_circle_rounded
                      : Icons.cancel_rounded,
                  color: Colors.white),
              const SizedBox(width: 12),
              Text(
                  newStatus.toLowerCase() == 'accepted'
                      ? "Order Accepted"
                      : "Order $newStatus",
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            ]),
            backgroundColor: newStatus.toLowerCase() == 'accepted'
                ? Colors.green.shade700
                : Colors.red.shade800,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
      return true;
    } catch (e) {
      debugPrint("Error updating status: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Action Failed. Please check connection.",
              style: GoogleFonts.poppins()),
          backgroundColor: Colors.red,
        ));
      }
      _fetchOrders(isSilent: true); // Force revert UI
      return false;
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
        backgroundColor: _primaryGreen,
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
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 8,
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
              hintText:
                  "Search name, crop, or ID...", // Cleaned up for localization
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
          labelColor: Colors.white,
          indicatorColor: Colors.white,
          unselectedLabelColor: Colors.white.withOpacity(0.6),
          labelStyle:
              GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 13),
          unselectedLabelStyle:
              GoogleFonts.poppins(fontWeight: FontWeight.w500, fontSize: 13),
          indicatorWeight: 3,
          tabs: [
            Tab(text: _text('requests')),
            Tab(text: _text('active')),
            const Tab(text: "History"),
          ],
        ),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _isLoading
            ? ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 4,
                separatorBuilder: (_, __) => const SizedBox(height: 16),
                itemBuilder: (_, __) => const _SkeletonOrderCard(),
              )
            : TabBarView(
                key: const ValueKey('tab_view_data'),
                controller: _tabController,
                children: [
                  _OrderList(
                    orders: pending,
                    isLoading: _isLoading,
                    controller: _pendingScroll,
                    onRefresh: _fetchOrders,
                    onStatusUpdate: _updateStatus,
                    emptyMsg: "No pending requests",
                    emptySubMsg:
                        "Orders waiting for your approval will appear here.",
                    icon: Icons.inbox_rounded,
                    errorMessage: _errorMessage,
                    highlightOrderId: widget.highlightOrderId,
                    tabType: 'pending',
                  ),
                  _OrderList(
                    orders: active,
                    isLoading: _isLoading,
                    controller: _activeScroll,
                    onRefresh: _fetchOrders,
                    onStatusUpdate: _updateStatus,
                    emptyMsg: "No active orders",
                    emptySubMsg:
                        "Your packed and shipped orders will be tracked here.",
                    icon: Icons.local_shipping_rounded,
                    errorMessage: _errorMessage,
                    highlightOrderId: widget.highlightOrderId,
                    tabType: 'active',
                  ),
                  _OrderList(
                    orders: history,
                    isLoading: _isLoading,
                    controller: _historyScroll,
                    onRefresh: _fetchOrders,
                    onStatusUpdate: _updateStatus,
                    emptyMsg: "No past orders",
                    emptySubMsg:
                        "Delivered and cancelled orders will be saved here.",
                    icon: Icons.history_rounded,
                    errorMessage: _errorMessage,
                    highlightOrderId: widget.highlightOrderId,
                    tabType: 'history',
                  ),
                ],
              ),
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
  final Future<bool> Function(dynamic, String) onStatusUpdate;
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
    required this.onStatusUpdate,
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
      color: const Color(0xFF1B5E20),
      backgroundColor: Colors.white,
      child: ListView.separated(
        key: PageStorageKey('list_${widget.tabType}'),
        controller: widget.controller,
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, MediaQuery.of(context).padding.bottom + 40),
        itemCount: widget.orders.isEmpty ? 1 : widget.orders.length,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (context, index) {
          if (widget.errorMessage != null && widget.orders.isEmpty) {
            return SizedBox(
              height: MediaQuery.of(context).size.height * 0.5,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline_rounded,
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
                          color: const Color(0xFF1B5E20).withOpacity(0.5))),
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

          return _FarmerOrderCard(
            key: ValueKey('farmer_card_${order['id']}'),
            order: order,
            tabType: widget.tabType,
            onStatusUpdate: widget.onStatusUpdate,
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
      height: 290,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                      height: 110,
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(height: 12, width: 100, color: Colors.grey.shade200),
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
// ✅ THE UNCOMPROMISED PREMIUM FARMER CARD
// ============================================================================
class _FarmerOrderCard extends StatefulWidget {
  final Map<String, dynamic> order;
  final String tabType;
  final Future<bool> Function(dynamic, String) onStatusUpdate;
  final bool isHighlighted;

  const _FarmerOrderCard({
    super.key,
    required this.order,
    required this.tabType,
    required this.onStatusUpdate,
    this.isHighlighted = false,
  });

  @override
  State<_FarmerOrderCard> createState() => _FarmerOrderCardState();
}

class _FarmerOrderCardState extends State<_FarmerOrderCard> {
  bool _isAccepting = false;
  bool _isRejecting = false;

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
    return DateFormat('MMM d, yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final String fullId = order['id'].toString();
    final rawStatus = order['status'] ?? 'Pending';
    final statusLower = rawStatus.toString().toLowerCase().trim();

    String displayStatus = rawStatus.toString().toUpperCase();
    Color statusColor = const Color(0xFFF57C00);
    Color statusBg = const Color(0xFFFFF3E0);
    IconData statusIcon = Icons.pending_actions_rounded;

    if (statusLower == 'pending' || statusLower == 'requested') {
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

    final rawBuyer = order['buyer'];
    final buyer = rawBuyer is Map
        ? rawBuyer
        : (rawBuyer is List && rawBuyer.isNotEmpty ? rawBuyer[0] : {});
    final String buyerName =
        "${buyer['first_name'] ?? order['buyer_name'] ?? 'Buyer'} ${buyer['last_name'] ?? ''}"
            .trim();

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

    final rawCrop = order['crop'];
    final crop = rawCrop is Map
        ? rawCrop
        : (rawCrop is List && rawCrop.isNotEmpty ? rawCrop[0] : {});

    String cropName = crop['crop_name'] ?? order['crop_name'] ?? "Crop Item";
    String? imgUrl = crop['image_url'];
    String cropVariety = crop['variety'] ?? order['variety'] ?? '';
    String cropGrade = crop['grade'] ?? order['grade'] ?? '';

    String displayTitle = cropName;
    if (cropVariety.isNotEmpty && cropVariety.toLowerCase() != 'null') {
      displayTitle = "$cropName : $cropVariety";
    }

    return RepaintBoundary(
      child: Container(
        height: 290,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: widget.isHighlighted
                  ? const Color(0xFF1B5E20)
                  : Colors.grey.shade200,
              width: widget.isHighlighted ? 2.5 : 1),
          boxShadow: [
            BoxShadow(
                color: widget.isHighlighted
                    ? const Color(0xFF1B5E20).withOpacity(0.15)
                    : Colors.black.withOpacity(0.03),
                blurRadius: widget.isHighlighted ? 20 : 15,
                offset: const Offset(0, 6))
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: widget.tabType != 'pending'
                ? () {
                    Navigator.push(
                      context,
                      PageRouteBuilder(
                        transitionDuration: const Duration(milliseconds: 250),
                        pageBuilder: (_, __, ___) =>
                            FarmerOrderDetailScreen(orderId: fullId),
                        transitionsBuilder: (_, anim, __, child) =>
                            FadeTransition(opacity: anim, child: child),
                      ),
                    );
                  }
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 🚀 HEADER
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: widget.isHighlighted
                        ? const Color(0xFF1B5E20).withOpacity(0.05)
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
                                backgroundColor: Colors.amber.shade100,
                                child: Text(
                                    buyerName.isNotEmpty
                                        ? buyerName[0].toUpperCase()
                                        : "B",
                                    style: GoogleFonts.poppins(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.amber.shade900))),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(buyerName,
                                  style: GoogleFonts.poppins(
                                      fontSize: 14,
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
                                    fontSize: 10,
                                    letterSpacing: 0.5)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(
                    height: 1, thickness: 1, color: Color(0xFFF0F0F0)),
                // 🚀 BODY
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          height: 110,
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
                                // 🔒 LOOPHOLE CLOSED: Unique Hero Tag per Tab to prevent crash
                                child: Hero(
                                  tag:
                                      'farmer_order_img_${widget.tabType}_$fullId',
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
                                child: Text(displayTitle,
                                    style: GoogleFonts.poppins(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                        letterSpacing: -0.5,
                                        height: 1.2),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ),
                              if (cropGrade.isNotEmpty &&
                                  cropGrade.toLowerCase() != 'null')
                                Padding(
                                  padding:
                                      const EdgeInsets.only(top: 4, bottom: 4),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                            color: Colors.grey.shade300)),
                                    child: Text("Grade $cropGrade",
                                        style: GoogleFonts.poppins(
                                            fontSize: 11,
                                            color: Colors.grey.shade700,
                                            fontWeight: FontWeight.w600),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                  ),
                                ),
                              const SizedBox(height: 6),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Text(formattedPrice,
                                      style: GoogleFonts.poppins(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black87)),
                                  const SizedBox(width: 6),
                                  Text("•  $qty kg",
                                      style: GoogleFonts.poppins(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.grey.shade600)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(
                    height: 1, thickness: 1, color: Color(0xFFF0F0F0)),
                // 🚀 FOOTER
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (widget.tabType != 'pending') ...[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Ordered: $orderDate",
                                  style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey.shade600)),
                              const SizedBox(height: 2),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                    color: const Color(0xFFE3F2FD),
                                    borderRadius: BorderRadius.circular(4)),
                                child: Text(orderIdDisplay,
                                    style: GoogleFonts.jetBrainsMono(
                                        fontSize: 11,
                                        color: const Color(0xFF1565C0),
                                        fontWeight: FontWeight.w700)),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.push(
                            context,
                            PageRouteBuilder(
                              transitionDuration:
                                  const Duration(milliseconds: 250),
                              pageBuilder: (_, __, ___) =>
                                  FarmerOrderDetailScreen(orderId: fullId),
                              transitionsBuilder: (_, anim, __, child) =>
                                  FadeTransition(opacity: anim, child: child),
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: widget.tabType == 'active'
                                  ? const Color(0xFF1B5E20)
                                  : Colors.white,
                              foregroundColor: widget.tabType == 'active'
                                  ? Colors.white
                                  : Colors.black87,
                              side: widget.tabType == 'active'
                                  ? BorderSide.none
                                  : BorderSide(color: Colors.grey.shade300),
                              elevation: 0,
                              minimumSize: const Size(120, 38),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(100)),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 0)),
                          child: Text(
                            widget.tabType == 'active'
                                ? FarmerText.get(context, 'manage_status')
                                : FarmerText.get(context, 'view_details'),
                            style: GoogleFonts.poppins(
                                fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        )
                      ] else ...[
                        Expanded(
                          child: SizedBox(
                            height: 38,
                            child: OutlinedButton(
                              onPressed: (_isAccepting || _isRejecting)
                                  ? null
                                  : () async {
                                      setState(() => _isRejecting = true);
                                      await widget.onStatusUpdate(
                                          fullId, 'rejected');
                                      if (mounted)
                                        setState(() => _isRejecting = false);
                                    },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red.shade700,
                                side: BorderSide(color: Colors.red.shade300),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(100)),
                                padding: EdgeInsets.zero,
                              ),
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                child: _isRejecting
                                    ? const SizedBox(
                                        height: 16,
                                        width: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2, color: Colors.red))
                                    : Text(FarmerText.get(context, 'reject'),
                                        key: const ValueKey('reject_btn'),
                                        style: GoogleFonts.poppins(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12)),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 38,
                            child: ElevatedButton(
                              onPressed: (_isAccepting || _isRejecting)
                                  ? null
                                  : () async {
                                      setState(() => _isAccepting = true);
                                      await widget.onStatusUpdate(
                                          fullId, 'accepted');
                                      if (mounted)
                                        setState(() => _isAccepting = false);
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1B5E20),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(100)),
                                padding: EdgeInsets.zero,
                              ),
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                child: _isAccepting
                                    ? const SizedBox(
                                        height: 16,
                                        width: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white))
                                    : Text(FarmerText.get(context, 'accept'),
                                        key: const ValueKey('accept_btn'),
                                        style: GoogleFonts.poppins(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12)),
                              ),
                            ),
                          ),
                        ),
                      ],
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
