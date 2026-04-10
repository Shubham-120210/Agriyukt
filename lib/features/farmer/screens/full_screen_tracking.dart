import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;

// 🚀 CHAT IMPORT
import 'package:agriyukt_app/features/common/screens/chat_screen.dart';

class FullScreenTracking extends StatefulWidget {
  final String orderId;

  const FullScreenTracking({
    super.key,
    required this.orderId,
  });

  @override
  State<FullScreenTracking> createState() => _FullScreenTrackingState();
}

class _FullScreenTrackingState extends State<FullScreenTracking>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  final Completer<GoogleMapController> _mapController = Completer();

  final String googleApiKey = "AIzaSyD1ioETNK6cCxUud9k98JuTH3SzoyN2Fjc";

  LatLng? _farmLocation;
  Set<Polyline> _polylines = {};
  BitmapDescriptor? _truckIcon;
  BitmapDescriptor? _destinationIcon;

  LatLng? _lastPos;
  double _lastRotation = 0.0;
  bool _isMapInitialized = false;
  bool _hasFetchedRoute = false;

  String _distanceText = "Calculating...";
  String _etaText = "--";
  String _arrivalTimeText = "--:--";
  String _targetName = "Destination";

  // 🛡️ ROLE-BASED UI VARIABLES
  bool _isBuyer = true;
  String _chatTargetId = '';
  String _chatTargetName = '';
  String _cropName = 'Order';
  String _orderStatus = 'In Transit';

  // Real Google Maps Colors
  final Color _mapsGreen = const Color(0xFF0F9D58);
  final Color _mapsBlue = const Color(0xFF4285F4);
  final Color _mapsRed = const Color(0xFFDB4437);
  final Color _darkText = const Color(0xFF202124);
  final Color _greyText = const Color(0xFF70757A);

  late AnimationController _pulseController;

  final String _cleanMapStyle = '''
  [
    { "featureType": "poi", "stylers": [{ "visibility": "off" }] },
    { "featureType": "transit", "stylers": [{ "visibility": "off" }] },
    { "featureType": "road", "elementType": "geometry.fill", "stylers": [{"color": "#ffffff"}] },
    { "featureType": "road", "elementType": "geometry.stroke", "stylers": [{"color": "#e0e0e0"}] },
    { "featureType": "water", "stylers": [{"color": "#c8d7d4"}] }
  ]
  ''';

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000))
      ..repeat(reverse: true);
    _loadCustomIcons();
    _fetchDestinationData();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomIcons() async {
    _truckIcon = await _bitmapDescriptorFromIconData(
        Icons.navigation_rounded, _mapsBlue, 110);
    _destinationIcon =
        await _bitmapDescriptorFromIconData(Icons.location_on, _mapsRed, 120);
    if (mounted) setState(() {});
  }

  Future<void> _fetchDestinationData() async {
    try {
      final orderData = await _supabase.from('orders').select('''
          buyer_id, farmer_id, destination_lat, destination_lng, status, tracking_status,
          farmer:profiles!orders_farmer_id_fkey(latitude, longitude, first_name, last_name),
          buyer:profiles!orders_buyer_id_fkey(first_name, last_name),
          crop:crops!orders_crop_id_fkey(crop_name)
      ''').eq('id', widget.orderId).single();

      final String currentUserId = _supabase.auth.currentUser?.id ?? '';
      _isBuyer = currentUserId == orderData['buyer_id'];
      _orderStatus =
          orderData['tracking_status'] ?? orderData['status'] ?? 'In Transit';

      final rawCrop = orderData['crop'];
      if (rawCrop is Map && rawCrop.containsKey('crop_name')) {
        _cropName = rawCrop['crop_name'];
      }

      final rawFarmer = orderData['farmer'];
      final farmer = rawFarmer is Map ? rawFarmer : {};

      final rawBuyer = orderData['buyer'];
      final buyer = rawBuyer is Map ? rawBuyer : {};

      // Set Chat Target depending on who is looking at the screen
      if (_isBuyer) {
        _chatTargetId = orderData['farmer_id']?.toString() ?? '';
        _chatTargetName =
            "${farmer['first_name'] ?? 'Farmer'} ${farmer['last_name'] ?? ''}"
                .trim();
      } else {
        _chatTargetId = orderData['buyer_id']?.toString() ?? '';
        _chatTargetName =
            "${buyer['first_name'] ?? 'Buyer'} ${buyer['last_name'] ?? ''}"
                .trim();
      }

      double fLat = (orderData['destination_lat'] as num?)?.toDouble() ??
          (farmer['latitude'] as num?)?.toDouble() ??
          19.2183;
      double fLng = (orderData['destination_lng'] as num?)?.toDouble() ??
          (farmer['longitude'] as num?)?.toDouble() ??
          72.8567;

      if (mounted) {
        setState(() {
          _farmLocation = LatLng(fLat, fLng);
          _targetName = _isBuyer
              ? "${farmer['first_name'] ?? 'Destination'} ${farmer['last_name'] ?? ''}"
                  .trim()
              : "Farm";
        });
        if (_lastPos != null && !_hasFetchedRoute) {
          _drawGuaranteedPolyline(_lastPos!);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _farmLocation = const LatLng(19.2183, 72.8567);
          _targetName = "Mumbai Destination";
        });
        if (_lastPos != null && !_hasFetchedRoute) {
          _drawGuaranteedPolyline(_lastPos!);
        }
      }
    }
  }

  void _updateLocalEtaAndDistance(LatLng currentPos) {
    if (_farmLocation == null) return;

    double distanceInMeters = Geolocator.distanceBetween(
      currentPos.latitude,
      currentPos.longitude,
      _farmLocation!.latitude,
      _farmLocation!.longitude,
    );

    double distanceInKm = distanceInMeters / 1000;
    int etaMinutes = ((distanceInKm / 40) * 60).round();

    DateTime arrivalTime = DateTime.now().add(Duration(minutes: etaMinutes));
    String formattedArrival = DateFormat('h:mm a').format(arrivalTime);

    if (mounted) {
      setState(() {
        _distanceText = "${distanceInKm.toStringAsFixed(1)} km";
        _etaText = etaMinutes > 60
            ? "${(etaMinutes / 60).floor()} hr ${etaMinutes % 60} min"
            : "$etaMinutes min";
        _arrivalTimeText = formattedArrival;
      });
    }
  }

  void _drawGuaranteedPolyline(LatLng currentPos) {
    if (_farmLocation == null || !mounted) return;

    _hasFetchedRoute = true;
    _updateLocalEtaAndDistance(currentPos);

    setState(() {
      _polylines = {
        Polyline(
          polylineId: const PolylineId('guaranteed_blue_line'),
          color: _mapsBlue,
          points: [
            currentPos,
            LatLng(
                currentPos.latitude +
                    ((_farmLocation!.latitude - currentPos.latitude) * 0.3),
                currentPos.longitude - 0.015),
            LatLng(
                currentPos.latitude +
                    ((_farmLocation!.latitude - currentPos.latitude) * 0.7),
                currentPos.longitude + 0.015),
            _farmLocation!
          ],
          width: 7,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          geodesic: true,
        ),
      };
    });
  }

  Future<void> _fitRouteOnMap(LatLng currentPos) async {
    if (_farmLocation == null) return;
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

    controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100.0));
  }

  void _animateCamera(LatLng pos, double rotation) async {
    final controller = await _mapController.future;
    controller.animateCamera(CameraUpdate.newCameraPosition(
      CameraPosition(target: pos, zoom: 17.0, bearing: rotation, tilt: 50),
    ));
  }

  void _recenterMap() {
    if (_lastPos != null) {
      _animateCamera(_lastPos!, _lastRotation);
    }
  }

  double _calculateBearing(LatLng start, LatLng end) {
    double lat1 = start.latitude * (math.pi / 180.0);
    double lon1 = start.longitude * (math.pi / 180.0);
    double lat2 = end.latitude * (math.pi / 180.0);
    double lon2 = end.longitude * (math.pi / 180.0);
    double dLon = lon2 - lon1;
    double y = math.sin(dLon) * math.cos(lat2);
    double x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    return (math.atan2(y, x) * (180.0 / math.pi) + 360.0) % 360.0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _supabase
            .from('orders')
            .stream(primaryKey: ['id']).eq('id', widget.orderId),
        builder: (context, snapshot) {
          final data = snapshot.hasData && snapshot.data!.isNotEmpty
              ? snapshot.data!.first
              : {};

          double lat = (data['buyer_lat'] as num?)?.toDouble() ??
              (data['transport_lat'] as num?)?.toDouble() ??
              19.0760;
          double lng = (data['buyer_lng'] as num?)?.toDouble() ??
              (data['transport_lng'] as num?)?.toDouble() ??
              72.8777;

          LatLng currentPos = LatLng(lat, lng);

          if (_lastPos == null || _lastPos != currentPos) {
            double rotation = _lastPos != null
                ? _calculateBearing(_lastPos!, currentPos)
                : _lastRotation;
            _lastRotation = rotation;
            _lastPos = currentPos;

            Future.microtask(() {
              if (!mounted) return;
              if (!_hasFetchedRoute) {
                _drawGuaranteedPolyline(currentPos);
              } else {
                _updateLocalEtaAndDistance(currentPos);
              }
              if (!_isMapInitialized) {
                _fitRouteOnMap(currentPos);
                _isMapInitialized = true;
              } else {
                _animateCamera(currentPos, rotation);
              }
            });
          }

          return Stack(
            children: [
              // 1. THE FULL SCREEN MAP
              GoogleMap(
                initialCameraPosition:
                    CameraPosition(target: currentPos, zoom: 15),
                style: _cleanMapStyle,
                padding: const EdgeInsets.only(top: 120, bottom: 120),
                markers: {
                  if (_farmLocation != null)
                    Marker(
                        markerId: const MarkerId('farm'),
                        position: _farmLocation!,
                        icon:
                            _destinationIcon ?? BitmapDescriptor.defaultMarker),
                  Marker(
                      markerId: const MarkerId('truck'),
                      position: currentPos,
                      icon: _truckIcon ?? BitmapDescriptor.defaultMarker,
                      rotation: _lastRotation,
                      anchor: const Offset(0.5, 0.5),
                      flat: true),
                },
                polylines: _polylines,
                onMapCreated: (c) {
                  if (!_mapController.isCompleted) _mapController.complete(c);
                },
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                compassEnabled: false,
              ),

              // 2. DYNAMIC HEADER LOGIC (Buyer vs Farmer)
              Positioned(
                top: MediaQuery.of(context).padding.top + 16,
                left: 16,
                right: 16,
                child: _isBuyer
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 16),
                        decoration: BoxDecoration(
                            color: _mapsGreen,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 15,
                                  offset: const Offset(0, 8))
                            ]),
                        child: Row(
                          children: [
                            const Icon(Icons.turn_right_rounded,
                                color: Colors.white, size: 36),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("Continue to",
                                      style: GoogleFonts.roboto(
                                          color: Colors.white70,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500)),
                                  Text(_targetName,
                                      style: GoogleFonts.roboto(
                                          color: Colors.white,
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )
                    : Align(
                        alignment: Alignment.topCenter,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 14),
                          decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(30),
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black.withOpacity(0.15),
                                    blurRadius: 15,
                                    offset: const Offset(0, 5))
                              ]),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              FadeTransition(
                                opacity: _pulseController,
                                child: Icon(Icons.local_shipping_rounded,
                                    color: _mapsBlue, size: 22),
                              ),
                              const SizedBox(width: 12),
                              Text("Buyer is arriving",
                                  style: GoogleFonts.roboto(
                                      color: _darkText,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ),
              ),

              // 3. FLOATING ACTION BUTTONS (Chat & Recenter)
              Positioned(
                bottom: 140,
                right: 16,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // CHAT BUTTON
                    if (_chatTargetId.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                            color: _mapsGreen,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4))
                            ]),
                        child: IconButton(
                          icon: const Icon(Icons.chat_bubble_rounded,
                              color: Colors.white, size: 24),
                          onPressed: () {
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => ChatScreen(
                                          targetUserId: _chatTargetId,
                                          targetName: _chatTargetName,
                                          orderId: widget.orderId,
                                          cropName: _cropName,
                                          orderStatus: _orderStatus,
                                        )));
                          },
                        ),
                      ),

                    // RECENTER BUTTON
                    Container(
                      decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withOpacity(0.15),
                                blurRadius: 10,
                                offset: const Offset(0, 4))
                          ]),
                      child: IconButton(
                        icon: Icon(Icons.near_me, color: _mapsBlue, size: 26),
                        onPressed: _recenterMap,
                      ),
                    ),
                  ],
                ),
              ),

              // 4. GOOGLE MAPS BOTTOM NAVIGATION BAR
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: EdgeInsets.fromLTRB(
                      20,
                      20,
                      20,
                      MediaQuery.of(context).padding.bottom > 0
                          ? MediaQuery.of(context).padding.bottom + 10
                          : 30),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(24)),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 20,
                            offset: const Offset(0, -5))
                      ]),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Big Green ETA
                            Text(_etaText,
                                style: GoogleFonts.roboto(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 32,
                                    color: _mapsGreen,
                                    letterSpacing: -0.5)),
                            const SizedBox(height: 4),
                            // Distance and Time Info
                            Row(
                              children: [
                                Text(_distanceText,
                                    style: GoogleFonts.roboto(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                        color: _greyText)),
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 6),
                                  child: Text("•",
                                      style: TextStyle(
                                          color: _greyText, fontSize: 16)),
                                ),
                                Text(_arrivalTimeText,
                                    style: GoogleFonts.roboto(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                        color: _greyText)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Red Exit Button
                      InkWell(
                        onTap: () => Navigator.pop(context),
                        borderRadius: BorderRadius.circular(30),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 14),
                          decoration: BoxDecoration(
                            color: _mapsRed.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.close_rounded,
                                  color: _mapsRed, size: 20),
                              const SizedBox(width: 6),
                              Text("Exit",
                                  style: GoogleFonts.roboto(
                                      color: _mapsRed,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16)),
                            ],
                          ),
                        ),
                      )
                    ],
                  ),
                ),
              )
            ],
          );
        },
      ),
    );
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
}
