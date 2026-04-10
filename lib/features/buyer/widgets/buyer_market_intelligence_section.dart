import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:agriyukt_app/core/providers/language_provider.dart';

class BuyerMarketIntelligence extends StatefulWidget {
  final String buyerId;
  final Color themeColor;

  const BuyerMarketIntelligence({
    super.key,
    required this.buyerId,
    this.themeColor = const Color(0xFF1565C0), // Buyer Blue
  });

  @override
  State<BuyerMarketIntelligence> createState() =>
      _BuyerMarketIntelligenceState();
}

class _BuyerMarketIntelligenceState extends State<BuyerMarketIntelligence>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  bool _hasError = false;
  List<Map<String, dynamic>> _marketData = [];
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000))
      ..repeat(reverse: true);
    _fetchMarketData();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  String _normalizeCropName(String name) {
    if (name.isEmpty) return "";
    String trimmed = name.trim().toLowerCase();
    return "${trimmed[0].toUpperCase()}${trimmed.substring(1)}";
  }

  // 🚀 Format to clean, lowercase units for the small suffix
  String _formatUnit(String? rawUnit) {
    if (rawUnit == null || rawUnit.isEmpty) return "kg";
    String lower = rawUnit.toLowerCase().trim();
    if (lower == 'quintal (q)' || lower == 'quintal') return "q";
    if (lower == 'kilogram' || lower == 'kg') return "kg";
    if (lower == 'ton' || lower == 'tonne') return "ton";
    return lower;
  }

  String _formatUpdatedTime(String? isoString) {
    if (isoString == null || isoString.isEmpty) return "Recently";
    try {
      DateTime dt = DateTime.parse(isoString).toLocal();
      return DateFormat('MMM d, h:mm a').format(dt);
    } catch (e) {
      return "Recently";
    }
  }

  Future<void> _fetchMarketData() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });
    }

    try {
      await _supabase.functions
          .invoke('fetch-crop-rates')
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      debugPrint("🚨 ACTUAL CLOUD ERROR: $e");
    }

    try {
      // 1. Fetch exactly what the buyer has in their Watchlist/Favorites
      final likedResponse = await _supabase
          .from('favorites')
          .select('crop:crops(*)')
          .eq('user_id', widget.buyerId)
          .timeout(const Duration(seconds: 10));

      List<String> targetCropsQuery = [];
      Map<String, String> varietyMap = {};
      Map<String, String> imageMap = {};

      if (likedResponse != null && (likedResponse as List).isNotEmpty) {
        for (var item in likedResponse) {
          final crop = item['crop'];
          if (crop != null && crop['crop_name'] != null) {
            String originalName = crop['crop_name'].toString().trim();
            String nameLower = originalName.toLowerCase();

            if (!targetCropsQuery.contains(originalName)) {
              targetCropsQuery.add(originalName);
            }

            String variety = crop['variety']?.toString() ??
                crop['crop_type']?.toString() ??
                '';
            varietyMap[nameLower] = variety;

            if (crop['image_url'] != null &&
                crop['image_url'].toString().isNotEmpty) {
              imageMap[nameLower] = crop['image_url'].toString();
            }
          }
        }
      }

      // 2. STRICT PERSONALIZATION: If Watchlist is empty, stop and show Empty State
      if (targetCropsQuery.isEmpty) {
        if (mounted) {
          setState(() {
            _marketData = [];
            _isLoading = false;
          });
        }
        return;
      }

      // 3. Fetch AI Predictions ONLY for the Watchlist crops
      final aiResponse = await _supabase
          .from('market_predictions')
          .select()
          .inFilter('crop_name', targetCropsQuery)
          .timeout(const Duration(seconds: 10));

      // 4. Merge Data
      List<Map<String, dynamic>> finalData = [];

      for (var data in aiResponse) {
        Map<String, dynamic> item = Map<String, dynamic>.from(data);
        String dbCropName = (item['crop_name'] ?? '').toString().trim();
        String dbCropLower = dbCropName.toLowerCase();

        item['personal_image'] = imageMap[dbCropLower] ?? '';
        item['personal_variety'] = varietyMap[dbCropLower] ?? '';

        finalData.add(item);
      }

      if (mounted) {
        setState(() {
          _marketData = finalData;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("🚨 Buyer Market Intelligence Error: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  void _showFullMarketSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Color(0xFFF4F6F8),
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 16),
              width: 50,
              height: 5,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(10)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("My Watchlist Market",
                      style: GoogleFonts.poppins(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87)),
                  IconButton(
                      icon:
                          const Icon(Icons.close, color: Colors.grey, size: 28),
                      onPressed: () => Navigator.pop(context))
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                physics: const BouncingScrollPhysics(),
                itemCount: _marketData.length,
                itemBuilder: (context, index) =>
                    _buildLivePriceTile(_marketData[index]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Provider.of<LanguageProvider>(context);

    if (_hasError) return _buildErrorState();
    if (_isLoading) return _buildSkeleton();
    if (_marketData.isEmpty) return _buildEmptyState();

    final previewData = _marketData.take(3).toList();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 24,
              offset: const Offset(0, 8))
        ],
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.only(top: 24, bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Text("🔮 ", style: TextStyle(fontSize: 22)),
                    RichText(
                      text: TextSpan(
                        text: "Prediction ",
                        style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87),
                        children: [
                          TextSpan(
                            text: "(Tomorrow)",
                            style: GoogleFonts.poppins(
                                color: widget.themeColor,
                                fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                IconButton(
                    onPressed: _fetchMarketData,
                    icon: Icon(Icons.refresh,
                        size: 22, color: Colors.grey.shade400))
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 🚀 HEIGHT INCREASED TO 240
          SizedBox(
            height: 240,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: _marketData.length,
              itemBuilder: (context, i) => _buildPredictionCard(_marketData[i]),
            ),
          ),

          const SizedBox(height: 36),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text("📊 ", style: TextStyle(fontSize: 22)),
                Text("Live Wholesale Prices",
                    style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87)),
              ],
            ),
          ),
          const SizedBox(height: 20),

          ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            itemCount: previewData.length,
            itemBuilder: (context, index) =>
                _buildLivePriceTile(previewData[index]),
          ),

          if (_marketData.length > 3)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _showFullMarketSheet,
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(
                          color: widget.themeColor.withOpacity(0.5),
                          width: 1.5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16))),
                  child: Text("View All My Watchlist Data",
                      style: GoogleFonts.poppins(
                          color: widget.themeColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPredictionCard(Map<String, dynamic> data) {
    final bool isUpward = data['is_upward'] == true;
    final double predictedPrice =
        double.tryParse(data['predicted_price']?.toString() ?? '0') ?? 0.0;
    final double trendPercent =
        double.tryParse(data['trend_percent']?.toString() ?? '0') ?? 0.0;

    final int decimals = predictedPrice < 100 ? 1 : 0;
    final String imageUrl = data['personal_image'] ?? '';
    final String emoji = data['emoji'] ?? '🌱';
    final String cropName = _normalizeCropName(data['crop_name'] ?? 'Crop');
    final String formattedUnit = _formatUnit(data['unit']?.toString());

    final Color startColor =
        isUpward ? const Color(0xFF4CAF50) : const Color(0xFFFF9800);
    final Color endColor =
        isUpward ? const Color(0xFF009688) : const Color(0xFFF44336);

    return Container(
      width: 165,
      margin: const EdgeInsets.only(right: 14, bottom: 12, top: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [startColor, endColor],
        ),
        boxShadow: [
          BoxShadow(
            color: startColor.withOpacity(0.3),
            blurRadius: 16,
            offset: const Offset(0, 8),
          )
        ],
        border: Border.all(color: Colors.white.withOpacity(0.4), width: 1.5),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: -20,
            right: -20,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.15),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildCropAvatar(imageUrl, emoji, 75, isRound: true),
                Transform.translate(
                  offset: const Offset(0, -12),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.95),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 4,
                              offset: const Offset(0, 2))
                        ]),
                    child: Text(
                      cropName,
                      style: GoogleFonts.poppins(
                        color: Colors.black87,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          "₹${predictedPrice.toStringAsFixed(decimals)}",
                          style: GoogleFonts.jetBrainsMono(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1,
                            shadows: [
                              Shadow(
                                color: Colors.black.withOpacity(0.15),
                                offset: const Offset(0, 2),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          "/ $formattedUnit",
                          style: GoogleFonts.poppins(
                            color: Colors.white.withOpacity(0.85),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(isUpward ? Icons.trending_up : Icons.trending_down,
                          color: Colors.white, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        "${trendPercent.toStringAsFixed(1)}%",
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLivePriceTile(Map<String, dynamic> data) {
    final double livePrice =
        double.tryParse(data['live_price']?.toString() ?? '0') ?? 0.0;
    final double predictedPrice =
        double.tryParse(data['predicted_price']?.toString() ?? '0') ?? 0.0;

    int decimals = livePrice < 100 ? 1 : 0;
    String formattedTime = _formatUpdatedTime(data['last_updated']?.toString());
    String imageUrl = data['personal_image'] ?? '';
    String emoji = data['emoji'] ?? '🌱';
    String variety = data['personal_variety'] ?? '';
    String formattedUnit = _formatUnit(data['unit']?.toString());

    final bool isUpward = data['is_upward'] == true;
    final Color trendColor =
        isUpward ? Colors.green.shade700 : Colors.red.shade700;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildCropAvatar(imageUrl, emoji, 68,
              isRound: false), // 🚀 Massive 68px Crop Image
          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  data['crop_name'] ?? '',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (variety.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    variety,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ]
              ],
            ),
          ),

          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      "₹${livePrice.toStringAsFixed(decimals)}",
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: widget.themeColor,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Text(
                      "/ $formattedUnit",
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(isUpward ? Icons.trending_up : Icons.trending_down,
                      color: trendColor, size: 12),
                  const SizedBox(width: 4),
                  Text(
                    "₹${predictedPrice.toStringAsFixed(decimals)}",
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: trendColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCropAvatar(String imageUrl, String emoji, double size,
      {bool isRound = false}) {
    if (imageUrl.isNotEmpty) {
      String finalUrl = imageUrl.startsWith('http')
          ? imageUrl
          : _supabase.storage.from('crop_images').getPublicUrl(imageUrl);
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(isRound ? 100 : 16),
          color: Colors.white,
          boxShadow: isRound
              ? [
                  BoxShadow(
                      color: Colors.black12,
                      blurRadius: 8,
                      offset: const Offset(0, 4))
                ]
              : [],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(isRound ? 100 : 16),
          child: CachedNetworkImage(
            imageUrl: finalUrl,
            fit: BoxFit.cover,
            placeholder: (context, url) => Container(
                color: Colors.grey.shade100,
                child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 2))),
            errorWidget: (context, url, error) =>
                _buildEmojiAvatar(emoji, size, isRound),
          ),
        ),
      );
    }
    return _buildEmojiAvatar(emoji, size, isRound);
  }

  Widget _buildEmojiAvatar(String emoji, double size, bool isRound) {
    return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(isRound ? 100 : 16),
            boxShadow: isRound
                ? [
                    BoxShadow(
                        color: Colors.black12,
                        blurRadius: 8,
                        offset: const Offset(0, 4))
                  ]
                : [],
            border: isRound ? null : Border.all(color: Colors.grey.shade200)),
        child: Text(emoji, style: TextStyle(fontSize: size * 0.55)));
  }

  // 🚀 EMPTY WATCHLIST STATE
  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 24,
                offset: const Offset(0, 8))
          ],
          border: Border.all(color: Colors.grey.shade200)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: widget.themeColor.withOpacity(0.05),
                shape: BoxShape.circle),
            child:
                Icon(Icons.favorite_border, size: 48, color: widget.themeColor),
          ),
          const SizedBox(height: 20),
          Text("Empty Watchlist",
              style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87)),
          const SizedBox(height: 8),
          Text(
              "Like a crop in the marketplace to instantly see its AI price prediction right here.",
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 14, color: Colors.grey.shade600, height: 1.5)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
              onPressed: _fetchMarketData,
              style: ElevatedButton.styleFrom(
                  backgroundColor: widget.themeColor,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16))),
              icon: const Icon(Icons.refresh, size: 18),
              label: Text("Refresh Data",
                  style: GoogleFonts.poppins(fontWeight: FontWeight.bold)))
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.cloud_off, color: Colors.grey, size: 40),
      const SizedBox(height: 12),
      Text("Cloud connection lost",
          style: GoogleFonts.poppins(color: Colors.grey.shade600)),
      TextButton(
          onPressed: _fetchMarketData,
          child: Text("Retry",
              style: TextStyle(
                  color: widget.themeColor, fontWeight: FontWeight.bold)))
    ]));
  }

  Widget _buildSkeleton() {
    return FadeTransition(
        opacity: _pulseController,
        child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
                height: 240,
                width: double.infinity,
                decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey.shade200),
                    borderRadius: BorderRadius.circular(32)))));
  }
}
