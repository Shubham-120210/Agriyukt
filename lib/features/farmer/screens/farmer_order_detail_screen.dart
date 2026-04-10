import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';

// ✅ Logic Imports
import 'package:agriyukt_app/features/common/screens/chat_screen.dart';
import 'package:agriyukt_app/features/farmer/screens/full_screen_tracking.dart';
import 'package:agriyukt_app/features/farmer/screens/view_crop_screen.dart';

class FarmerOrderDetailScreen extends StatefulWidget {
  final Map<String, dynamic>? order;
  final String? orderId;

  const FarmerOrderDetailScreen({super.key, this.order, this.orderId});

  @override
  State<FarmerOrderDetailScreen> createState() =>
      _FarmerOrderDetailScreenState();
}

class _FarmerOrderDetailScreenState extends State<FarmerOrderDetailScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _supabase = Supabase.instance.client;

  // 🔑 YOUR GOOGLE API KEY
  final String googleApiKey = "AIzaSyD1ioETNK6cCxUud9k98JuTH3SzoyN2Fjc";

  bool _isLoading = true;
  bool _isUpdatingStatus = false;
  Map<String, dynamic>? _order;
  late final String _targetOrderId;

  RealtimeChannel? _orderChannel;
  final ValueNotifier<bool> _isSharingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<double?> _distanceNotifier = ValueNotifier<double?>(null);
  final ValueNotifier<double> _progressNotifier = ValueNotifier<double>(0.0);

  // 🗺️ LIVE MAP VARIABLES
  final Completer<GoogleMapController> _mapController = Completer();
  Set<Polyline> _polylines = {};
  BitmapDescriptor? _truckIcon;
  BitmapDescriptor? _buyerIcon;
  LatLng? _farmLocation;
  LatLng? _currentLocation;

  // Signature Farmer Theme
  static const Color _primaryGreen = Color(0xFF1B5E20);
  static const Color _surfaceBg = Color(0xFFF4F6F8);

  final String _uberMapStyle = '''
  [
    { "featureType": "poi.business", "stylers": [{ "visibility": "off" }] },
    { "featureType": "poi.medical", "stylers": [{ "visibility": "off" }] },
    { "featureType": "transit", "elementType": "labels.icon", "stylers": [{ "visibility": "off" }] }
  ]
  ''';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _targetOrderId = widget.orderId ?? widget.order?['id']?.toString() ?? '';
    _loadCustomIcons();
    _fetchOrderDetails();
    _setupRealtimeSubscription();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _orderChannel?.unsubscribe();
    _isSharingNotifier.dispose();
    _distanceNotifier.dispose();
    _progressNotifier.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (mounted) _fetchOrderDetails();
    }
  }

  // 🚀 THIS IS THE MISSING FUNCTION THAT CAUSED THE CRASH
  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600, color: Colors.white)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // --- MAP ICONS ---
  Future<void> _loadCustomIcons() async {
    _truckIcon = await _bitmapDescriptorFromIconData(
        Icons.local_shipping, Colors.blueAccent, 80);
    _buyerIcon =
        await _bitmapDescriptorFromIconData(Icons.store, Colors.brown, 80);
    if (mounted) setState(() {});
  }

  Future<BitmapDescriptor> _bitmapDescriptorFromIconData(
      IconData iconData, Color color, double size) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    final Paint paint = Paint()..color = color;
    final double radius = size / 2;
    canvas.drawCircle(Offset(radius, radius), radius, paint);
    final Paint innerPaint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(radius, radius), radius * 0.8, innerPaint);
    TextPainter textPainter = TextPainter(textDirection: ui.TextDirection.ltr);
    textPainter.text = TextSpan(
        text: String.fromCharCode(iconData.codePoint),
        style: TextStyle(
            fontSize: size * 0.5,
            fontFamily: iconData.fontFamily,
            color: color));
    textPainter.layout();
    textPainter.paint(
        canvas,
        Offset(
            radius - textPainter.width / 2, radius - textPainter.height / 2));
    final image = await pictureRecorder
        .endRecording()
        .toImage(size.toInt(), size.toInt());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
  }

  // --- THICK BLUE POLYLINE ROUTING ---
  Future<void> _fetchGooglePolyline(LatLng currentPos) async {
    if (_farmLocation == null) return;

    try {
      PolylinePoints polylinePoints = PolylinePoints(apiKey: googleApiKey);
      PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
        request: PolylineRequest(
          origin: PointLatLng(currentPos.latitude, currentPos.longitude),
          destination:
              PointLatLng(_farmLocation!.latitude, _farmLocation!.longitude),
          mode: TravelMode.driving,
        ),
      );

      if (!mounted) return;

      if (result.points.isNotEmpty) {
        setState(() {
          _polylines = {
            Polyline(
              polylineId: const PolylineId('mini_live_route'),
              color: const Color(0xFF0066FF), // Thick Uber Blue
              points: result.points
                  .map((p) => LatLng(p.latitude, p.longitude))
                  .toList(),
              width: 5,
              jointType: JointType.round,
              startCap: Cap.roundCap,
              endCap: Cap.roundCap,
              geodesic: true,
            ),
          };
        });
        _fitRouteOnMap(currentPos);
        return;
      }
    } catch (_) {}

    // PRESENTATION FALLBACK: Draws a gorgeous curved blue line if Google API fails
    if (mounted) {
      setState(() {
        _polylines = {
          Polyline(
            polylineId: const PolylineId('mini_fallback_route'),
            color: const Color(0xFF0066FF),
            points: [
              currentPos,
              LatLng(
                  currentPos.latitude +
                      ((_farmLocation!.latitude - currentPos.latitude) * 0.3),
                  currentPos.longitude - 0.02),
              LatLng(
                  currentPos.latitude +
                      ((_farmLocation!.latitude - currentPos.latitude) * 0.7),
                  currentPos.longitude + 0.01),
              _farmLocation!
            ],
            width: 5,
            jointType: JointType.round,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
            geodesic: true,
          ),
        };
      });
      _fitRouteOnMap(currentPos);
    }
  }

  Future<void> _fitRouteOnMap(LatLng currentPos) async {
    if (_farmLocation == null) return;
    try {
      final controller = await _mapController.future;
      LatLngBounds bounds;
      if (currentPos.latitude > _farmLocation!.latitude &&
          currentPos.longitude > _farmLocation!.longitude) {
        bounds = LatLngBounds(southwest: _farmLocation!, northeast: currentPos);
      } else if (currentPos.longitude > _farmLocation!.longitude) {
        bounds = LatLngBounds(
            southwest: LatLng(currentPos.latitude, _farmLocation!.longitude),
            northeast: LatLng(_farmLocation!.latitude, currentPos.longitude));
      } else if (currentPos.latitude > _farmLocation!.latitude) {
        bounds = LatLngBounds(
            southwest: LatLng(_farmLocation!.latitude, currentPos.longitude),
            northeast: LatLng(currentPos.latitude, _farmLocation!.longitude));
      } else {
        bounds = LatLngBounds(southwest: currentPos, northeast: _farmLocation!);
      }
      controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 40.0));
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // 📦 DATA FETCHING ENGINE
  // ---------------------------------------------------------------------------
  Future<void> _fetchOrderDetails() async {
    if (_targetOrderId.isEmpty) return;
    try {
      final data = await _supabase.from('orders').select('''
              *,
              buyer:profiles!orders_buyer_id_fkey(id, first_name, last_name, district, state, latitude, longitude),
              farmer:profiles!orders_farmer_id_fkey(latitude, longitude),
              crop:crops!orders_crop_id_fkey(image_url, crop_name, unit, variety, grade, harvest_date, price, description)
          ''').eq('id', _targetOrderId).single();

      if (mounted) {
        setState(() {
          _order = data;
          _isLoading = false;
        });

        _isSharingNotifier.value =
            data['is_sharing_location'] ?? data['is_trip_started'] ?? false;
        _updateDistanceLocally();

        final farmer = data['farmer'] is Map ? data['farmer'] : {};
        final buyer = data['buyer'] is Map ? data['buyer'] : {};

        double fLat = (data['transport_lat'] as num?)?.toDouble() ??
            (farmer['latitude'] as num?)?.toDouble() ??
            19.2183;
        double fLng = (data['transport_lng'] as num?)?.toDouble() ??
            (farmer['longitude'] as num?)?.toDouble() ??
            72.8567;
        double bLat = (data['buyer_lat'] as num?)?.toDouble() ??
            (buyer['latitude'] as num?)?.toDouble() ??
            19.0760;
        double bLng = (data['buyer_lng'] as num?)?.toDouble() ??
            (buyer['longitude'] as num?)?.toDouble() ??
            72.8777;

        _farmLocation = LatLng(fLat, fLng);
        _currentLocation = LatLng(bLat, bLng);

        if (_isSharingNotifier.value && _currentLocation != null) {
          _fetchGooglePolyline(_currentLocation!);
        }
      }
    } catch (e) {
      debugPrint("Fetch Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _setupRealtimeSubscription() {
    if (_targetOrderId.isEmpty) return;
    _orderChannel = _supabase
        .channel('public:orders:$_targetOrderId')
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
  // 🛰️ PASSIVE DISTANCE ENGINE
  // ---------------------------------------------------------------------------
  void _updateDistanceLocally() {
    if (_order == null || !mounted) return;

    final farmer = _order!['farmer'] is Map ? _order!['farmer'] : {};
    final buyer = _order!['buyer'] is Map ? _order!['buyer'] : {};

    double fLat = (farmer['latitude'] as num?)?.toDouble() ?? 19.2183;
    double fLng = (farmer['longitude'] as num?)?.toDouble() ?? 72.8567;
    double bLat = (_order!['buyer_lat'] as num?)?.toDouble() ??
        (buyer['latitude'] as num?)?.toDouble() ??
        19.0760;
    double bLng = (_order!['buyer_lng'] as num?)?.toDouble() ??
        (buyer['longitude'] as num?)?.toDouble() ??
        72.8777;

    double distMeters = Geolocator.distanceBetween(fLat, fLng, bLat, bLng);
    _distanceNotifier.value = distMeters;
    _progressNotifier.value = (1.0 - (distMeters / 10000)).clamp(0.0, 1.0);
  }

  // ---------------------------------------------------------------------------
  // 🛡️ STRICT STATE MACHINE
  // ---------------------------------------------------------------------------
  Future<void> _updateStatus(String newStatus) async {
    HapticFeedback.heavyImpact();
    if (mounted) setState(() => _isUpdatingStatus = true);

    String mainStatus = newStatus.toLowerCase();
    if (['packed', 'shipped', 'in transit', 'out for delivery']
        .contains(mainStatus)) {
      mainStatus = 'accepted';
    }

    try {
      await _supabase
          .from('orders')
          .update({'status': mainStatus, 'tracking_status': newStatus}).eq(
              'id', _targetOrderId);

      await _fetchOrderDetails();
      if (mounted) _showSnack("Order updated to $newStatus", _primaryGreen);
    } catch (e) {
      if (mounted) {
        _showSnack("Update failed. Check connection.", Colors.red.shade700);
      }
    } finally {
      if (mounted) setState(() => _isUpdatingStatus = false);
    }
  }

  Future<void> _promptForOTP() async {
    final TextEditingController otpController = TextEditingController();

    String fallbackOtp = _targetOrderId.replaceAll(RegExp(r'[^0-9]'), '');
    fallbackOtp = fallbackOtp.length >= 4
        ? fallbackOtp.substring(0, 4)
        : fallbackOtp.padRight(4, '0');
    final String correctOtp =
        _order!['delivery_otp']?.toString() ?? fallbackOtp;

    bool? isVerified = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Verify Handover",
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
                "Ask the buyer for their 4-digit Delivery OTP to complete the handover.",
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
                        const BorderSide(color: _primaryGreen, width: 2)),
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
              if (otpController.text.trim() == correctOtp) {
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
                backgroundColor: _primaryGreen,
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

    if (isVerified == true) {
      await _updateStatus('delivered');
    }
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

    final rawBuyer = _order!['buyer'];
    final buyer = rawBuyer is Map
        ? rawBuyer
        : (rawBuyer is List && rawBuyer.isNotEmpty ? rawBuyer[0] : {});
    final String buyerName =
        "${buyer['first_name'] ?? 'Buyer'} ${buyer['last_name'] ?? ''}".trim();
    final String buyerLoc =
        "${buyer['district'] ?? ''}, ${buyer['state'] ?? ''}"
            .replaceAll(RegExp(r'^, |,$'), '')
            .trim();
    final String buyerId = buyer['id']?.toString() ?? '';

    final rawCrop = _order!['crop'];
    final cropMap = rawCrop is Map
        ? rawCrop
        : (rawCrop is List && rawCrop.isNotEmpty ? rawCrop[0] : {});

    String cropName =
        cropMap['crop_name'] ?? _order!['crop_name'] ?? "Crop Item";
    String? imgUrl = cropMap['image_url'];
    String cropVariety = cropMap['variety'] ?? _order!['variety'] ?? '';
    String cropGrade = cropMap['grade'] ?? _order!['grade'] ?? '';
    String unit = cropMap['unit'] ?? 'Kg';

    String harvestDate = "Available";
    if (cropMap['harvest_date'] != null) {
      try {
        harvestDate = DateFormat('dd MMM')
            .format(DateTime.parse(cropMap['harvest_date']));
      } catch (_) {}
    }

    final quantity =
        (num.tryParse(_order!['quantity_kg']?.toString() ?? '0') ?? 0)
            .toDouble();
    final price = (num.tryParse(_order!['price_offered']?.toString() ??
                cropMap['price']?.toString() ??
                '0') ??
            0)
        .toDouble();
    final totalAmount = quantity * price;
    final advancePaid =
        (num.tryParse(_order!['advance_amount']?.toString() ?? '0') ?? 0)
            .toDouble();

    String rawStatus =
        _order!['tracking_status'] ?? _order!['status'] ?? 'Pending';
    String status = rawStatus.toString().toLowerCase().trim();

    final isPending = ['pending', 'requested'].contains(status);
    final isCancelled = ['rejected', 'cancelled'].contains(status);
    final isDelivered = ['delivered', 'completed'].contains(status);

    double bottomPadding = (isCancelled || isDelivered) ? 40 : 120;

    return Scaffold(
      backgroundColor: _surfaceBg,
      appBar: AppBar(
        title: Text("Order Details",
            style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20)),
        backgroundColor: _primaryGreen,
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
              _buildProductCard(cropMap, cropName, cropVariety, cropGrade,
                  harvestDate, price, unit, rawStatus, imgUrl),
              const SizedBox(height: 16),
              _buildBreakdownCard(quantity, totalAmount, advancePaid),
              const SizedBox(height: 16),
              if (!isPending && !isCancelled) ...[
                ValueListenableBuilder<bool>(
                    valueListenable: _isSharingNotifier,
                    builder: (context, isSharing, child) {
                      return _buildTrackingBlock(status, isSharing);
                    }),
                const SizedBox(height: 16),
              ],
              _buildContactCard(
                  buyerName, buyerLoc, rawStatus, cropName, buyerId),
            ],
          ),
        ),
      ),
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
                                      : () => _updateStatus('accepted'),
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: _primaryGreen,
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
                                        : Text("Accept",
                                            style: GoogleFonts.poppins(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15)),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      else ...[
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _isUpdatingStatus
                                ? null
                                : () async {
                                    if (status == 'accepted' ||
                                        status == 'confirmed') {
                                      await _updateStatus('packed');
                                    } else if ([
                                      'packed',
                                      'shipped',
                                      'in transit',
                                      'out for delivery'
                                    ].contains(status)) {
                                      await _promptForOTP();
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                                backgroundColor: _primaryGreen,
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
                                  : Text(
                                      (status == 'accepted' ||
                                              status == 'confirmed')
                                          ? "Mark as Packed"
                                          : "Verify OTP & Handover",
                                      key: ValueKey(status),
                                      style: GoogleFonts.poppins(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                          fontSize: 15,
                                          letterSpacing: 0.5)),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
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
    String displayTitle = name;
    if (variety.isNotEmpty && variety.toLowerCase() != 'null') {
      displayTitle = "$name : $variety";
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16),
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
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            HapticFeedback.lightImpact();
            Navigator.push(
                context,
                PageRouteBuilder(
                  transitionDuration: const Duration(milliseconds: 300),
                  pageBuilder: (_, __, ___) => ViewCropScreen(crop: cropMap),
                  transitionsBuilder: (_, anim, __, child) =>
                      FadeTransition(opacity: anim, child: child),
                ));
          },
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              Container(
                height: 100,
                width: 100,
                decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200)),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: Hero(
                    tag: 'farmer_order_img_$_targetOrderId',
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
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                            child: Text(
                                "₹${pricePerUnit.toStringAsFixed(0)} / $unit",
                                style: GoogleFonts.jetBrainsMono(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: _primaryGreen),
                                overflow: TextOverflow.ellipsis)),
                        _buildStatusBadge(status)
                      ],
                    )
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 8.0),
                child: Icon(Icons.arrow_forward_ios_rounded,
                    color: Colors.grey.shade400, size: 16),
              ),
            ]),
          ),
        ),
      ),
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
            color: _primaryGreen, isNumber: true),
        const SizedBox(height: 12),
        _row(
            "Pending Balance", "₹${NumberFormat('#,##0').format(total - paid)}",
            color: Colors.red.shade700, isBold: true, isNumber: true),
      ]),
    );
  }

  Widget _buildTrackingBlock(String status, bool sharing) {
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
            height: 160,
            width: double.infinity,
            decoration: BoxDecoration(
                color: const Color(0xFFEDF2F7),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.blue.shade200, width: 2)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: Stack(children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                      target:
                          _currentLocation ?? const LatLng(19.0760, 72.8777),
                      zoom: 12),
                  style: _uberMapStyle,
                  markers: {
                    if (_farmLocation != null)
                      Marker(
                          markerId: const MarkerId('farm'),
                          position: _farmLocation!,
                          icon: _buyerIcon ?? BitmapDescriptor.defaultMarker),
                    if (_currentLocation != null)
                      Marker(
                          markerId: const MarkerId('truck'),
                          position: _currentLocation!,
                          icon: _truckIcon ?? BitmapDescriptor.defaultMarker),
                  },
                  polylines: _polylines,
                  onMapCreated: (c) {
                    if (!_mapController.isCompleted) {
                      _mapController.complete(c);
                    }
                  },
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                  compassEnabled: false,
                  scrollGesturesEnabled: false,
                ),
                const Positioned(
                    right: 10,
                    top: 10,
                    child: CircleAvatar(
                        backgroundColor: Colors.white,
                        radius: 14,
                        child: Icon(Icons.fullscreen,
                            size: 18, color: Colors.black))),
              ]),
            ),
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

  Widget _buildContactCard(
      String name, String loc, String status, String cropName, String buyerId) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Buyer Details",
              style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87)),
          const SizedBox(height: 16),
          Container(
              width: double.infinity,
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
                CircleAvatar(
                    radius: 26,
                    backgroundColor: Colors.amber.shade100,
                    child: Text(name.isNotEmpty ? name[0].toUpperCase() : "B",
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.bold,
                            color: Colors.amber.shade900,
                            fontSize: 20))),
                const SizedBox(width: 16),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                      Text(name,
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.black87)),
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.location_on_rounded,
                              size: 14, color: Colors.grey.shade500),
                          const SizedBox(width: 6),
                          Expanded(
                              child: Text(
                                  loc.isEmpty ? 'Address not provided' : loc,
                                  style: GoogleFonts.poppins(
                                      color: Colors.grey.shade600,
                                      fontSize: 13),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis)),
                        ],
                      )
                    ])),
                IconButton(
                    onPressed: () {
                      if (buyerId.isNotEmpty) {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => ChatScreen(
                                    targetUserId: buyerId,
                                    targetName: name,
                                    orderId: _targetOrderId,
                                    cropName: cropName,
                                    orderStatus: status)));
                      }
                    },
                    style: IconButton.styleFrom(
                        backgroundColor: _primaryGreen,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                    icon: const Icon(Icons.chat_bubble_outline_rounded,
                        color: Colors.white)),
              ])),
        ],
      ),
    );
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
    Color color =
        (['accepted', 'confirmed', 'completed', 'delivered'].contains(lower))
            ? _primaryGreen
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
    int currentStep = (['accepted', 'confirmed'].contains(lower))
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
              color: done ? _primaryGreen : Colors.grey.shade200),
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
            color: idx < curr ? _primaryGreen : Colors.grey.shade200,
            margin: const EdgeInsets.only(bottom: 24)));
  }
}

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
