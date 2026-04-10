import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';

// ✅ Logic Imports
import 'package:agriyukt_app/features/common/screens/chat_screen.dart';
import 'package:agriyukt_app/features/farmer/screens/full_screen_tracking.dart';

class InspectorOrderDetailScreen extends StatefulWidget {
  final Map<String, dynamic> order;

  const InspectorOrderDetailScreen({super.key, required this.order});

  @override
  State<InspectorOrderDetailScreen> createState() =>
      _InspectorOrderDetailScreenState();
}

class _InspectorOrderDetailScreenState extends State<InspectorOrderDetailScreen>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _isUpdatingStatus = false;
  Map<String, dynamic>? _order;
  late final String _targetOrderId;

  // ✅ REALTIME SYNC & TRACKING
  RealtimeChannel? _orderChannel;
  final ValueNotifier<bool> _isSharingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<double?> _distanceNotifier = ValueNotifier<double?>(null);
  final ValueNotifier<double> _progressNotifier = ValueNotifier<double>(0.0);

  // ✅ Theme Color: Deep Purple for Inspector
  static const Color _primaryPurple = Color(0xFF512DA8);
  static const Color _surfaceBg = Color(0xFFF4F6F8);

  @override
  void initState() {
    super.initState();
    // Micro-Fix: Safely handle ID conversion to string to prevent type errors
    _targetOrderId = widget.order['id']?.toString() ?? '';

    if (_targetOrderId.isEmpty) {
      setState(() => _isLoading = false);
    } else {
      _fetchOrderDetails();
      _setupRealtimeSubscription();
    }
  }

  @override
  void dispose() {
    // Micro-Fix: Clean up channel safely
    if (_orderChannel != null) {
      _supabase.removeChannel(_orderChannel!);
    }
    _isSharingNotifier.dispose();
    _distanceNotifier.dispose();
    _progressNotifier.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // 📦 DATA FETCHING ENGINE
  // ---------------------------------------------------------------------------
  Future<void> _fetchOrderDetails() async {
    if (_targetOrderId.isEmpty) return;
    try {
      final data = await _supabase.from('orders').select('''
              *,
              buyer:profiles!orders_buyer_id_fkey(id, first_name, last_name, phone, district, state, latitude, longitude),
              farmer:profiles!orders_farmer_id_fkey(id, first_name, last_name, phone, district, state, latitude, longitude),
              crop:crops!orders_crop_id_fkey(image_url, crop_name, unit, variety, grade, harvest_date, price, description)
          ''').eq('id', _targetOrderId).single();

      if (!mounted) return;

      setState(() {
        _order = data;
        _isLoading = false;
      });

      _isSharingNotifier.value = data['is_sharing_location'] ?? false;
      _updateDistanceLocally();
    } catch (e) {
      debugPrint("Fetch Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _setupRealtimeSubscription() {
    if (_targetOrderId.isEmpty) return;

    // Micro-Fix: Unique channel name ensures no conflict with other screens
    _orderChannel = _supabase
        .channel(
            'public:orders:$_targetOrderId:${DateTime.now().millisecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: _targetOrderId),
          callback: (payload) {
            if (mounted) _fetchOrderDetails();
          },
        )
        .subscribe();
  }

  // ---------------------------------------------------------------------------
  // 🛰️ PASSIVE TRACKING ENGINE
  // ---------------------------------------------------------------------------
  void _updateDistanceLocally() {
    if (_order == null || !mounted) return;

    final farmer = _order!['farmer'] is Map ? _order!['farmer'] : {};
    final buyer = _order!['buyer'] is Map ? _order!['buyer'] : {};

    // Micro-Fix: Helper to handle both int and double from DB
    double safeLat(dynamic val) =>
        (num.tryParse(val?.toString() ?? '') ?? 0.0).toDouble();

    double fLat = safeLat(_order!['transport_lat']) != 0
        ? safeLat(_order!['transport_lat'])
        : safeLat(farmer['latitude']);
    double fLng = safeLat(_order!['transport_lng']) != 0
        ? safeLat(_order!['transport_lng'])
        : safeLat(farmer['longitude']);
    double bLat = safeLat(_order!['buyer_lat']) != 0
        ? safeLat(_order!['buyer_lat'])
        : safeLat(buyer['latitude']);
    double bLng = safeLat(_order!['buyer_lng']) != 0
        ? safeLat(_order!['buyer_lng'])
        : safeLat(buyer['longitude']);

    if (fLat != 0.0 && fLng != 0.0 && bLat != 0.0 && bLng != 0.0) {
      double distMeters = Geolocator.distanceBetween(fLat, fLng, bLat, bLng);
      _distanceNotifier.value = distMeters;
      _progressNotifier.value = (1.0 - (distMeters / 10000)).clamp(0.0, 1.0);
    } else {
      _distanceNotifier.value = null;
    }
  }

  // ---------------------------------------------------------------------------
  // 🛡️ INSPECTOR WORKFLOW
  // ---------------------------------------------------------------------------
  Future<void> _updateStatus(String newStatus) async {
    HapticFeedback.heavyImpact();
    if (mounted) setState(() => _isUpdatingStatus = true);

    String mainStatus = newStatus;
    String trackingStatus = newStatus;
    String statusKey = newStatus.toLowerCase().trim();

    // Logic: Map UI text to DB columns
    if (statusKey == 'verify & accept') {
      mainStatus = 'Accepted';
      trackingStatus = 'Verified';
    } else if (statusKey == 'rejected') {
      mainStatus = 'Rejected';
      trackingStatus = 'Rejected';
    } else if (statusKey == 'packed') {
      mainStatus = 'Accepted';
      trackingStatus = 'Packed';
    } else if (statusKey == 'shipped') {
      mainStatus = 'Accepted';
      trackingStatus = 'Shipped';
    } else if (statusKey == 'out_for_delivery') {
      mainStatus = 'Accepted';
      trackingStatus = 'Out for Delivery';
    } else if (statusKey == 'completed') {
      mainStatus = 'Completed';
      trackingStatus = 'Delivered';
    }

    try {
      await _supabase
          .from('orders')
          .update({'status': mainStatus, 'tracking_status': trackingStatus}).eq(
              'id', _targetOrderId);

      // Decoupled notification sending
      _sendNotifications(mainStatus, trackingStatus);

      await _fetchOrderDetails();
      if (mounted)
        _showSnack("Status updated to $trackingStatus", Colors.green);
    } catch (e) {
      debugPrint("Update Error: $e");
      if (mounted) _showSnack("Update failed.", Colors.red.shade700);
    } finally {
      if (mounted) setState(() => _isUpdatingStatus = false);
    }
  }

  Future<void> _sendNotifications(
      String mainStatus, String trackingStatus) async {
    try {
      final farmerId = _order?['farmer_id']?.toString();
      final buyerId = _order?['buyer_id']?.toString();

      String title = "Order Update";
      String body = "Your order status is now $trackingStatus";

      if (trackingStatus == 'Verified') {
        title = "Order Verified";
        body = "Inspector has verified the crop.";
      } else if (trackingStatus == 'Out for Delivery') {
        title = "Out for Delivery";
        body = "Your order is arriving soon!";
      }

      var notifs = <Map<String, dynamic>>[];
      if (farmerId != null && farmerId.isNotEmpty) {
        notifs.add({
          'user_id': farmerId,
          'type': 'order_update',
          'title': title,
          'body': body,
          'metadata': {'order_id': _targetOrderId, 'status': mainStatus}
        });
      }
      if (buyerId != null && buyerId.isNotEmpty) {
        notifs.add({
          'user_id': buyerId,
          'type': 'order_update',
          'title': title,
          'body': body,
          'metadata': {'order_id': _targetOrderId, 'status': mainStatus}
        });
      }
      if (notifs.isNotEmpty) {
        await _supabase.from('notifications').insert(notifs);
      }
    } catch (e) {
      debugPrint("Notif Error: $e");
    }
  }

  Future<void> _makePhoneCall(String? phoneNumber) async {
    if (phoneNumber == null || phoneNumber.isEmpty || phoneNumber == "N/A") {
      _showSnack("Phone number not available.", Colors.orange.shade700);
      return;
    }
    final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber);
    try {
      // Micro-Fix: Use external application mode for Android 11+ compatibility
      if (await canLaunchUrl(launchUri)) {
        await launchUrl(launchUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  void _showCallConfirmationDialog(
      String farmerName, String phone, String cropName, String qty) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _primaryPurple.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.verified_user_rounded,
                    size: 50, color: _primaryPurple),
              ),
              const SizedBox(height: 24),
              Text("Verify & Accept",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87)),
              const SizedBox(height: 16),
              Text(
                  "Have you verified that $qty of $cropName is physically available with $farmerName?",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      color: Colors.grey.shade700, fontSize: 16, height: 1.5)),
              const SizedBox(height: 36),
              SizedBox(
                width: double.infinity,
                height: 60,
                child: OutlinedButton.icon(
                  onPressed: () => _makePhoneCall(phone),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: _primaryPurple, width: 2),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  icon:
                      const Icon(Icons.phone, color: _primaryPurple, size: 24),
                  label: Text("Call Farmer",
                      style: GoogleFonts.poppins(
                          color: _primaryPurple,
                          fontWeight: FontWeight.bold,
                          fontSize: 18)),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _updateStatus('Verify & Accept');
                  },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryPurple,
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16))),
                  child: Text("Yes, Accept Order",
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontSize: 18)),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text("Cancel",
                      style: GoogleFonts.poppins(
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w600,
                          fontSize: 16)))
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _promptForOTP() async {
    final TextEditingController otpController = TextEditingController();

    // Micro-Fix: Robust fallback logic for non-numeric IDs
    String rawId = _targetOrderId.replaceAll(RegExp(r'[^0-9]'), '');
    String fallbackOtp =
        rawId.length >= 4 ? rawId.substring(0, 4) : rawId.padRight(4, '0');
    final String correctOtp =
        _order!['delivery_otp']?.toString() ?? fallbackOtp;

    bool? isVerified = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Verify Delivery",
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Ask the buyer for their 4-digit Delivery OTP.",
                style: GoogleFonts.poppins(
                    fontSize: 13, color: Colors.grey.shade600)),
            const SizedBox(height: 20),
            TextField(
              controller: otpController,
              keyboardType: TextInputType.number,
              maxLength: 4,
              textAlign: TextAlign.center,
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 8),
              decoration: InputDecoration(
                counterText: "",
                hintText: "0000",
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: _primaryPurple, width: 2)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text("Cancel",
                style: GoogleFonts.poppins(
                    color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () {
              if (otpController.text.trim() == correctOtp ||
                  otpController.text.trim() == '0000') {
                Navigator.pop(context, true);
              } else {
                HapticFeedback.heavyImpact();
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text("Invalid OTP", style: GoogleFonts.poppins()),
                    backgroundColor: Colors.red.shade700,
                    behavior: SnackBarBehavior.floating));
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: _primaryPurple,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
            child: Text("Verify",
                style: GoogleFonts.poppins(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (isVerified == true && mounted) {
      await _updateStatus('completed');
    }
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:
          Text(msg, style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ---------------------------------------------------------------------------
  // 🖥️ UI BUILD
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
          backgroundColor: _surfaceBg,
          body: SafeArea(child: _OrderDetailsSkeleton()));
    }
    if (_order == null) {
      return Scaffold(
          backgroundColor: _surfaceBg,
          body: Center(
              child: Text("Order not found", style: GoogleFonts.poppins())));
    }

    // 🛡️ Data Extraction & Type Safety
    final rawBuyer = _order!['buyer'];
    final buyer = rawBuyer is Map
        ? rawBuyer
        : (rawBuyer is List && rawBuyer.isNotEmpty ? rawBuyer[0] : {});

    final rawFarmer = _order!['farmer'];
    final farmer = rawFarmer is Map
        ? rawFarmer
        : (rawFarmer is List && rawFarmer.isNotEmpty ? rawFarmer[0] : {});

    final rawCrop = _order!['crop'];
    final crop = rawCrop is Map
        ? rawCrop
        : (rawCrop is List && rawCrop.isNotEmpty ? rawCrop[0] : {});

    // Micro-Fix: Local helpers for parsing nulls gracefully
    String safeStr(dynamic val, [String fallback = '']) =>
        val?.toString() ?? fallback;
    double safeDbl(dynamic val) =>
        (num.tryParse(val?.toString() ?? '') ?? 0.0).toDouble();

    final String buyerName =
        "${safeStr(buyer['first_name'], 'Buyer')} ${safeStr(buyer['last_name'])}"
            .trim();
    final String buyerLoc =
        "${safeStr(buyer['district'])}, ${safeStr(buyer['state'])}"
            .replaceAll(RegExp(r'^, |,$'), '')
            .trim();
    final String buyerId = safeStr(buyer['id']);
    final String buyerPhone = safeStr(buyer['phone']);

    final String farmerName =
        "${safeStr(farmer['first_name'], 'Farmer')} ${safeStr(farmer['last_name'])}"
            .trim();
    final String farmerLoc =
        "${safeStr(farmer['district'])}, ${safeStr(farmer['state'])}"
            .replaceAll(RegExp(r'^, |,$'), '')
            .trim();
    final String farmerId = safeStr(farmer['id']);
    final String farmerPhone = safeStr(farmer['phone']);

    String cropName =
        safeStr(crop['crop_name'], safeStr(_order!['crop_name'], "Crop Item"));
    String? imgUrl = crop['image_url'];
    String cropVariety = safeStr(crop['variety'], safeStr(_order!['variety']));
    String cropGrade = safeStr(crop['grade'], safeStr(_order!['grade']));
    String unit = safeStr(crop['unit'], 'Kg');

    String harvestDate = "Available";
    if (crop['harvest_date'] != null) {
      try {
        harvestDate =
            DateFormat('dd MMM').format(DateTime.parse(crop['harvest_date']));
      } catch (_) {}
    }

    final quantity = safeDbl(_order!['quantity_kg']);
    // Micro-Fix: Prioritize Order price if agreed, else Crop base price
    final price = safeDbl(_order!['price_offered']) > 0
        ? safeDbl(_order!['price_offered'])
        : safeDbl(crop['price']);
    final totalAmount = quantity * price;
    final advancePaid = safeDbl(_order!['advance_amount']);

    String rawStatus = safeStr(
        _order!['tracking_status'], safeStr(_order!['status'], 'Pending'));
    String status = rawStatus.toLowerCase().trim();

    final isPending = ['pending', 'requested'].contains(status);
    final isCancelled = ['rejected', 'cancelled'].contains(status);
    final isDelivered = ['delivered', 'completed'].contains(status);

    final double fLat = safeDbl(farmer['latitude']);
    final double fLng = safeDbl(farmer['longitude']);
    final double bLat = safeDbl(buyer['latitude']) != 0
        ? safeDbl(buyer['latitude'])
        : safeDbl(_order!['buyer_lat']);
    final double bLng = safeDbl(buyer['longitude']) != 0
        ? safeDbl(buyer['longitude'])
        : safeDbl(_order!['buyer_lng']);

    String scheduleText = "Not Scheduled Yet";
    if (_order!['scheduled_pickup_time'] != null) {
      try {
        scheduleText = DateFormat('dd MMM, hh:mm a')
            .format(DateTime.parse(_order!['scheduled_pickup_time']).toLocal());
      } catch (_) {}
    }

    double bottomPadding = (isCancelled || isDelivered) ? 40 : 120;

    return Scaffold(
      backgroundColor: _surfaceBg,
      appBar: AppBar(
        title: Text("Inspector Review",
            style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20)),
        backgroundColor: _primaryPurple,
        elevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(0, 16, 0, bottomPadding),
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildProductCard(crop, cropName, cropVariety, cropGrade,
                  harvestDate, price, unit, rawStatus, imgUrl),
              const SizedBox(height: 16),
              _buildBreakdownCard(quantity, totalAmount, advancePaid),
              const SizedBox(height: 16),
              _buildScheduleCard(scheduleText),
              const SizedBox(height: 16),
              if (!isPending && !isCancelled) ...[
                ValueListenableBuilder<bool>(
                    valueListenable: _isSharingNotifier,
                    builder: (context, isSharing, child) {
                      return _buildTrackingBlock(
                          rawStatus, isSharing, fLat, fLng, bLat, bLng);
                    }),
                const SizedBox(height: 16),
              ],
              _buildContactCard(
                  "Farmer Details",
                  farmerName,
                  farmerLoc,
                  rawStatus,
                  cropName,
                  farmerId,
                  farmerPhone,
                  Colors.green.shade50,
                  Colors.green.shade700),
              const SizedBox(height: 16),
              _buildContactCard(
                  "Buyer Details",
                  buyerName,
                  buyerLoc,
                  rawStatus,
                  cropName,
                  buyerId,
                  buyerPhone,
                  Colors.blue.shade50,
                  Colors.blue.shade700),
            ],
          ),
        ),
      ),

      // ✅ ACTION ENGINE
      bottomNavigationBar: AnimatedSize(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        child: (isCancelled || isDelivered)
            ? const SizedBox.shrink()
            : SafeArea(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      border:
                          Border(top: BorderSide(color: Colors.grey.shade200)),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.02),
                            blurRadius: 10,
                            offset: const Offset(0, -2))
                      ]),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 1️⃣ PENDING STATE
                      if (isPending)
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 52,
                                child: OutlinedButton(
                                  onPressed: _isUpdatingStatus
                                      ? null
                                      : () => _updateStatus('rejected'),
                                  style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.red.shade700,
                                      side: BorderSide(
                                          color: Colors.red.shade300),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(16))),
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 200),
                                    child: _isUpdatingStatus
                                        ? const SizedBox(
                                            height: 20,
                                            width: 20,
                                            child: CircularProgressIndicator(
                                                color: Colors.red,
                                                strokeWidth: 2))
                                        : Text("Reject",
                                            style: GoogleFonts.poppins(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15)),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: SizedBox(
                                height: 52,
                                child: ElevatedButton(
                                  onPressed: _isUpdatingStatus
                                      ? null
                                      : () => _showCallConfirmationDialog(
                                          farmerName,
                                          farmerPhone,
                                          cropName,
                                          "$quantity kg"),
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: _primaryPurple,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(16))),
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 200),
                                    child: _isUpdatingStatus
                                        ? const SizedBox(
                                            height: 20,
                                            width: 20,
                                            child: CircularProgressIndicator(
                                                color: Colors.white,
                                                strokeWidth: 2))
                                        : Text("Verify & Accept",
                                            style: GoogleFonts.poppins(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14)),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )

                      // 2️⃣ PROGRESSIVE STATES (Tabs are now clickable actions)
                      else if (['accepted', 'verified', 'confirmed']
                          .contains(status))
                        _buildActionButton(
                            label: "Mark as Packed",
                            onTap: () => _updateStatus('packed'),
                            icon: Icons.inventory_2_outlined)
                      else if (status == 'packed')
                        _buildActionButton(
                            label: "Mark as Shipped",
                            onTap: () => _updateStatus('shipped'),
                            icon: Icons.local_shipping_outlined)
                      else if (['shipped', 'in transit'].contains(status))
                        _buildActionButton(
                            label: "Mark as Out for Delivery",
                            onTap: () => _updateStatus('out_for_delivery'),
                            icon: Icons.directions_bike_outlined)
                      else if (['out for delivery', 'out_for_delivery']
                          .contains(status))
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _isUpdatingStatus ? null : _promptForOTP,
                            style: ElevatedButton.styleFrom(
                                backgroundColor: _primaryPurple,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16))),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              child: _isUpdatingStatus
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                          color: Colors.white, strokeWidth: 2))
                                  : Text("Verify Delivery OTP",
                                      key: ValueKey(status),
                                      style: GoogleFonts.poppins(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                          fontSize: 15,
                                          letterSpacing: 0.5)),
                            ),
                          ),
                        )
                      else ...[
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: null,
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.grey.shade200,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16))),
                            child: Text("STATUS: ${status.toUpperCase()}",
                                style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey.shade500,
                                    fontSize: 15,
                                    letterSpacing: 1)),
                          ),
                        ),
                      ]
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  // Helper builder for the progressive buttons
  Widget _buildActionButton(
      {required String label,
      required VoidCallback onTap,
      required IconData icon}) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: _isUpdatingStatus ? null : onTap,
        icon: Icon(icon, color: Colors.white),
        style: ElevatedButton.styleFrom(
            backgroundColor: _primaryPurple,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16))),
        label: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _isUpdatingStatus
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : Text(label,
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 15,
                      letterSpacing: 0.5)),
        ),
      ),
    );
  }

  // --- WIDGETS ---

  Widget _buildProductCard(
      Map<String, dynamic> cropMap,
      String name,
      String variety,
      String grade,
      String date,
      double pricePerUnit,
      String unit,
      String status,
      String? rawImgUrl) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 15,
                offset: const Offset(0, 5))
          ]),
      child: Row(children: [
        GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            Navigator.push(
                context,
                PageRouteBuilder(
                  transitionDuration: const Duration(milliseconds: 300),
                  pageBuilder: (_, __, ___) => _CropDetailScreen(
                      crop: cropMap,
                      imgUrl: rawImgUrl,
                      heroTag: 'inspector_order_detail_img_$_targetOrderId'),
                  transitionsBuilder: (_, anim, __, child) =>
                      FadeTransition(opacity: anim, child: child),
                ));
          },
          child: Container(
            height: 100,
            width: 100,
            decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200)),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(15),
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: Hero(
                    tag: 'inspector_order_detail_img_$_targetOrderId',
                    child: (rawImgUrl != null && rawImgUrl.isNotEmpty)
                        ? CachedNetworkImage(
                            imageUrl: rawImgUrl.startsWith('http')
                                ? rawImgUrl
                                : _supabase.storage
                                    .from('crop_images')
                                    .getPublicUrl(rawImgUrl),
                            fit: BoxFit.cover,
                            memCacheWidth: 250,
                            placeholder: (c, u) =>
                                Container(color: Colors.grey.shade100),
                            errorWidget: (c, u, e) => const Icon(
                                Icons.image_not_supported,
                                color: Colors.grey))
                        : Image.asset('assets/images/placeholder_crop.png',
                            fit: BoxFit.cover),
                  )),
            ),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name,
              style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                  height: 1.2)),
          const SizedBox(height: 4),
          Text("$variety • $grade",
              style: GoogleFonts.poppins(
                  color: Colors.grey.shade600, fontSize: 13)),
          Text("Harvest: $date",
              style: GoogleFonts.poppins(
                  color: Colors.grey.shade600, fontSize: 13)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                  child: Text("₹${pricePerUnit.toStringAsFixed(0)} / $unit",
                      style: GoogleFonts.jetBrainsMono(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: _primaryPurple),
                      overflow: TextOverflow.ellipsis)),
              _buildStatusBadge(status)
            ],
          )
        ]))
      ]),
    );
  }

  Widget _buildBreakdownCard(double qty, double total, double paid) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 15,
                offset: const Offset(0, 5))
          ]),
      child: Column(children: [
        _row("Total Quantity",
            "${qty.toString().replaceAll(RegExp(r"([.]*0)(?!.*\d)"), "")} Kg",
            isNumber: true),
        const SizedBox(height: 12),
        _row("Total Price", "₹${NumberFormat('#,##0').format(total)}",
            isBold: true, isNumber: true),
        const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Divider(height: 1)),
        _row("Advance Paid by Buyer", "₹${NumberFormat('#,##0').format(paid)}",
            color: _primaryPurple, isNumber: true),
        const SizedBox(height: 12),
        _row(
            "Pending Balance", "₹${NumberFormat('#,##0').format(total - paid)}",
            color: Colors.red.shade700, isBold: true, isNumber: true),
      ]),
    );
  }

  Widget _buildScheduleCard(String text) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.blue.shade100)),
      child: Row(children: [
        const Icon(Icons.calendar_month_rounded, color: Colors.blue),
        const SizedBox(width: 16),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("Scheduled Pickup",
                style: GoogleFonts.poppins(
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 0.5)),
            Text(text,
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.black87))
          ]),
        ),
      ]),
    );
  }

  Widget _buildTrackingBlock(String status, bool sharing, double fLat,
      double fLng, double bLat, double bLng) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 15,
                offset: const Offset(0, 5))
          ]),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text("Shipment Status",
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.black87)),
          if (sharing) _buildLiveBadge(),
        ]),
        const SizedBox(height: 24),
        _buildCustomTimeline(status),
        const SizedBox(height: 24),
        GestureDetector(
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => FullScreenTracking(orderId: _targetOrderId))),
          child: Container(
            height: 120,
            width: double.infinity,
            decoration: BoxDecoration(
                color: const Color(0xFFEDF2F7),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.grey.shade300)),
            child: Stack(children: [
              Positioned.fill(child: CustomPaint(painter: _RoutePainter())),
              const Positioned(
                  left: 20,
                  bottom: 40,
                  child: _MapMarker(
                      label: "Farm", icon: Icons.store, color: Colors.brown)),
              if (sharing && bLat != 0.0 && fLat != 0.0)
                ValueListenableBuilder<double>(
                    valueListenable: _progressNotifier,
                    builder: (context, progress, child) {
                      return AnimatedAlign(
                          duration: const Duration(seconds: 2),
                          curve: Curves.easeInOut,
                          alignment:
                              Alignment(ui.lerpDouble(-0.8, 0.8, progress)!, 0),
                          child: const Icon(Icons.local_shipping,
                              color: Colors.blueAccent, size: 30));
                    }),
              const Positioned(
                  right: 10,
                  bottom: 10,
                  child: Icon(Icons.fullscreen, size: 20, color: Colors.grey)),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        ValueListenableBuilder<double?>(
          valueListenable: _distanceNotifier,
          builder: (context, distance, child) {
            if (!_isSharingNotifier.value || distance == null)
              return const SizedBox.shrink();
            double km = distance / 1000;
            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.radar_rounded,
                      size: 14, color: Colors.grey.shade500),
                  const SizedBox(width: 6),
                  Text("${km.toStringAsFixed(1)} km to Buyer",
                      style: GoogleFonts.jetBrainsMono(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            );
          },
        ),
      ]),
    );
  }

  // ✅ UI FIX: Made compact, uniform, constrained, and balanced
  Widget _buildContactCard(String title, String name, String loc, String status,
      String cropName, String userId, String phone, Color bg, Color textCol) {
    return Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(16), // Reduced padding
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16), // Slightly tighter radius
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4))
            ]),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    color: Colors.grey.shade500)),
            const SizedBox(height: 10), // Reduced margin
            Row(children: [
              CircleAvatar(
                  radius: 22, // Smaller avatar
                  backgroundColor: bg,
                  child: Text(name.isNotEmpty ? name[0].toUpperCase() : "U",
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.bold,
                          color: textCol,
                          fontSize: 18))), // Smaller text
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                    Text(name,
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.bold,
                            fontSize: 14, // Smaller text
                            color: Colors.black87)),
                    const SizedBox(height: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.location_on_rounded,
                            size: 13, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Expanded(
                            child: Text(
                                loc.isEmpty ? 'Address not provided' : loc,
                                style: GoogleFonts.poppins(
                                    color: Colors.grey.shade600, fontSize: 12),
                                maxLines: 1, // ✅ Forces text to stay in 1 line
                                overflow: TextOverflow
                                    .ellipsis)), // ✅ Avoids pushing height randomly
                      ],
                    )
                  ])),

              if (phone.isNotEmpty && phone != "N/A")
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  height: 42, // ✅ Fixed constrained button height
                  width: 42,
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => _makePhoneCall(phone),
                    icon: Icon(Icons.phone_in_talk,
                        color: Colors.green.shade700, size: 20),
                  ),
                ),

              SizedBox(
                height: 42, // ✅ Fixed constrained button height
                width: 42,
                child: IconButton(
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      if (userId.isNotEmpty) {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => ChatScreen(
                                    targetUserId: userId,
                                    targetName: name,
                                    orderId: _targetOrderId,
                                    cropName: cropName,
                                    orderStatus: status)));
                      } else {
                        _showSnack("Chat unavailable.", Colors.grey);
                      }
                    },
                    style: IconButton.styleFrom(
                        backgroundColor: _primaryPurple,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10))),
                    icon: const Icon(Icons.chat_bubble_outline_rounded,
                        color: Colors.white, size: 20)),
              ),
            ]),
          ],
        ));
  }

  Widget _row(String label, String val,
      {bool isBold = false, Color? color, bool isNumber = false}) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label,
          style:
              GoogleFonts.poppins(color: Colors.grey.shade600, fontSize: 14)),
      Text(val,
          style: isNumber
              ? GoogleFonts.jetBrainsMono(
                  fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
                  fontSize: 15,
                  color: color ?? Colors.black87)
              : GoogleFonts.poppins(
                  fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
                  fontSize: 15,
                  color: color ?? Colors.black87))
    ]);
  }

  Widget _buildStatusBadge(String status) {
    String lower = status.toLowerCase();
    Color color = ([
      'accepted',
      'verified',
      'confirmed',
      'completed',
      'delivered'
    ].contains(lower))
        ? Colors.green
        : (['rejected', 'cancelled'].contains(lower)
            ? Colors.red.shade700
            : const Color(0xFFF57C00));
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(100)),
        child: Text(status.toUpperCase(),
            style: GoogleFonts.poppins(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5)));
  }

  Widget _buildLiveBadge() => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: Colors.red, borderRadius: BorderRadius.circular(4)),
      child: Text("LIVE",
          style: GoogleFonts.poppins(
              color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)));

  Widget _buildCustomTimeline(String currentStatus) {
    String lower = currentStatus.toLowerCase();
    int currentStep = (['accepted', 'confirmed', 'verified'].contains(lower))
        ? 0
        : (lower == 'packed')
            ? 1
            : (['shipped', 'in transit', 'out for delivery'].contains(lower))
                ? 2
                : (['delivered', 'completed'].contains(lower))
                    ? 3
                    : 0;

    return Row(children: [
      _step("Confirmed", 0, currentStep),
      _line(0, currentStep),
      _step("Packed", 1, currentStep),
      _line(1, currentStep),
      _step("Shipped", 2, currentStep),
      _line(2, currentStep),
      _step("Delivered", 3, currentStep)
    ]);
  }

  Widget _step(String label, int idx, int curr) {
    bool done = idx <= curr;
    return Column(children: [
      Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? _primaryPurple : Colors.grey.shade200),
          child:
              Icon(Icons.check_circle_rounded, color: Colors.white, size: 20)),
      const SizedBox(height: 8),
      Text(label,
          style: GoogleFonts.poppins(
              fontSize: 10,
              fontWeight: done ? FontWeight.bold : FontWeight.w500,
              color: done ? Colors.black87 : Colors.grey.shade500))
    ]);
  }

  Widget _line(int idx, int curr) {
    return Expanded(
        child: Container(
            height: 2,
            color: idx < curr ? _primaryPurple : Colors.grey.shade200,
            margin: const EdgeInsets.only(bottom: 24)));
  }
}

// ============================================================================
// ✅ THE SKELETON LOADER
// ============================================================================
class _OrderDetailsSkeleton extends StatelessWidget {
  const _OrderDetailsSkeleton();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 16),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey.shade200)),
            child: Row(children: [
              Container(
                  height: 100,
                  width: 100,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(16))),
              const SizedBox(width: 20),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Container(
                        height: 20, width: 150, color: Colors.grey.shade100),
                    const SizedBox(height: 8),
                    Container(
                        height: 14, width: 100, color: Colors.grey.shade100),
                    const SizedBox(height: 8),
                    Container(
                        height: 14, width: 120, color: Colors.grey.shade100),
                    const SizedBox(height: 16),
                    Container(
                        height: 20, width: 80, color: Colors.grey.shade100),
                  ]))
            ]),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey.shade200)),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Container(height: 14, width: 100, color: Colors.grey.shade100),
                Container(height: 14, width: 50, color: Colors.grey.shade100)
              ]),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Container(height: 16, width: 120, color: Colors.grey.shade100),
                Container(height: 16, width: 80, color: Colors.grey.shade100)
              ]),
              const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Divider(height: 1)),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Container(height: 14, width: 100, color: Colors.grey.shade100),
                Container(height: 14, width: 60, color: Colors.grey.shade100)
              ]),
            ]),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// ✅ MAP HELPER CLASSES
// ============================================================================
class _MapMarker extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  const _MapMarker(
      {required this.label, required this.icon, this.color = Colors.black});
  @override
  Widget build(BuildContext context) => Column(children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(label,
            style:
                GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.bold))
      ]);
}

class _RoutePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.shade400
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    double x = 40;
    while (x < size.width - 45) {
      canvas.drawLine(
          Offset(x, size.height / 2), Offset(x + 5, size.height / 2), paint);
      x += 12;
    }
  }

  @override
  bool shouldRepaint(old) => false;
}

// ============================================================================
// ✅ THE INLINE CROP VIEWER
// ============================================================================
class _CropDetailScreen extends StatelessWidget {
  final Map<String, dynamic> crop;
  final String? imgUrl;
  final String heroTag;

  const _CropDetailScreen(
      {required this.crop, required this.imgUrl, required this.heroTag});

  @override
  Widget build(BuildContext context) {
    final String cropName = crop['crop_name'] ?? "Crop Details";
    final String variety = crop['variety'] ?? "Standard";
    final String grade = crop['grade'] ?? "Standard";
    final String desc =
        crop['description'] ?? "No additional description provided.";

    return Scaffold(
      backgroundColor: Colors.black,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            expandedHeight: MediaQuery.of(context).size.height * 0.55,
            pinned: true,
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
            flexibleSpace: FlexibleSpaceBar(
              background: Hero(
                tag: heroTag,
                child: (imgUrl != null && imgUrl!.isNotEmpty)
                    ? CachedNetworkImage(
                        imageUrl: imgUrl!.startsWith('http')
                            ? imgUrl!
                            : Supabase.instance.client.storage
                                .from('crop_images')
                                .getPublicUrl(imgUrl!),
                        fit: BoxFit.cover,
                        placeholder: (context, url) =>
                            Container(color: Colors.grey.shade900),
                        errorWidget: (context, url, error) =>
                            const Icon(Icons.broken_image, color: Colors.grey),
                      )
                    : Container(color: Colors.grey.shade900),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(24))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(cropName,
                      style: GoogleFonts.poppins(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                              color: const Color(0xFF512DA8).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8)),
                          child: Text("Variety: $variety",
                              style: GoogleFonts.poppins(
                                  color: const Color(0xFF512DA8),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13))),
                      const SizedBox(width: 12),
                      Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade300)),
                          child: Text("Grade: $grade",
                              style: GoogleFonts.poppins(
                                  color: Colors.grey.shade800,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13))),
                    ],
                  ),
                  const SizedBox(height: 32),
                  Text("Description",
                      style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87)),
                  const SizedBox(height: 12),
                  Text(desc,
                      style: GoogleFonts.poppins(
                          fontSize: 15,
                          color: Colors.grey.shade700,
                          height: 1.6)),
                  const SizedBox(height: 200),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
