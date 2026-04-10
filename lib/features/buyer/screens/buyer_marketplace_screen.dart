import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:agriyukt_app/features/buyer/screens/buyer_crop_details_screen.dart';

class BuyerMarketplaceScreen extends StatefulWidget {
  const BuyerMarketplaceScreen({super.key});

  @override
  State<BuyerMarketplaceScreen> createState() => _BuyerMarketplaceScreenState();
}

class _BuyerMarketplaceScreenState extends State<BuyerMarketplaceScreen> {
  final _client = Supabase.instance.client;

  String _searchQuery = "";
  String _selectedCategory = "All";
  bool _isLoading = true;
  String? _errorMessage;

  List<Map<String, dynamic>> _allCrops = [];
  List<Map<String, dynamic>> _filteredCrops = [];
  Set<String> _likedCropIds = {};

  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  RealtimeChannel? _cropsChannel;

  static const Color _primaryBlue = Color(0xFF1565C0);
  static const Color _surfaceBg = Color(0xFFF4F6F8);

  final List<String> _categories = [
    "All",
    "Vegetables",
    "Fruits",
    "Grains",
    "Pulses",
    "Flowers",
    "Oils"
  ];

  @override
  void initState() {
    super.initState();
    _fetchMarketData();
    _setupRealtimeCrops();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _fetchMarketData(isSilent: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    if (_cropsChannel != null) _client.removeChannel(_cropsChannel!);
    super.dispose();
  }

  void _setupRealtimeCrops() {
    if (_cropsChannel != null) _client.removeChannel(_cropsChannel!);
    _cropsChannel = _client.channel('public:crops_market').onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'crops',
          callback: (_) => _fetchMarketData(isSilent: true),
        );
    _cropsChannel?.subscribe();
  }

  Future<void> _fetchMarketData({bool isSilent = false}) async {
    try {
      final userId = _client.auth.currentUser?.id;

      if (!isSilent && _allCrops.isEmpty && mounted) {
        setState(() {
          _isLoading = true;
          _errorMessage = null;
        });
      }

      // ✅ MACRO-FETCH ENGINE: Pulls up to 1000 active crops to avoid local pagination traps
      final response = await _client
          .from('crops')
          .select(
              '*, profiles:farmer_id (first_name, last_name, district, taluka, village)')
          .eq('status', 'Active')
          .order('created_at', ascending: false)
          .limit(1000);

      if (userId != null) {
        try {
          final favResponse = await _client
              .from('favorites')
              .select('crop_id')
              .eq('user_id', userId);
          final favData = favResponse as List<dynamic>;
          _likedCropIds = favData.map((e) => e['crop_id'].toString()).toSet();
        } catch (_) {}
      }

      if (mounted) {
        final newCrops =
            List<Map<String, dynamic>>.from(response).where((crop) {
          final qtyRaw = crop['quantity'] ?? crop['quantity_kg'] ?? 0;
          final reservedRaw = crop['reserved_quantity'] ?? 0;
          final double total =
              (num.tryParse(qtyRaw.toString()) ?? 0).toDouble();
          final double reserved =
              (num.tryParse(reservedRaw.toString()) ?? 0).toDouble();
          return (total - reserved) > 0;
        }).toList();

        // ✅ SILENT SYNC LOCK: Prevents scroll-jumping if data structure hasn't changed
        if (_allCrops.length != newCrops.length || !_isLoading) {
          setState(() {
            _allCrops = newCrops;
            _isLoading = false;
            _errorMessage = null;
            _runFilter();
          });
        }
      }
    } catch (e) {
      debugPrint("Market Data Error: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          if (_allCrops.isEmpty)
            _errorMessage = "Connection error. Pull to refresh.";
        });
      }
    }
  }

  void _runFilter() {
    setState(() {
      _filteredCrops = _allCrops.where((crop) {
        final name = (crop['crop_name'] ?? crop['name'] ?? '')
            .toString()
            .toLowerCase()
            .trim();
        final variety = (crop['variety'] ?? '').toString().toLowerCase().trim();
        final category = (crop['category'] ?? '').toString();

        final matchesSearch = _searchQuery.isEmpty ||
            name.contains(_searchQuery) ||
            variety.contains(_searchQuery);
        final matchesCategory =
            _selectedCategory == "All" || category == _selectedCategory;

        return matchesSearch && matchesCategory;
      }).toList();
    });
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _searchQuery = query.toLowerCase().trim();
      _runFilter();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surfaceBg,
      resizeToAvoidBottomInset:
          false, // Prevents keyboard from crushing the list
      appBar: AppBar(
        backgroundColor: _primaryBlue,
        elevation: 0,
        titleSpacing: 16,
        // ✅ HEADER COMPRESSED: Text removed, Search Bar takes the exact title slot
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
              hintText: "Search wheat, tomato, etc...",
              hintStyle: GoogleFonts.poppins(
                  color: Colors.grey.shade400, fontSize: 13),
              prefixIcon: Icon(Icons.search_rounded,
                  color: Colors.grey.shade400, size: 20),
              suffixIcon: _searchController.text.isNotEmpty
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
        bottom: PreferredSize(
          preferredSize:
              const Size.fromHeight(52), // Perfectly sized for chips + padding
          child: Container(
            height: 40,
            margin: const EdgeInsets.only(bottom: 12),
            child: ListView.separated(
              physics: const BouncingScrollPhysics(),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final cat = _categories[index];
                final isSel = _selectedCategory == cat;
                return ChoiceChip(
                  label: Text(cat),
                  selected: isSel,
                  onSelected: (val) {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedCategory = cat);
                    _runFilter();
                  },
                  selectedColor: Colors.white,
                  backgroundColor: _primaryBlue.withOpacity(0.3),
                  showCheckmark: false,
                  labelStyle: GoogleFonts.poppins(
                      color: isSel ? _primaryBlue : Colors.white,
                      fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                      fontSize: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide.none),
                );
              },
            ),
          ),
        ),
      ),
      // ✅ SINGLE-TREE GEOMETRY: Ensures pull-to-refresh works even on empty states
      body: RefreshIndicator(
        onRefresh: () async {
          HapticFeedback.lightImpact();
          await _fetchMarketData(isSilent: true);
        },
        color: _primaryBlue,
        backgroundColor: Colors.white,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, MediaQuery.of(context).padding.bottom + 40),
          itemCount: _isLoading && _allCrops.isEmpty
              ? 4
              : _filteredCrops.isEmpty || _errorMessage != null
                  ? 1
                  : _filteredCrops.length,
          separatorBuilder: (_, __) => const SizedBox(height: 16),
          itemBuilder: (context, index) {
            // 1. Error State
            if (_errorMessage != null && _allCrops.isEmpty) {
              return SizedBox(
                height: MediaQuery.of(context).size.height * 0.6,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.wifi_off_rounded,
                        size: 50, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    Text("Connection Error",
                        style: GoogleFonts.poppins(
                            color: Colors.black87,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(_errorMessage!,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                            color: Colors.grey.shade500, fontSize: 13)),
                  ],
                ),
              );
            }

            // 2. Loading State
            if (_isLoading && _allCrops.isEmpty) {
              return const _SkeletonMarketCard();
            }

            // 3. Empty State
            if (_filteredCrops.isEmpty) {
              return SizedBox(
                height: MediaQuery.of(context).size.height * 0.6,
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
                      child: Icon(Icons.shopping_basket_outlined,
                          size: 50, color: _primaryBlue.withOpacity(0.5)),
                    ),
                    const SizedBox(height: 20),
                    Text("No crops found",
                        style: GoogleFonts.poppins(
                            color: Colors.black87,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(
                        "Try selecting a different category\nor adjusting your search.",
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                            color: Colors.grey.shade500, fontSize: 13)),
                  ],
                ),
              );
            }

            // 4. Actual Data
            final crop = _filteredCrops[index];
            return _IsolatedMarketCard(
              key: ValueKey(crop['id']
                  .toString()), // Strict identifying key to lock layout
              crop: crop,
              isInitiallyLiked: _likedCropIds.contains(crop['id'].toString()),
              onRefreshRequested: () => _fetchMarketData(isSilent: true),
            );
          },
        ),
      ),
    );
  }
}

// ============================================================================
// ✅ ISOLATED STATEFUL CARD: Prevents full-screen rebuilds on Like button tap
// ============================================================================
class _IsolatedMarketCard extends StatefulWidget {
  final Map<String, dynamic> crop;
  final bool isInitiallyLiked;
  final VoidCallback onRefreshRequested;

  const _IsolatedMarketCard({
    super.key,
    required this.crop,
    required this.isInitiallyLiked,
    required this.onRefreshRequested,
  });

  @override
  State<_IsolatedMarketCard> createState() => _IsolatedMarketCardState();
}

class _IsolatedMarketCardState extends State<_IsolatedMarketCard> {
  late bool _isLiked;

  @override
  void initState() {
    super.initState();
    _isLiked = widget.isInitiallyLiked;
  }

  @override
  void didUpdateWidget(covariant _IsolatedMarketCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isInitiallyLiked != widget.isInitiallyLiked) {
      _isLiked = widget.isInitiallyLiked;
    }
  }

  Future<void> _toggleLike() async {
    HapticFeedback.lightImpact();
    setState(() => _isLiked = !_isLiked);

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    final cropId = widget.crop['id'].toString();

    try {
      if (_isLiked) {
        await Supabase.instance.client
            .from('favorites')
            .upsert({'user_id': userId, 'crop_id': cropId});
      } else {
        await Supabase.instance.client
            .from('favorites')
            .delete()
            .match({'user_id': userId, 'crop_id': cropId});
      }
    } catch (e) {
      debugPrint("Favorite Sync Error: $e");
      if (mounted) setState(() => _isLiked = !_isLiked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final crop = widget.crop;
    final String cropId = crop['id'].toString();
    final String cropName = crop['crop_name'] ?? "Unknown Crop";
    final String variety = crop['variety'] ?? '';

    String displayTitle = cropName;
    if (variety.isNotEmpty && variety.toLowerCase() != 'null') {
      displayTitle = "$cropName : $variety";
    }

    final double priceRaw =
        (num.tryParse(crop['price']?.toString() ?? '0') ?? 0).toDouble();
    final String formattedPrice =
        NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
            .format(priceRaw);

    final qtyRaw = crop['quantity'] ?? crop['quantity_kg'] ?? 0;
    final reservedRaw = crop['reserved_quantity'] ?? 0;
    final double total = (num.tryParse(qtyRaw.toString()) ?? 0).toDouble();
    final double reserved =
        (num.tryParse(reservedRaw.toString()) ?? 0).toDouble();

    double available = total - reserved;
    if (available < 0) available = 0;

    String qtyValue =
        available.toString().replaceAll(RegExp(r"([.]*0)(?!.*\d)"), "");
    final String displayQty = "$qtyValue ${crop['unit'] ?? 'kg'}";

    final farmerData = crop['profiles'] is Map ? crop['profiles'] : {};
    String farmerName = farmerData['first_name'] != null
        ? "${farmerData['first_name']} ${farmerData['last_name'] ?? ''}".trim()
        : "AgriYukt Farmer";
    String location =
        "${farmerData['district'] ?? ''}, ${farmerData['state'] ?? ''}"
            .replaceAll(RegExp(r'^, |,$'), '')
            .trim();

    return RepaintBoundary(
      child: GestureDetector(
        onTap: () async {
          FocusScope.of(context).unfocus();
          await Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      BuyerCropDetailsScreen(crop: crop, cropData: crop)));
          widget.onRefreshRequested();
        },
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 15,
                  offset: const Offset(0, 5))
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 🖼️ RIGID IMAGE HEADER
              Stack(
                children: [
                  ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(20)),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Container(
                        color: Colors.grey.shade100,
                        width: double.infinity,
                        child: Hero(
                          tag: 'market_crop_$cropId',
                          child: (crop['image_url'] == null ||
                                  crop['image_url'].isEmpty)
                              ? Icon(Icons.grass_rounded,
                                  size: 50, color: Colors.grey.shade300)
                              : CachedNetworkImage(
                                  imageUrl: crop['image_url']
                                          .toString()
                                          .startsWith('http')
                                      ? crop['image_url']
                                      : Supabase.instance.client.storage
                                          .from('crop_images')
                                          .getPublicUrl(crop['image_url']),
                                  fit: BoxFit.cover,
                                  memCacheWidth: 600,
                                  fadeInDuration:
                                      const Duration(milliseconds: 150),
                                  placeholder: (context, url) =>
                                      Container(color: Colors.grey.shade100),
                                  errorWidget: (context, url, error) => Icon(
                                      Icons.broken_image_rounded,
                                      color: Colors.grey.shade400),
                                ),
                        ),
                      ),
                    ),
                  ),
                  if (crop['crop_type']?.toString().toLowerCase() == 'organic')
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                            color: const Color(0xFF2E7D32),
                            borderRadius: BorderRadius.circular(100)),
                        child: Row(
                          children: [
                            const Icon(Icons.eco_rounded,
                                color: Colors.white, size: 12),
                            const SizedBox(width: 4),
                            Text("ORGANIC",
                                style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5)),
                          ],
                        ),
                      ),
                    ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      height: 36,
                      width: 36,
                      decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.9),
                          shape: BoxShape.circle),
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        icon: Icon(
                            _isLiked
                                ? Icons.favorite_rounded
                                : Icons.favorite_outline_rounded,
                            color: _isLiked
                                ? Colors.red.shade600
                                : Colors.grey.shade600,
                            size: 20),
                        onPressed: _toggleLike,
                      ),
                    ),
                  ),
                ],
              ),

              // 📝 DATA BODY
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(displayTitle,
                              style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: Colors.black87,
                                  height: 1.2),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: 12),
                        Text("$formattedPrice / kg",
                            style: GoogleFonts.jetBrainsMono(
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF2E7D32),
                                fontSize: 16)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(Icons.inventory_2_rounded,
                            size: 16, color: Colors.grey.shade500),
                        const SizedBox(width: 6),
                        Text("Available Stock: ",
                            style: GoogleFonts.poppins(
                                color: Colors.grey.shade600, fontSize: 13)),
                        Text(displayQty,
                            style: GoogleFonts.jetBrainsMono(
                                color: Colors.black87,
                                fontSize: 13,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.person_rounded,
                            size: 16, color: Colors.grey.shade500),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text("$farmerName • $location",
                              style: GoogleFonts.poppins(
                                  color: Colors.grey.shade600, fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () async {
                          FocusScope.of(context).unfocus();
                          await Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => BuyerCropDetailsScreen(
                                      crop: crop, cropData: crop)));
                          widget.onRefreshRequested();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1565C0),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text("VIEW DETAILS",
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Colors.white,
                                letterSpacing: 0.5)),
                      ),
                    ),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// ✅ THE PERFECT GEOMETRY SKELETON
// ============================================================================
class _SkeletonMarketCard extends StatelessWidget {
  const _SkeletonMarketCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(20))),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                        height: 20, width: 150, color: Colors.grey.shade200),
                    Container(
                        height: 20, width: 80, color: Colors.grey.shade200),
                  ],
                ),
                const SizedBox(height: 12),
                Container(height: 14, width: 200, color: Colors.grey.shade200),
                const SizedBox(height: 6),
                Container(height: 14, width: 160, color: Colors.grey.shade200),
                const SizedBox(height: 16),
                Container(
                    height: 48,
                    width: double.infinity,
                    decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(12))),
              ],
            ),
          )
        ],
      ),
    );
  }
}
