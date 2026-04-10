import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';

class BuyerCropDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> crop;
  final Map<String, dynamic>? cropData;

  const BuyerCropDetailsScreen({super.key, required this.crop, this.cropData});

  @override
  State<BuyerCropDetailsScreen> createState() => _BuyerCropDetailsScreenState();
}

class _BuyerCropDetailsScreenState extends State<BuyerCropDetailsScreen> {
  final _supabase = Supabase.instance.client;
  bool _isOrdering = false;

  Map<String, dynamic>? _predictionData;
  bool _isLoadingPrediction = true;
  bool _isFavorite = false;
  bool _isCheckingFavorite = true;

  @override
  void initState() {
    super.initState();
    _fetchCropPrediction();
    _checkIfFavorite();
  }

  bool _isCropMatch(String farmerCrop, String aiCrop) {
    String f = farmerCrop.toLowerCase().trim();
    String a = aiCrop.toLowerCase().trim();
    if (f == a) return true;
    if ((f.contains('okra') ||
            f.contains('ladyfinger') ||
            f.contains('bhindi')) &&
        (a.contains('okra') ||
            a.contains('ladyfinger') ||
            a.contains('bhindi'))) {
      return true;
    }
    if (f.contains(a) || a.contains(f)) return true;
    return false;
  }

  Future<void> _fetchCropPrediction() async {
    try {
      final cropMap = widget.cropData ?? widget.crop;
      final String cropName = cropMap['crop_name']?.toString().trim() ??
          cropMap['name']?.toString().trim() ??
          '';

      if (cropName.isEmpty) {
        if (mounted) setState(() => _isLoadingPrediction = false);
        return;
      }

      final response = await _supabase
          .from('market_predictions')
          .select()
          .timeout(const Duration(seconds: 10));

      Map<String, dynamic>? matchedPrediction;
      for (var data in response) {
        String aiCropName = data['crop_name']?.toString() ?? '';
        if (_isCropMatch(cropName, aiCropName)) {
          matchedPrediction = data;
          break;
        }
      }

      if (mounted) {
        setState(() {
          _predictionData = matchedPrediction;
          _isLoadingPrediction = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingPrediction = false);
    }
  }

  Future<void> _checkIfFavorite() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      final cropId = (widget.cropData ?? widget.crop)['id'];

      final response = await _supabase
          .from('favorites')
          .select('id')
          .eq('user_id', user.id)
          .eq('crop_id', cropId)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _isFavorite = response != null;
          _isCheckingFavorite = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isCheckingFavorite = false);
    }
  }

  Future<void> _toggleFavorite() async {
    HapticFeedback.selectionClick();
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    final cropId = (widget.cropData ?? widget.crop)['id'];

    setState(() => _isFavorite = !_isFavorite);

    try {
      if (_isFavorite) {
        await _supabase
            .from('favorites')
            .insert({'user_id': user.id, 'crop_id': cropId});
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Added to Watchlist!", style: GoogleFonts.poppins()),
            backgroundColor: Colors.black87,
            duration: const Duration(seconds: 1)));
      } else {
        await _supabase
            .from('favorites')
            .delete()
            .eq('user_id', user.id)
            .eq('crop_id', cropId);
      }
    } catch (e) {
      setState(() => _isFavorite = !_isFavorite);
    }
  }

  void _showOrderDialog(String priceStr, double maxQty) {
    final double pricePerKg =
        double.tryParse(priceStr.replaceAll(',', '')) ?? 0.0;
    final TextEditingController qtyController = TextEditingController();
    double totalCost = 0.0;
    String? errorText;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                  left: 20,
                  right: 20,
                  top: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Place Order",
                      style: GoogleFonts.poppins(
                          fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 15),
                  TextField(
                    controller: qtyController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: GoogleFonts.poppins(),
                    decoration: InputDecoration(
                      labelText: "Quantity Needed",
                      hintText: "Available: $maxQty",
                      errorText: errorText,
                      labelStyle: GoogleFonts.poppins(),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      suffixText: widget.cropData?['unit'] ??
                          widget.crop['unit'] ??
                          "Kg",
                      suffixStyle:
                          GoogleFonts.poppins(fontWeight: FontWeight.bold),
                    ),
                    onChanged: (val) {
                      final q = double.tryParse(val) ?? 0.0;
                      setSheetState(() {
                        if (q > maxQty) {
                          errorText = "Exceeds available stock ($maxQty)";
                          totalCost = 0.0;
                        } else if (q <= 0 && val.isNotEmpty) {
                          errorText = "Enter valid quantity";
                          totalCost = 0.0;
                        } else {
                          errorText = null;
                          totalCost = q * pricePerKg;
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 15),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Total Cost:",
                          style: GoogleFonts.poppins(fontSize: 16)),
                      Text(
                          "₹${NumberFormat.decimalPattern('en_IN').format(totalCost)}",
                          style: GoogleFonts.poppins(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF2E7D32))),
                    ],
                  ),
                  const SizedBox(height: 25),
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: (_isOrdering ||
                              errorText != null ||
                              totalCost <= 0 ||
                              qtyController.text.isEmpty)
                          ? null
                          : () async {
                              final qty =
                                  double.tryParse(qtyController.text) ?? 0.0;
                              Navigator.pop(context);
                              await _placeOrderNative(qty, totalCost);
                            },
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2E7D32),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12))),
                      child: _isOrdering
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text("CONFIRM ORDER",
                              style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // 🚀 DIRECT DATABASE INSERT (Bypasses all RPCs, strict schema match)
  Future<void> _placeOrderNative(double quantity, double totalCost) async {
    setState(() => _isOrdering = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw "Authentication Error";

      final crop = widget.cropData ?? widget.crop;
      final cropId = crop['id'];
      final farmerId = crop['farmer_id'];
      final cropName = crop['crop_name'] ?? crop['name'] ?? 'Unknown Crop';

      String buyerName = "Buyer";
      try {
        final profile = await _supabase
            .from('profiles')
            .select('first_name, last_name')
            .eq('id', user.id)
            .single();
        buyerName = "${profile['first_name']} ${profile['last_name']}".trim();
      } catch (_) {}

      // 🚀 EXPLICIT MAPPING: We send exactly what the 'orders' table needs. Nothing more.
      final payload = {
        'buyer_id': user.id,
        'farmer_id': farmerId,
        'crop_id': cropId,
        'quantity_kg': quantity,
        'total_price': totalCost, // Matches your schema
        'price_offered': totalCost, // Matches your schema
        'crop_name': cropName,
        'buyer_name': buyerName,
        'status': 'Pending',
        'tracking_status': 'Pending',
      };

      await _supabase
          .from('orders')
          .insert(payload)
          .timeout(const Duration(seconds: 15));

      HapticFeedback.mediumImpact();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("✅ Order Requested! Waiting for Farmer approval.",
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
            backgroundColor: const Color(0xFF1565C0)));
        Navigator.pop(context, true);
      }
    } on PostgrestException catch (pe) {
      HapticFeedback.heavyImpact();
      debugPrint("Postgres Error: ${pe.message}");
      // If it still says "column 'name' does not exist", it is 100% a Database Trigger issue.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("DB Error: ${pe.message}",
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
            backgroundColor: Colors.red.shade800,
            duration: const Duration(seconds: 6)));
      }
    } catch (e) {
      HapticFeedback.heavyImpact();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("App Error: $e", style: GoogleFonts.poppins()),
            backgroundColor: Colors.red.shade800,
            duration: const Duration(seconds: 6)));
      }
    } finally {
      if (mounted) setState(() => _isOrdering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final crop = widget.cropData ?? widget.crop;

    final String name = crop['crop_name'] ?? crop['name'] ?? 'Unknown Crop';
    final String variety = crop['variety'] ?? crop['crop_variety'] ?? 'Generic';
    final String status =
        (crop['status'] ?? 'Active').toString().toLowerCase().trim();
    final String category = crop['category'] ?? 'General';
    final String grade = crop['grade'] ?? 'Standard';

    String rawPrice =
        (crop['price']?.toString() ?? crop['price_per_qty']?.toString() ?? "0")
            .replaceAll(RegExp(r'[^0-9.]'), '');
    double priceNumeric = double.tryParse(rawPrice) ?? 0.0;
    String priceVal = NumberFormat.decimalPattern('en_IN').format(priceNumeric);

    // 🚀 FIXED: Pure Stock Reader
    double totalQty = 0.0;
    if (crop['quantity_kg'] != null &&
        crop['quantity_kg'].toString().isNotEmpty &&
        double.tryParse(crop['quantity_kg'].toString()) != 0) {
      totalQty = double.tryParse(crop['quantity_kg'].toString()) ?? 0.0;
    } else {
      String rawQtyStr = crop['quantity']?.toString() ?? "0";
      totalQty =
          double.tryParse(rawQtyStr.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
    }

    String cleanQty = totalQty == totalQty.truncateToDouble()
        ? totalQty.toInt().toString()
        : totalQty.toStringAsFixed(2);

    String unit = crop['unit'] ?? "Kg";
    if (crop['quantity'] != null && crop['quantity'].toString().contains(' ')) {
      unit = crop['quantity'].toString().split(' ').sublist(1).join(' ').trim();
    }
    if (unit.isEmpty) unit = "Kg";
    final String quantityStr = "$cleanQty $unit";

    // 🚀 LOGIC FIX: Button enables if stock > 0 AND status is active
    final bool isBuyable = totalQty > 0 && status == 'active';

    String description = crop['description'] ??
        crop['health_notes'] ??
        "No specific notes provided for this crop.";
    final farmerProfile = crop['profiles'] ?? {};
    final String farmerName =
        "${farmerProfile['first_name'] ?? 'Farmer'} ${farmerProfile['last_name'] ?? ''}"
            .trim();
    final String imgUrl = crop['image_url']?.toString() ?? '';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text("Crop Details",
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (!_isCheckingFavorite)
            IconButton(
                icon: Icon(_isFavorite ? Icons.favorite : Icons.favorite_border,
                    color: _isFavorite ? Colors.redAccent : Colors.white),
                onPressed: _toggleFavorite),
          const SizedBox(width: 8),
        ],
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 16,
            bottom: MediaQuery.of(context).padding.bottom > 0
                ? MediaQuery.of(context).padding.bottom
                : 20),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 15,
                offset: const Offset(0, -5))
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Asking Price",
                      style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500)),
                  Text("₹$priceVal / $unit",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87)),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: isBuyable
                  ? () => _showOrderDialog(priceNumeric.toString(), totalQty)
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    isBuyable ? const Color(0xFF2E7D32) : Colors.grey.shade400,
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(isBuyable ? "BUY NOW" : "UNAVAILABLE",
                  style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5)),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Hero(
              tag: crop['id']?.toString() ?? UniqueKey().toString(),
              child: Container(
                height: 250,
                width: double.infinity,
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(15),
                    color: Colors.grey[100],
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4))
                    ]),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: imgUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: imgUrl.startsWith('http')
                              ? imgUrl
                              : _supabase.storage
                                  .from('crop_images')
                                  .getPublicUrl(imgUrl),
                          fit: BoxFit.cover,
                          memCacheHeight: 750,
                          placeholder: (context, url) => const Center(
                              child: CircularProgressIndicator(
                                  color: Colors.green)),
                          errorWidget: (context, url, error) => const Center(
                              child: Icon(Icons.image_not_supported,
                                  size: 50, color: Colors.grey)),
                        )
                      : const Center(
                          child:
                              Icon(Icons.image, size: 80, color: Colors.grey)),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                    child: Text("$name ($variety)",
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                            height: 1.2))),
                const SizedBox(width: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                      color: _getStatusColor(status).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: _getStatusColor(status).withOpacity(0.5))),
                  child: Text(status.toUpperCase(),
                      style: GoogleFonts.poppins(
                          color: _getStatusColor(status),
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          letterSpacing: 0.5)),
                )
              ],
            ),
            const SizedBox(height: 5),
            Text("$category • $grade",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                    color: Colors.grey[600],
                    fontSize: 15,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 24),
            _buildMarketIntelligenceCard(),
            const Divider(height: 40, thickness: 1),
            _detailRow(Icons.scale, "Available", quantityStr),
            _detailRow(Icons.verified_outlined, "Grade", grade),
            _detailRow(
                Icons.eco, "Farming Mode", crop['crop_type'] ?? 'Organic'),
            _detailRow(Icons.event_available, "Harvest Date",
                _formatDate(crop['harvest_date'])),
            _detailRow(Icons.local_shipping, "Available From",
                _formatDate(crop['available_from'])),
            const SizedBox(height: 30),
            Text("Farmer Details",
                style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87)),
            const SizedBox(height: 12),
            _buildFarmerCard(farmerName, farmerProfile),
            const SizedBox(height: 30),
            Text("Description",
                style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87)),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: Colors.green.shade50.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade100)),
              child: Text(description,
                  style: GoogleFonts.poppins(
                      fontSize: 14, height: 1.6, color: Colors.black87)),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildMarketIntelligenceCard() {
    if (_isLoadingPrediction)
      return Container(
          height: 100,
          decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(16)),
          child: const Center(
              child: CircularProgressIndicator(color: Color(0xFF1E293B))));
    if (_predictionData == null) {
      return Container(
        margin: const EdgeInsets.only(bottom: 24),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade300)),
        child: Row(children: [
          Icon(Icons.auto_awesome, color: Colors.grey.shade400, size: 28),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text("AI Market Insights",
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade700,
                        fontSize: 14)),
                const SizedBox(height: 4),
                Text(
                    "Our AI models are currently gathering market data for this specific crop variety. Check back soon!",
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: Colors.grey.shade600)),
              ])),
        ]),
      );
    }

    final double liveAvg =
        double.tryParse(_predictionData!['live_price']?.toString() ?? '0') ??
            0.0;
    final double predicted = double.tryParse(
            _predictionData!['predicted_price']?.toString() ?? '0') ??
        0.0;
    final double trend =
        double.tryParse(_predictionData!['trend_percent']?.toString() ?? '0') ??
            0.0;
    final bool isUpward = _predictionData!['is_upward'] == true;
    final Color trendColor = isUpward ? Colors.redAccent : Colors.greenAccent;
    final IconData trendIcon =
        isUpward ? Icons.trending_up : Icons.trending_down;
    int decimals = liveAvg < 100 ? 1 : 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 15,
                offset: const Offset(0, 8))
          ]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.auto_awesome, color: Colors.amberAccent, size: 20),
          const SizedBox(width: 8),
          Text("AI Market Insights",
              style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.white))
        ]),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("Mandi Avg. Today",
                style: GoogleFonts.poppins(
                    fontSize: 12, color: Colors.grey.shade400)),
            Text("₹${liveAvg.toStringAsFixed(decimals)}",
                style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.white))
          ]),
          Container(width: 1, height: 40, color: Colors.grey.shade700),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text("Tomorrow's Prediction",
                style: GoogleFonts.poppins(
                    fontSize: 12, color: Colors.grey.shade400)),
            Row(children: [
              Icon(trendIcon, color: trendColor, size: 18),
              const SizedBox(width: 4),
              Text("₹${predicted.toStringAsFixed(decimals)}",
                  style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: trendColor))
            ])
          ])
        ]),
        const SizedBox(height: 16),
        Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              Icon(Icons.info_outline, color: Colors.grey.shade300, size: 16),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(
                      isUpward
                          ? "Prices are expected to rise by ${trend.toStringAsFixed(1)}%. Buying today is recommended."
                          : "Prices are expected to drop by ${trend.toStringAsFixed(1)}%. You may want to wait.",
                      style: GoogleFonts.poppins(
                          fontSize: 11, color: Colors.grey.shade300)))
            ])),
      ]),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(children: [
        Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 20, color: Colors.green.shade700)),
        const SizedBox(width: 12),
        Text("$label:",
            style: GoogleFonts.poppins(
                color: Colors.grey[700],
                fontSize: 14,
                fontWeight: FontWeight.w500)),
        const SizedBox(width: 8),
        Expanded(
            child: Text(value,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87))),
      ]),
    );
  }

  Widget _buildFarmerCard(String name, Map profile) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.grey.shade200)),
      child: Column(children: [
        Row(children: [
          CircleAvatar(
              backgroundColor: Colors.green.shade100,
              child: Text(name.isNotEmpty ? name[0] : "F",
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade900))),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name,
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold, fontSize: 16)),
            Row(children: [
              Icon(Icons.verified, size: 14, color: Colors.green.shade600),
              const SizedBox(width: 4),
              Text("Verified Producer",
                  style: GoogleFonts.poppins(
                      color: Colors.green.shade700,
                      fontSize: 12,
                      fontWeight: FontWeight.w500))
            ])
          ])
        ]),
        const Divider(height: 25),
        _farmerLocRow(Icons.location_city, "District",
            profile['district'] ?? 'Not Specified'),
        _farmerLocRow(
            Icons.map, "Taluka", profile['taluka'] ?? 'Not Specified'),
      ]),
    );
  }

  Widget _farmerLocRow(IconData icon, String l, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Icon(icon, size: 14, color: Colors.grey.shade500),
        const SizedBox(width: 8),
        Text("$l:",
            style:
                GoogleFonts.poppins(color: Colors.grey.shade600, fontSize: 13)),
        const Spacer(),
        Text(v,
            style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.black87))
      ]),
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty || dateStr == '--')
      return "Not Specified";
    try {
      final d = DateTime.parse(dateStr).toLocal();
      return DateFormat('dd MMM yyyy').format(d);
    } catch (e) {
      return dateStr;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return const Color(0xFF2E7D32);
      case 'sold':
        return Colors.red.shade700;
      case 'inactive':
        return Colors.grey.shade600;
      case 'verified':
        return Colors.orange.shade700;
      default:
        return Colors.blue.shade700;
    }
  }
}
