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
import 'package:agriyukt_app/features/common/services/payment_service.dart';
import 'package:agriyukt_app/features/farmer/screens/full_screen_tracking.dart';
import 'package:agriyukt_app/features/buyer/screens/buyer_crop_details_screen.dart';

class BuyerOrderDetailScreen extends StatefulWidget {
  final String orderId;
  final Map<String, dynamic>? cropData;

  const BuyerOrderDetailScreen(
      {super.key, required this.orderId, this.cropData});

  @override
  State<BuyerOrderDetailScreen> createState() => _BuyerOrderDetailScreenState();
}

class _BuyerOrderDetailScreenState extends State<BuyerOrderDetailScreen>
    with WidgetsBindingObserver {
  final _supabase = Supabase.instance.client;
  final PaymentService _paymentService = PaymentService();

  // 🔑 MAPS API KEY
  final String googleApiKey = "AIzaSyD1ioETNK6cCxUud9k98JuTH3SzoyN2Fjc";

  bool _isLoading = true;
  bool _isUpdatingStatus = false;
  late final RealtimeChannel _orderChannel;

  Map<String, dynamic>? _order;

  StreamSubscription<Position>? _positionStream;
  bool _hasStartedTripInSession = false;

  final ValueNotifier<bool> _isSharingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isTogglingTripNotifier =
      ValueNotifier<bool>(false);
  final ValueNotifier<double?> _distanceNotifier = ValueNotifier<double?>(null);
  final ValueNotifier<double> _progressNotifier = ValueNotifier<double>(0.0);

  // 🗺️ MINI MAP VARIABLES
  final Completer<GoogleMapController> _mapController = Completer();
  Set<Polyline> _polylines = {};
  BitmapDescriptor? _truckIcon;
  BitmapDescriptor? _farmerIcon;
  LatLng? _farmLocation;
  LatLng? _currentLocation;

  final TextEditingController _amountController = TextEditingController();

  static const Color _primaryBlue = Color(0xFF1565C0);
  static const Color _primaryGreen = Color(0xFF2E7D32);
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
    _loadCustomIcons();
    _fetchOrderDetails();
    _setupRealtimeSubscription();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionStream?.cancel();
    _positionStream = null;

    if (_isSharingNotifier.value && widget.orderId.isNotEmpty) {
      Future.microtask(() async {
        try {
          await _supabase.from('orders').update({
            'is_sharing_location': false,
            'is_trip_started': false
          }).eq('id', widget.orderId);
        } catch (_) {}
      });
    }

    _supabase.removeChannel(_orderChannel);
    _paymentService.dispose();
    _amountController.dispose();
    _isSharingNotifier.dispose();
    _isTogglingTripNotifier.dispose();
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
    _farmerIcon =
        await _bitmapDescriptorFromIconData(Icons.store, Colors.redAccent, 80);
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

  // --- 🚀 THICK BLUE POLYLINE ROUTING ---
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

    // 🛡️ PRESENTATION FALLBACK: Draws a gorgeous curved blue line if Google API fails
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
                      ((_farmLocation!.latitude - currentPos.latitude) * 0.5),
                  currentPos.longitude - 0.01),
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

  Future<void> _fetchOrderDetails() async {
    try {
      final data = await _supabase.from('orders').select('''
              *,
              farmer:profiles!orders_farmer_id_fkey(id, first_name, last_name, district, state, latitude, longitude),
              crop:crops!orders_crop_id_fkey(id, image_url, crop_name, unit, variety, grade, harvest_date, price, description)
          ''').eq('id', widget.orderId).single();

      if (mounted) {
        setState(() {
          _order = data;
          _isLoading = false;
        });

        if (!mounted) return;
        _isSharingNotifier.value =
            data['is_sharing_location'] ?? data['is_trip_started'] ?? false;

        // Setup Locations for Map
        final rawFarmer = data['farmer'];
        final farmer = rawFarmer is Map ? rawFarmer : {};
        double fLat = (data['transport_lat'] as num?)?.toDouble() ??
            (farmer['latitude'] as num?)?.toDouble() ??
            19.2183;
        double fLng = (data['transport_lng'] as num?)?.toDouble() ??
            (farmer['longitude'] as num?)?.toDouble() ??
            72.8567;
        double bLat = (data['buyer_lat'] as num?)?.toDouble() ?? 19.0760;
        double bLng = (data['buyer_lng'] as num?)?.toDouble() ?? 72.8777;

        _farmLocation = LatLng(fLat, fLng);
        _currentLocation = LatLng(bLat, bLng);

        _updateDistanceLocally();

        String status = (data['tracking_status'] ?? data['status'] ?? '')
            .toString()
            .toLowerCase();
        if (_isSharingNotifier.value &&
            ['shipped', 'in transit', 'out for delivery'].contains(status)) {
          if (_positionStream == null) {
            _startSharingLocation(isAutoResume: true);
          }
        }
      }
    } catch (e) {
      debugPrint("Fetch Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _setupRealtimeSubscription() {
    _orderChannel = _supabase
        .channel('public:orders:${widget.orderId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: widget.orderId),
          callback: (payload) {
            final newRec = payload.newRecord ?? {};
            final oldRec = payload.oldRecord ?? {};

            if (newRec['status'] != oldRec['status'] ||
                newRec['tracking_status'] != oldRec['tracking_status'] ||
                newRec['advance_amount'] != oldRec['advance_amount']) {
              if (mounted) _fetchOrderDetails();
            }
          },
        )
        .subscribe();
  }

  Future<void> _startSharingLocation({bool isAutoResume = false}) async {
    if (_positionStream != null || _isTogglingTripNotifier.value) return;

    _isTogglingTripNotifier.value = true;

    Timer(const Duration(seconds: 2), () {
      if (mounted && _isTogglingTripNotifier.value) {
        _isTogglingTripNotifier.value = false;
      }
    });

    try {
      if (mounted) _isSharingNotifier.value = true;

      if (!isAutoResume && !_hasStartedTripInSession) {
        _hasStartedTripInSession = true;
        HapticFeedback.lightImpact();

        if (mounted) {
          _showSnack("🚗 Trip Started!", Colors.green.shade700);
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => FullScreenTracking(orderId: widget.orderId)));
        }

        try {
          await _supabase
              .from('orders')
              .update({
                'is_sharing_location': true,
                'is_trip_started': true,
                'status': 'in transit',
                'tracking_status': 'In Transit'
              })
              .eq('id', widget.orderId)
              .timeout(const Duration(seconds: 2));

          _sendTripStartedNotification();
        } catch (_) {}
      }

      // 🚀 DRAW THE BLUE ROUTE IMMEDIATELY
      if (_currentLocation != null) {
        _fetchGooglePolyline(_currentLocation!);
      }

      try {
        bool serviceEnabled = await Geolocator.isLocationServiceEnabled()
            .timeout(const Duration(seconds: 2));
        if (serviceEnabled) {
          LocationPermission permission = await Geolocator.checkPermission();
          if (permission == LocationPermission.denied) {
            permission = await Geolocator.requestPermission();
          }
          if (permission == LocationPermission.whileInUse ||
              permission == LocationPermission.always) {
            Position? initialPos;
            try {
              initialPos = await Geolocator.getLastKnownPosition()
                  .timeout(const Duration(seconds: 2));
            } catch (_) {}

            if (initialPos != null && mounted) {
              _updateDatabase(initialPos);
              _calculateLiveDistance(initialPos);
              _currentLocation =
                  LatLng(initialPos.latitude, initialPos.longitude);
              _fetchGooglePolyline(_currentLocation!);
            }

            _positionStream = Geolocator.getPositionStream(
              locationSettings: const LocationSettings(
                  accuracy: LocationAccuracy.high, distanceFilter: 10),
            ).listen((Position position) {
              if (mounted) {
                _updateDatabase(position);
                _calculateLiveDistance(position);
                _currentLocation =
                    LatLng(position.latitude, position.longitude);
                _fetchGooglePolyline(_currentLocation!);
              }
            });
          }
        }
      } catch (_) {}
    } catch (_) {
    } finally {
      if (mounted) _isTogglingTripNotifier.value = false;
    }
  }

  void _sendTripStartedNotification() async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser != null && _order?['farmer_id'] != null) {
        final buyerPrefs = await _supabase
            .from('profiles')
            .select('first_name')
            .eq('id', currentUser.id)
            .maybeSingle();
        final buyerName = buyerPrefs?['first_name'] ?? 'Buyer';
        await _supabase.from('notifications').insert({
          'user_id': _order!['farmer_id'],
          'type': 'order_update',
          'title': 'Trip Started',
          'body': '$buyerName has started the trip to your location.',
          'metadata': {
            'order_id': widget.orderId,
            'status': 'in transit',
            'person_name': buyerName
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _stopSharingLocation() async {
    if (_isTogglingTripNotifier.value) return;
    _isTogglingTripNotifier.value = true;

    try {
      await _positionStream?.cancel();
      _positionStream = null;

      if (mounted) {
        _isSharingNotifier.value = false;
        _hasStartedTripInSession = false;
        _polylines.clear();
      }

      if (widget.orderId.isNotEmpty) {
        await _supabase
            .from('orders')
            .update({'is_sharing_location': false, 'is_trip_started': false})
            .eq('id', widget.orderId)
            .timeout(const Duration(seconds: 3));
      }

      if (mounted) _showSnack("🛑 Trip Ended.", Colors.orange.shade800);
    } catch (e) {
    } finally {
      if (mounted) _isTogglingTripNotifier.value = false;
    }
  }

  Future<void> _updateDatabase(Position pos) async {
    try {
      await _supabase
          .from('orders')
          .update({'buyer_lat': pos.latitude, 'buyer_lng': pos.longitude})
          .eq('id', widget.orderId)
          .timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  void _calculateLiveDistance(Position pos) {
    if (_order == null || !mounted) return;
    final farmer = _order!['farmer'] is Map ? _order!['farmer'] : {};
    double? targetLat = (_order!['transport_lat'] as num?)?.toDouble() ??
        (farmer['latitude'] as num?)?.toDouble() ??
        19.2183;
    double? targetLng = (_order!['transport_lng'] as num?)?.toDouble() ??
        (farmer['longitude'] as num?)?.toDouble() ??
        72.8567;

    double distMeters = Geolocator.distanceBetween(
        pos.latitude, pos.longitude, targetLat, targetLng);
    _distanceNotifier.value = distMeters;
  }

  void _updateDistanceLocally() {
    if (_order == null || !mounted) return;
    final farmer = _order!['farmer'] is Map ? _order!['farmer'] : {};
    double? fLat = (_order!['transport_lat'] as num?)?.toDouble() ??
        (farmer['latitude'] as num?)?.toDouble() ??
        19.2183;
    double? fLng = (_order!['transport_lng'] as num?)?.toDouble() ??
        (farmer['longitude'] as num?)?.toDouble() ??
        72.8567;
    double? bLat = (_order!['buyer_lat'] as num?)?.toDouble() ?? 19.0760;
    double? bLng = (_order!['buyer_lng'] as num?)?.toDouble() ?? 72.8777;

    double distMeters = Geolocator.distanceBetween(bLat, bLng, fLat, fLng);
    _distanceNotifier.value = distMeters;
  }

  void _triggerPayment(double totalAmount, double paidAmount) {
    double outstanding = totalAmount - paidAmount;
    if (outstanding <= 0) return;
    double minPayment = totalAmount * 0.50;
    if (minPayment > outstanding) minPayment = outstanding;
    double suggestedAmount = outstanding;
    _amountController.text = suggestedAmount == suggestedAmount.roundToDouble()
        ? suggestedAmount.toStringAsFixed(0)
        : suggestedAmount.toStringAsFixed(2);
    _showCustomPaymentDialog(totalAmount, outstanding, paidAmount, minPayment);
  }

  void _showCustomPaymentDialog(double totalOrderValue,
      double outstandingBalance, double currentPaid, double minPayment) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (BuildContext stateContext, StateSetter setDialogState) {
            double inputAmount = double.tryParse(_amountController.text) ?? 0;
            double commission = inputAmount * 0.04;
            double totalPayable = inputAmount + commission;
            bool isMinMet = inputAmount >= (minPayment - 0.01);
            bool isMaxMet = inputAmount <= (outstandingBalance + 0.01);

            String? errorText;
            if (inputAmount <= 0 && _amountController.text.isNotEmpty) {
              errorText = "Enter a valid amount";
            } else if (!isMinMet) {
              errorText = "Min payment: ₹${minPayment.toInt()} (50% of total)";
            } else if (!isMaxMet) {
              errorText = "Max payment: ₹${outstandingBalance.toInt()}";
            }

            return AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: Text("Pay Balance",
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold, fontSize: 18)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Total Order: ₹${totalOrderValue.toStringAsFixed(0)}",
                        style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87)),
                    Text("Remaining: ₹${outstandingBalance.toStringAsFixed(0)}",
                        style: GoogleFonts.poppins(
                            fontSize: 13, color: Colors.grey.shade600)),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _amountController,
                      enabled: true,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d+\.?\d{0,2}'))
                      ],
                      style: GoogleFonts.jetBrainsMono(
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                          color: Colors.black87),
                      decoration: InputDecoration(
                        prefixText: "₹ ",
                        prefixStyle: GoogleFonts.poppins(
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                            color: _primaryBlue),
                        labelText: "Amount to Pay",
                        labelStyle: GoogleFonts.poppins(fontSize: 14),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                                color: Color(0xFF1565C0), width: 2)),
                        errorText: errorText,
                      ),
                      onChanged: (val) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200)),
                      child: Column(
                        children: [
                          _buildBillRow("Base Amount", inputAmount),
                          const SizedBox(height: 8),
                          _buildBillRow("Platform Fee (4%)", commission,
                              color: Colors.red.shade700),
                          const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Divider(height: 1)),
                          _buildBillRow("Total Amount", totalPayable,
                              isBold: true, fontSize: 16),
                        ],
                      ),
                    )
                  ],
                ),
              ),
              actionsPadding: const EdgeInsets.only(right: 16, bottom: 16),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text("Cancel",
                      style: GoogleFonts.poppins(
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.bold)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryBlue,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
                  onPressed: (isMinMet && isMaxMet && inputAmount > 0)
                      ? () {
                          FocusManager.instance.primaryFocus?.unfocus();
                          Navigator.pop(ctx);
                          _processActualPayment(inputAmount, totalPayable);
                        }
                      : null,
                  child: Text("Pay ₹${totalPayable.toStringAsFixed(0)}",
                      style: GoogleFonts.poppins(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildBillRow(String label, double amount,
      {bool isBold = false, Color? color, double fontSize = 13}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: GoogleFonts.poppins(
                fontSize: fontSize,
                fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
                color: Colors.black87)),
        Text("₹${amount.toStringAsFixed(2)}",
            style: GoogleFonts.jetBrainsMono(
                fontSize: fontSize,
                fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
                color: color ?? (isBold ? _primaryBlue : Colors.black87))),
      ],
    );
  }

  Future<bool> _processActualPayment(
      double principalAmount, double totalCharged) async {
    final currentUser = _supabase.auth.currentUser;
    if (currentUser == null) return false;
    if (mounted) setState(() => _isUpdatingStatus = true);

    Completer<bool> paymentCompleter = Completer<bool>();

    await _paymentService.processPayment(
      context: context,
      appOrderId: widget.orderId,
      farmerId: _order?['farmer_id'] ?? '',
      amount: totalCharged,
      onResult: (bool isSuccess) async {
        if (!isSuccess) {
          if (mounted) setState(() => _isUpdatingStatus = false);
          paymentCompleter.complete(false);
          return;
        }
        try {
          final double platformFee = totalCharged - principalAmount;

          await _supabase.from('payments').insert({
            'order_id': widget.orderId,
            'buyer_id': currentUser.id,
            'farmer_id': _order?['farmer_id'],
            'base_amount': principalAmount,
            'platform_fee': platformFee,
            'total_charged': totalCharged,
            'status': 'SUCCESS',
            'payment_type': 'ONLINE',
            'gateway_transaction_id':
                'txn_${DateTime.now().millisecondsSinceEpoch}',
          });

          final latestOrder = await _supabase
              .from('orders')
              .select('advance_amount')
              .eq('id', widget.orderId)
              .single();
          double currentPaid =
              (num.tryParse(latestOrder['advance_amount']?.toString() ?? '0') ??
                      0)
                  .toDouble();
          double newTotalPaid =
              double.parse((currentPaid + principalAmount).toStringAsFixed(2));

          await _supabase.from('orders').update(
              {'advance_amount': newTotalPaid}).eq('id', widget.orderId);

          if (mounted) {
            _showSnack("Payment Successful! 🎉", Colors.green.shade700);
            await Future.delayed(const Duration(seconds: 1));
            await _fetchOrderDetails();
          }
          paymentCompleter.complete(true);
        } catch (_) {
          paymentCompleter.complete(false);
        } finally {
          if (mounted) setState(() => _isUpdatingStatus = false);
        }
      },
    );

    return paymentCompleter.future;
  }

  Future<void> _cancelOrder() async {
    HapticFeedback.heavyImpact();
    if (mounted) setState(() => _isUpdatingStatus = true);
    try {
      await _supabase
          .from('orders')
          .update({'status': 'cancelled'}).eq('id', widget.orderId);
      await _fetchOrderDetails();
      if (mounted) _showSnack("Order Cancelled", Colors.red.shade700);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isUpdatingStatus = false);
    }
  }

  Future<void> _pickSchedule() async {
    final date = await showDatePicker(
        context: context,
        initialDate: DateTime.now().add(const Duration(days: 1)),
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 30)));
    if (date == null || !mounted) return;

    final time = await showTimePicker(
        context: context, initialTime: const TimeOfDay(hour: 10, minute: 0));
    if (time == null || !mounted) return;

    final fullDate =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);

    setState(() => _isUpdatingStatus = true);
    try {
      await _supabase
          .from('orders')
          .update({'scheduled_pickup_time': fullDate.toIso8601String()}).eq(
              'id', widget.orderId);
      await _fetchOrderDetails();
      if (mounted) _showSnack("Schedule Updated", Colors.green.shade700);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isUpdatingStatus = false);
    }
  }

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
          appBar: AppBar(
              backgroundColor: _primaryBlue,
              title: const Text("Order Not Found",
                  style: TextStyle(color: Colors.white)),
              iconTheme: const IconThemeData(color: Colors.white)),
          body: Center(
              child: Text("This order does not exist.",
                  style: GoogleFonts.poppins())));
    }

    try {
      final rawFarmer = _order!['farmer'];
      final Map<String, dynamic> farmer = rawFarmer is Map
          ? Map<String, dynamic>.from(rawFarmer)
          : <String, dynamic>{};

      final String farmerName =
          "${farmer['first_name'] ?? 'Farmer'} ${farmer['last_name'] ?? ''}"
              .trim();
      final String farmerLoc =
          "${farmer['district'] ?? ''}, ${farmer['state'] ?? ''}"
              .replaceAll(RegExp(r'^, |,$'), '')
              .trim();
      final String farmerId = _order!['farmer_id']?.toString() ?? '';

      final rawCrop = _order!['crop'];
      final Map<String, dynamic> cropMap = rawCrop is Map
          ? Map<String, dynamic>.from(rawCrop)
          : <String, dynamic>{};

      String cropName =
          cropMap['crop_name'] ?? _order!['crop_name'] ?? "Crop Item";
      String? imgUrl = cropMap['image_url'];
      String cropVariety = cropMap['variety'] ?? _order!['variety'] ?? '';
      String cropGrade = cropMap['grade'] ?? _order!['grade'] ?? '';
      String unit = cropMap['unit'] ?? 'Kg';

      String harvestDate = "Available";
      if (cropMap['harvest_date'] != null &&
          cropMap['harvest_date'].toString().isNotEmpty) {
        try {
          harvestDate = DateFormat('dd MMM')
              .format(DateTime.parse(cropMap['harvest_date'].toString()));
        } catch (_) {}
      }

      final double quantity =
          (num.tryParse(_order!['quantity_kg']?.toString() ?? '0') ?? 0)
              .toDouble();
      final double price = (num.tryParse(_order!['price_offered']?.toString() ??
                  cropMap['price']?.toString() ??
                  '0') ??
              0)
          .toDouble();
      final double totalAmount = quantity * price;
      final double advancePaid =
          (num.tryParse(_order!['advance_amount']?.toString() ?? '0') ?? 0)
              .toDouble();

      String rawStatus =
          _order!['tracking_status'] ?? _order!['status'] ?? 'Pending';
      String status = rawStatus.toString().toLowerCase().trim();

      final isPending = ['pending', 'requested'].contains(status);
      final isCancelled = ['rejected', 'cancelled'].contains(status);
      final isDelivered = ['delivered', 'completed'].contains(status);

      final bool isFullyPaid =
          totalAmount > 0 && advancePaid >= (totalAmount - 1.0);

      final double fLat = (_order!['transport_lat'] as num?)?.toDouble() ??
          (farmer['latitude'] as num?)?.toDouble() ??
          19.2183;
      final double fLng = (_order!['transport_lng'] as num?)?.toDouble() ??
          (farmer['longitude'] as num?)?.toDouble() ??
          72.8567;
      final double bLat = (_order!['buyer_lat'] as num?)?.toDouble() ?? 19.0760;
      final double bLng = (_order!['buyer_lng'] as num?)?.toDouble() ?? 72.8777;

      final scheduleTime = _order!['scheduled_pickup_time'];
      String scheduleText = "Tap to Schedule";
      if (scheduleTime != null && scheduleTime.toString().isNotEmpty) {
        try {
          scheduleText = DateFormat('dd MMM, hh:mm a')
              .format(DateTime.parse(scheduleTime.toString()).toLocal());
        } catch (_) {}
      }

      String fallbackOtp = widget.orderId.replaceAll(RegExp(r'[^0-9]'), '');
      fallbackOtp = fallbackOtp.length >= 4
          ? fallbackOtp.substring(0, 4)
          : fallbackOtp.padRight(4, '0');
      final String deliveryOtp =
          _order!['delivery_otp']?.toString() ?? fallbackOtp;

      if (isDelivered && _isSharingNotifier.value) {
        Future.delayed(Duration.zero, _stopSharingLocation);
      }

      double bottomPadding =
          (isCancelled || isDelivered || isFullyPaid) ? 40 : 260;

      return Scaffold(
        backgroundColor: _surfaceBg,
        appBar: AppBar(
          title: Text("Order Details",
              style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 20)),
          backgroundColor: _primaryBlue,
          elevation: 0,
          centerTitle: false,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: SafeArea(
          child: Stack(
            children: [
              SingleChildScrollView(
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
                    _buildScheduleCard(
                        !isPending && !isCancelled && !isDelivered,
                        scheduleText),
                    const SizedBox(height: 16),
                    if (!isPending && !isCancelled) ...[
                      ValueListenableBuilder<bool>(
                          valueListenable: _isSharingNotifier,
                          builder: (context, isSharing, child) {
                            return _buildTrackingBlock(
                                rawStatus, isSharing, deliveryOtp, isDelivered);
                          }),
                      const SizedBox(height: 16),
                    ],
                    _buildContactCard(
                        farmerName, farmerLoc, rawStatus, cropName, farmerId),
                  ],
                ),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                left: 0,
                right: 0,
                bottom: (isCancelled || isDelivered || isFullyPaid) ? -300 : 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(24)),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.02),
                            blurRadius: 10,
                            offset: const Offset(0, -2))
                      ]),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isFullyPaid)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(12)),
                          child: Center(
                              child: Text("ORDER FULLY PAID",
                                  style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green))),
                        ),
                      if (isPending)
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: OutlinedButton(
                            onPressed: _isUpdatingStatus ? null : _cancelOrder,
                            style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Colors.red),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30))),
                            child: _isUpdatingStatus
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                        color: Colors.red, strokeWidth: 2))
                                : Text("Cancel Order",
                                    style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.red.shade700,
                                        fontSize: 16)),
                          ),
                        )
                      else if (!isFullyPaid)
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton.icon(
                            onPressed: _isUpdatingStatus
                                ? null
                                : () =>
                                    _triggerPayment(totalAmount, advancePaid),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: _primaryBlue,
                                elevation: 4,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30))),
                            icon: _isUpdatingStatus
                                ? const SizedBox.shrink()
                                : const Icon(Icons.payment,
                                    color: Colors.white),
                            label: _isUpdatingStatus
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2))
                                : Text("PAY BALANCE",
                                    style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                        fontSize: 16)),
                          ),
                        )
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e, stacktrace) {
      debugPrint("FATAL UI CRASH: $e\n$stacktrace");
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
            backgroundColor: Colors.red,
            title: const Text("Error", style: TextStyle(color: Colors.white)),
            iconTheme: const IconThemeData(color: Colors.white)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: Colors.red, size: 60),
                const SizedBox(height: 16),
                Text("Data Parsing Error",
                    style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.red)),
                const SizedBox(height: 8),
                Text("A value from the database couldn't be read properly.",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(color: Colors.grey.shade600)),
              ],
            ),
          ),
        ),
      );
    }
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
                  pageBuilder: (_, __, ___) =>
                      BuyerCropDetailsScreen(crop: cropMap),
                  transitionsBuilder: (_, anim, __, child) =>
                      FadeTransition(opacity: anim, child: child),
                ));
          },
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  height: 110,
                  width: 110,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200)),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: Hero(
                      tag: 'buyer_order_img_detail_${widget.orderId}',
                      child: (rawImgUrl != null && rawImgUrl.isNotEmpty)
                          ? CachedNetworkImage(
                              imageUrl: rawImgUrl.startsWith('http')
                                  ? rawImgUrl
                                  : _supabase.storage
                                      .from('crop_images')
                                      .getPublicUrl(rawImgUrl),
                              fit: BoxFit.cover,
                              memCacheWidth: 300,
                              memCacheHeight: 300,
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
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(displayTitle,
                          style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                              letterSpacing: -0.5,
                              height: 1.2),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      if (grade.isNotEmpty && grade.toLowerCase() != 'null')
                        Padding(
                          padding: const EdgeInsets.only(top: 4, bottom: 4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(4),
                                border:
                                    Border.all(color: Colors.grey.shade300)),
                            child: Text("Grade $grade",
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
                          Expanded(
                              child: Text(
                                  "₹${pricePerUnit.toStringAsFixed(0)} / $unit",
                                  style: GoogleFonts.jetBrainsMono(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: _primaryBlue),
                                  overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      _buildStatusBadge(status)
                    ],
                  ),
                ),
                Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    child: Icon(Icons.arrow_forward_ios_rounded,
                        color: Colors.grey.shade400, size: 16)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBreakdownCard(double qty, double total, double paid) {
    String qtyText = qty == qty.roundToDouble()
        ? qty.toStringAsFixed(0)
        : qty.toStringAsFixed(2);

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
        _row("Total Quantity", "$qtyText Kg", isNumber: true),
        const SizedBox(height: 12),
        _row("Total Price", "₹${NumberFormat('#,##0').format(total)}",
            isBold: true, isNumber: true),
        const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Divider(height: 1)),
        _row("Amount Paid", "₹${NumberFormat('#,##0').format(paid)}",
            color: _primaryBlue, isNumber: true),
        const SizedBox(height: 12),
        _row(
            "Pending Balance", "₹${NumberFormat('#,##0').format(total - paid)}",
            color: Colors.red.shade700, isBold: true, isNumber: true),
      ]),
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

  Widget _buildScheduleCard(bool isActive, String text) {
    return GestureDetector(
      onTap: isActive ? _pickSchedule : null,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.blue.shade100)),
        child: Row(children: [
          const Icon(Icons.calendar_month_rounded, color: _primaryBlue),
          const SizedBox(width: 16),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("Scheduled Pickup",
                  style: GoogleFonts.poppins(
                      color: _primaryBlue,
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
          if (isActive)
            const Icon(Icons.edit_rounded, size: 20, color: _primaryBlue)
        ]),
      ),
    );
  }

  Widget _buildTrackingBlock(
      String status, bool sharing, String deliveryOtp, bool isDelivered) {
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
          Text("Tracking",
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.black87)),
          if (sharing && !isDelivered) _buildLiveBadge(),
        ]),
        const SizedBox(height: 24),
        _buildCustomTimeline(status),
        const SizedBox(height: 24),
        if (!isDelivered) ...[
          const Divider(),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: Colors.green.shade50, shape: BoxShape.circle),
                  child: const Icon(Icons.vpn_key_rounded,
                      color: _primaryGreen, size: 24)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("DELIVERY OTP",
                        style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade500,
                            letterSpacing: 1)),
                    Text(deliveryOtp,
                        style: GoogleFonts.jetBrainsMono(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 4,
                            color: Colors.black87)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ValueListenableBuilder<bool>(
              valueListenable: _isTogglingTripNotifier,
              builder: (context, isToggling, child) {
                return SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                        onPressed: isToggling
                            ? null
                            : () {
                                if (sharing) {
                                  _stopSharingLocation();
                                } else {
                                  _startSharingLocation(isAutoResume: false);
                                }
                              },
                        style: ElevatedButton.styleFrom(
                            backgroundColor:
                                sharing ? Colors.red.shade50 : _primaryBlue,
                            foregroundColor:
                                sharing ? Colors.red.shade700 : Colors.white,
                            elevation: 0,
                            side: sharing
                                ? BorderSide(color: Colors.red.shade300)
                                : BorderSide.none,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12))),
                        icon: isToggling
                            ? const SizedBox.shrink()
                            : Icon(sharing
                                ? Icons.stop_rounded
                                : Icons.directions_car_rounded),
                        label: isToggling
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : Text(sharing ? "End Trip" : "Start Trip to Farm",
                                style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.bold))));
              }),
          const SizedBox(height: 16),
          if (sharing) ...[
            GestureDetector(
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          FullScreenTracking(orderId: widget.orderId))),
              child: Container(
                height: 160, // 🚀 Taller map so you can see the route clearly!
                width: double.infinity,
                decoration: BoxDecoration(
                    color: const Color(0xFFEDF2F7),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Colors.blue.shade200, width: 2)),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: Stack(children: [
                    // 🗺️ REAL LIVE GOOGLE MAP WIDGET INSIDE THE BOX WITH BLUE POLYLINE
                    GoogleMap(
                      initialCameraPosition: CameraPosition(
                          target: _currentLocation ??
                              const LatLng(19.0760, 72.8777),
                          zoom: 12),
                      style: _uberMapStyle,
                      markers: {
                        if (_farmLocation != null)
                          Marker(
                              markerId: const MarkerId('farm'),
                              position: _farmLocation!,
                              icon: _farmerIcon ??
                                  BitmapDescriptor.defaultMarker),
                        if (_currentLocation != null)
                          Marker(
                              markerId: const MarkerId('truck'),
                              position: _currentLocation!,
                              icon:
                                  _truckIcon ?? BitmapDescriptor.defaultMarker),
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
                      scrollGesturesEnabled:
                          false, // Acts like a preview button
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
                if (distance == null) return const SizedBox.shrink();
                String distText = (distance > 1000)
                    ? "${(distance / 1000).toStringAsFixed(1)} km"
                    : "${distance.round()} m";

                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                      color: _primaryBlue.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _primaryBlue.withOpacity(0.1))),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildStatColumn(Icons.map_rounded, "Distance", distText),
                      Container(
                          width: 1,
                          height: 40,
                          color: _primaryBlue.withOpacity(0.2)),
                      _buildStatColumn(Icons.timer_rounded, "Est. Time",
                          "${(distance / 1000 / 40 * 60).round()} mins"),
                    ],
                  ),
                );
              },
            ),
          ] else ...[
            Container(
                height: 120,
                width: double.infinity,
                decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Colors.grey.shade300)),
                child: Center(
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                      Icon(Icons.map_rounded,
                          size: 30, color: Colors.grey.shade400),
                      const SizedBox(height: 8),
                      Text("Click 'Start Trip' to unlock map",
                          style: GoogleFonts.poppins(
                              color: Colors.grey.shade500,
                              fontSize: 12,
                              fontWeight: FontWeight.w500))
                    ])))
          ]
        ] else ...[
          Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12)),
              child:
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.check_circle,
                    color: Colors.green.shade700, size: 20),
                const SizedBox(width: 8),
                Text("Order Delivered Successfully",
                    style: GoogleFonts.poppins(
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.bold,
                        fontSize: 13))
              ]))
        ]
      ]),
    );
  }

  Widget _buildStatColumn(IconData icon, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(icon, size: 14, color: _primaryBlue),
          const SizedBox(width: 6),
          Text(label,
              style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: _primaryBlue,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5))
        ]),
        const SizedBox(height: 4),
        Text(value,
            style: GoogleFonts.jetBrainsMono(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87)),
      ],
    );
  }

  Widget _buildLiveBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: Colors.red.shade600, borderRadius: BorderRadius.circular(100)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.fiber_manual_record, color: Colors.white, size: 8),
          const SizedBox(width: 4),
          Text("LIVE",
              style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5)),
        ],
      ),
    );
  }

  Widget _buildContactCard(
      String name, String loc, String status, String cropName, String id) {
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
          CircleAvatar(
              radius: 26,
              backgroundColor: Colors.blue.shade50,
              child: Text(name.isNotEmpty ? name[0].toUpperCase() : "F",
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      color: _primaryBlue,
                      fontSize: 20))),
          const SizedBox(width: 16),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                Text("Farmer Details",
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        color: Colors.grey.shade500)),
                Text(name,
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.black87)),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.location_on_rounded,
                        size: 14, color: Colors.grey.shade500),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text(loc.isEmpty ? 'Address not provided' : loc,
                            style: GoogleFonts.poppins(
                                color: Colors.grey.shade600, fontSize: 13),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis)),
                  ],
                )
              ])),
          IconButton(
              onPressed: () {
                if (id.isNotEmpty) {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => ChatScreen(
                              targetUserId: id,
                              targetName: name,
                              orderId: widget.orderId,
                              cropName: cropName,
                              orderStatus: status)));
                }
              },
              style: IconButton.styleFrom(
                  backgroundColor: _primaryBlue,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              icon: const Icon(Icons.chat_bubble_outline_rounded,
                  color: Colors.white)),
        ]));
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
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? _primaryBlue : Colors.grey.shade200),
          child: const Icon(Icons.check_circle_rounded,
              color: Colors.white, size: 16)),
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
            color: idx < curr ? _primaryBlue : Colors.grey.shade200,
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
