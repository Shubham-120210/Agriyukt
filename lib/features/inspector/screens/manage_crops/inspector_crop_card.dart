import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:agriyukt_app/features/farmer/farmer_translations.dart';

class InspectorCropCard extends StatelessWidget {
  final String cropName;
  final String price;
  final String quantity;
  final String harvestDate;
  final String availableDate;
  final String imageUrl;
  final String status;

  final VoidCallback onViewTap;
  final VoidCallback onEditTap;
  final VoidCallback onDeleteTap;

  final ImageProvider? imageProvider;
  final String? heroTag;

  // 🎨 STRICT THEME COLOR: Inspector Purple
  final Color _inspectorColor = const Color(0xFF512DA8);

  const InspectorCropCard({
    super.key,
    required this.cropName,
    required this.price,
    required this.quantity,
    required this.harvestDate,
    required this.availableDate,
    required this.imageUrl,
    required this.status,
    required this.onViewTap,
    required this.onEditTap,
    required this.onDeleteTap,
    this.imageProvider,
    this.heroTag,
  });

  String _text(BuildContext context, String key, {String fallback = ""}) {
    String trans = FarmerText.get(context, key);
    return trans == key && fallback.isNotEmpty ? fallback : trans;
  }

  // 🚀 PRODUCTION FIX: Added .trim() to prevent DB formatting errors from breaking colors
  Color _getStatusColor(String currentStatus) {
    switch (currentStatus.trim().toLowerCase()) {
      case 'active':
        return const Color(0xFF2E7D32); // Green
      case 'sold':
        return Colors.red.shade700; // Red
      case 'inactive':
        return Colors.grey.shade600; // Grey
      case 'verified':
        return Colors.orange.shade800; // Orange
      default:
        return const Color(0xFF2E7D32);
    }
  }

  // 🚀 PRODUCTION FIX: Strict URL Validator prevents CachedNetworkImage crashes
  bool get _isValidUrl {
    final url = imageUrl.trim();
    return url.isNotEmpty &&
        (url.startsWith('http') || url.startsWith('https'));
  }

  @override
  Widget build(BuildContext context) {
    // 🚀 PRODUCTION FIX: Deterministic Hero Tag.
    // Prevents both "Multiple heroes share the same tag" crash AND "UniqueKey Jitter" during scrolling.
    final safeHeroTag = heroTag ??
        (imageUrl.isNotEmpty
            ? imageUrl
            : "crop_${cropName}_${quantity}_${price}");
    final statusColor = _getStatusColor(status);

    return Semantics(
      label: "Crop card for $cropName",
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color:
                  Colors.grey.shade200), // Added subtle border for premium feel
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize:
              MainAxisSize.min, // 🔒 FLUID GEOMETRY: Prevents overflow
          children: [
            Stack(
              children: [
                Hero(
                  tag: safeHeroTag,
                  child: ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(16)),
                    child: Container(
                      height: 180,
                      width: double.infinity,
                      color: Colors.grey[100],
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: onViewTap,
                          child: _buildImage(),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: Tooltip(
                    message: _text(context, 'delete', fallback: "Delete"),
                    child: Material(
                      color: Colors.white.withOpacity(0.9),
                      shape: const CircleBorder(),
                      elevation: 2,
                      shadowColor: Colors.black12,
                      child: InkWell(
                        onTap: onDeleteTap,
                        customBorder: const CircleBorder(),
                        child: Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          child: Icon(Icons.delete_outline,
                              color: Colors.red.shade600, size: 20),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.95),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [
                          BoxShadow(
                              color: Colors.black12,
                              blurRadius: 4,
                              offset: Offset(0, 2))
                        ]),
                    child: Text(
                      _text(context, status.trim().toLowerCase(),
                              fallback: status)
                          .toUpperCase(),
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min, // 🔒 FLUID GEOMETRY
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          cropName,
                          style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87),
                          maxLines:
                              2, // 🔒 Gives text room to breathe if localized string is long
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        price,
                        style: GoogleFonts.poppins(
                            fontSize: 18, // Slightly larger for emphasis
                            fontWeight: FontWeight.bold,
                            color:
                                _inspectorColor), // ✅ Matches Inspector Purple
                        maxLines: 1,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildInfoRow(Icons.scale, quantity, "Quantity"),
                  const SizedBox(height: 6),
                  _buildInfoRow(
                      Icons.agriculture,
                      "${_text(context, 'harvest', fallback: 'Harvest')}: $harvestDate",
                      "Harvest Date"),
                  const SizedBox(height: 6),
                  _buildInfoRow(
                      Icons.calendar_today,
                      "${_text(context, 'available', fallback: 'Available')}: $availableDate",
                      "Availability Date"),
                  const SizedBox(height: 20),

                  // Row 1: View & Edit Buttons
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: onViewTap,
                          icon: const Icon(Icons.visibility,
                              size: 18, color: Colors.white),
                          label: Text(
                              _text(context, 'view', fallback: "View Details"),
                              style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                _inspectorColor, // ✅ Matches Inspector Purple
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onEditTap,
                          icon: Icon(Icons.edit,
                              size: 18,
                              color:
                                  _inspectorColor), // ✅ Matches Inspector Purple
                          label: Text(
                              _text(context, 'edit', fallback: "Edit/Verify"),
                              style: GoogleFonts.poppins(
                                  color:
                                      _inspectorColor, // ✅ Matches Inspector Purple
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                                color: _inspectorColor,
                                width: 1.2), // ✅ Matches Inspector Purple
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
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

  Widget _buildImage() {
    if (imageProvider != null) {
      return Image(
          image: imageProvider!,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _placeholder());
    }
    // 🚀 PRODUCTION FIX: Using safe URL validator
    if (_isValidUrl) {
      return CachedNetworkImage(
        imageUrl: imageUrl.trim(),
        fit: BoxFit.cover,
        // 🚀 PRODUCTION FIX: Dual-axis constraints prevent Out-Of-Memory List crashes
        memCacheHeight: 400,
        memCacheWidth: 400,
        placeholder: (context, url) => Container(
            color: Colors.grey[100],
            child: Center(
                child: CircularProgressIndicator(
                    color: _inspectorColor
                        .withOpacity(0.5), // ✅ Matches Inspector Purple
                    strokeWidth: 2))),
        errorWidget: (context, url, error) => _placeholder(),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    return Container(
        height: 180,
        width: double.infinity,
        color: Colors.grey[100],
        child: Icon(Icons.grass, size: 50, color: Colors.grey.shade400));
  }

  Widget _buildInfoRow(IconData icon, String text, String semanticLabel) {
    return Semantics(
      label: "$semanticLabel: $text",
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey[500]),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: Colors.grey[800],
                      fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}
