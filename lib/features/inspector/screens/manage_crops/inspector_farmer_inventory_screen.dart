import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:agriyukt_app/features/farmer/screens/view_crop_screen.dart';
import 'package:agriyukt_app/features/farmer/screens/add_crop_screen.dart'; // 🚀 FIXED IMPORT
import 'inspector_crop_card.dart';
import 'inspector_edit_crop_screen.dart';

class InspectorFarmerInventoryScreen extends StatefulWidget {
  final String farmerName;
  final String farmerId;

  const InspectorFarmerInventoryScreen({
    super.key,
    required this.farmerName,
    required this.farmerId,
  });

  @override
  State<InspectorFarmerInventoryScreen> createState() =>
      _InspectorFarmerInventoryScreenState();
}

class _InspectorFarmerInventoryScreenState
    extends State<InspectorFarmerInventoryScreen> {
  bool showActive = true;
  final _client = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";

  // 🎨 Inspector Theme Color
  final Color _inspectorColor = const Color(0xFF512DA8);

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      final query = _searchController.text.trim().toLowerCase();
      // 🚀 PRODUCTION FIX: Prevent unnecessary UI rebuilds
      if (_searchQuery != query) {
        setState(() {
          _searchQuery = query;
        });
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // 🛡️ PRODUCTION FIX: Safe Deletion with Foreign Key checks
  Future<void> _confirmAndDeleteCrop(Map<String, dynamic> crop) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Delete Crop?",
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Text(
            "Are you sure you want to delete '${crop['crop_name'] ?? 'this crop'}'? This cannot be undone.",
            style: GoogleFonts.poppins(fontSize: 14)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text("Cancel",
                  style: GoogleFonts.poppins(
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w600))),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8))),
              onPressed: () => Navigator.pop(context, true),
              child: Text("Delete",
                  style: GoogleFonts.poppins(
                      color: Colors.white, fontWeight: FontWeight.bold))),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _client.from('crops').delete().eq('id', crop['id']);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Crop deleted successfully',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
              backgroundColor: Colors.green.shade700));
        }
      } catch (e) {
        if (mounted) {
          String errorMsg = 'Failed to delete crop. Check connection.';
          if (e.toString().contains('violates foreign key') ||
              e.toString().contains('update or delete on table')) {
            errorMsg = 'Cannot delete: This crop is linked to active orders.';
          }
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(errorMsg,
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
              backgroundColor: Colors.red.shade700));
        }
      }
    }
  }

  double _parseQuantity(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    if (val is String) {
      String clean = val.replaceAll(RegExp(r'[^0-9.]'), '');
      return double.tryParse(clean) ?? 0.0;
    }
    return 0.0;
  }

  // 🚀 PRODUCTION FIX: Mathematically safe number formatting (No dangerous Regex)
  String _formatNumber(double num) {
    return num.truncateToDouble() == num
        ? num.toInt().toString()
        : num.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: _inspectorColor,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Manage Crops",
                style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            Text("${widget.farmerName}'s Inventory",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    GoogleFonts.poppins(fontSize: 12, color: Colors.white70)),
          ],
        ),
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Column(
          children: [
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 5,
                          offset: const Offset(0, 2))
                    ]),
                child: TextField(
                  controller: _searchController,
                  style:
                      GoogleFonts.poppins(fontSize: 14, color: Colors.black87),
                  decoration: InputDecoration(
                    hintText: "Search your crops...",
                    hintStyle: GoogleFonts.poppins(
                        color: Colors.grey.shade400, fontSize: 14),
                    prefixIcon: Icon(Icons.search, color: _inspectorColor),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear,
                                color: Colors.grey, size: 20),
                            onPressed: () => _searchController.clear())
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(child: _buildTabButton("Active Crops", true)),
                  const SizedBox(width: 10),
                  Expanded(child: _buildTabButton("Inactive/Sold", false)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                // 🚀 PRODUCTION LOGIC: Supabase Real-time Stream listens for DB changes instantly
                stream: _client
                    .from('crops')
                    .stream(primaryKey: ['id'])
                    .eq('farmer_id', widget.farmerId)
                    .order('created_at', ascending: false),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                        child: Text("Connection interrupted. Retrying...",
                            style: GoogleFonts.poppins(
                                color: Colors.red.shade700)));
                  }
                  if (!snapshot.hasData) {
                    return Center(
                        child:
                            CircularProgressIndicator(color: _inspectorColor));
                  }

                  final crops = snapshot.data!;
                  final filteredCrops = crops.where((crop) {
                    final status = crop['status'] ?? 'Active';
                    final double qty = _parseQuantity(crop['quantity']) +
                        _parseQuantity(crop['quantity_kg']);

                    final isActiveGroup =
                        ['Active', 'Verified', 'Growing'].contains(status) &&
                            (qty >= 0);
                    final matchesTab =
                        showActive ? isActiveGroup : !isActiveGroup;

                    final cropName = (crop['crop_name'] ?? crop['name'] ?? "")
                        .toString()
                        .toLowerCase();
                    final matchesSearch =
                        _searchQuery.isEmpty || cropName.contains(_searchQuery);

                    return matchesTab && matchesSearch;
                  }).toList();

                  if (filteredCrops.isEmpty) {
                    return Center(
                        child: Text(
                            _searchQuery.isNotEmpty
                                ? "No crops match '$_searchQuery'"
                                : (showActive
                                    ? "No active crops found"
                                    : "No inactive crops found"),
                            style:
                                GoogleFonts.poppins(color: Colors.grey[500])));
                  }

                  return ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8)
                            .copyWith(bottom: 100),
                    itemCount: filteredCrops.length,
                    itemBuilder: (context, index) {
                      final crop = filteredCrops[index];

                      double qtyNum = _parseQuantity(crop['quantity']);
                      if (qtyNum == 0) {
                        qtyNum = _parseQuantity(crop['quantity_kg']);
                      }

                      String qtyValue = _formatNumber(qtyNum);

                      final double reserved =
                          _parseQuantity(crop['reserved_kg']);
                      String unit = crop['unit'] ?? "Kg";
                      String displayQty = "$qtyValue $unit";
                      if (reserved > 0) {
                        displayQty += " (${_formatNumber(reserved)} Reserved)";
                      }

                      String imageUrl = crop['image_url'] ?? '';
                      if (imageUrl.isNotEmpty && !imageUrl.startsWith('http')) {
                        imageUrl = _client.storage
                            .from('crop_images')
                            .getPublicUrl(imageUrl);
                      } else if (imageUrl.isEmpty) {
                        imageUrl = "https://via.placeholder.com/150";
                      }

                      String hDate = crop['harvest_date'] ?? 'N/A';
                      String aDate = crop['available_from'] ?? 'N/A';
                      try {
                        if (hDate != 'N/A') {
                          final d = DateTime.parse(hDate);
                          hDate = "${d.day}/${d.month}/${d.year}";
                        }
                        if (aDate != 'N/A') {
                          final d = DateTime.parse(aDate);
                          aDate = "${d.day}/${d.month}/${d.year}";
                        }
                      } catch (_) {}

                      double priceNum = _parseQuantity(crop['price']);
                      if (priceNum == 0) {
                        priceNum = _parseQuantity(crop['price_per_qty']);
                      }
                      String priceVal = _formatNumber(priceNum);

                      return InspectorCropCard(
                        cropName: crop['crop_name'] ?? "Unknown Crop",
                        price: "₹$priceVal / $unit",
                        quantity: displayQty,
                        harvestDate: hDate,
                        availableDate: aDate,
                        imageUrl: imageUrl,
                        status: crop['status'] ?? 'Active',
                        onViewTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => ViewCropScreen(
                                    crop: crop, hideEditButton: false))),
                        onEditTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => InspectorEditCropScreen(
                                    cropData: crop,
                                    farmerId: widget.farmerId))),
                        onDeleteTap: () => _confirmAndDeleteCrop(crop),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
                // 🚀 FIXED: Call AddCropScreen instead of AddCropTab
                builder: (_) => AddCropScreen(farmerId: widget.farmerId))),
        backgroundColor: _inspectorColor,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text("Add Crop",
            style: GoogleFonts.poppins(
                color: Colors.white, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildTabButton(String text, bool isActiveTab) {
    bool isSelected = showActive == isActiveTab;
    return GestureDetector(
      onTap: () => setState(() => showActive = isActiveTab),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
            color: isSelected ? _inspectorColor : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border:
                isSelected ? null : Border.all(color: Colors.grey.shade300)),
        child: Center(
            child: Text(text,
                style: GoogleFonts.poppins(
                    color: isSelected ? Colors.white : Colors.grey[600],
                    fontWeight: FontWeight.w600,
                    fontSize: 13))),
      ),
    );
  }
}
