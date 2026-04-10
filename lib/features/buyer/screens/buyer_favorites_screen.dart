import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'buyer_crop_details_screen.dart';

class BuyerFavoritesScreen extends StatefulWidget {
  const BuyerFavoritesScreen({super.key});

  @override
  State<BuyerFavoritesScreen> createState() => _BuyerFavoritesScreenState();
}

class _BuyerFavoritesScreenState extends State<BuyerFavoritesScreen> {
  final _client = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _favorites = [];
  final Color _primaryBlue = const Color(0xFF1565C0);

  @override
  void initState() {
    super.initState();
    _fetchFavorites();
  }

  Future<void> _fetchFavorites() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return;

      // Fetch favorites and join with crop details + farmer details
      final response = await _client
          .from('favorites')
          .select('*, crop:crops(*, profiles:farmer_id(*))')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _favorites = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching favorites: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _removeFavorite(String favoriteId) async {
    try {
      await _client.from('favorites').delete().eq('id', favoriteId);
      // Remove from UI instantly for snappy UX
      setState(() {
        _favorites.removeWhere((item) => item['id'] == favoriteId);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text("Removed from Watchlist", style: GoogleFonts.poppins()),
            backgroundColor: Colors.black87,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint("Error removing favorite: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      appBar: AppBar(
        title: Text("My Watchlist",
            style: GoogleFonts.poppins(
                color: Colors.black87, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0.5,
        iconTheme: const IconThemeData(color: Colors.black87),
        centerTitle: true,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: _primaryBlue))
          : _favorites.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  physics: const BouncingScrollPhysics(),
                  itemCount: _favorites.length,
                  itemBuilder: (context, index) {
                    final favItem = _favorites[index];
                    final crop = favItem['crop'];

                    // Skip if the crop was deleted by the farmer but remains in favorites
                    if (crop == null) return const SizedBox.shrink();

                    return _buildFavoriteCard(crop, favItem['id'].toString());
                  },
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 15)
                ]),
            child:
                Icon(Icons.favorite_border, size: 60, color: Colors.grey[400]),
          ),
          const SizedBox(height: 20),
          Text("Watchlist is Empty",
              style: GoogleFonts.poppins(
                  color: Colors.black87,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text("Crops you like will appear here for quick access.",
              style:
                  GoogleFonts.poppins(color: Colors.grey[600], fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildFavoriteCard(Map<String, dynamic> crop, String favoriteId) {
    String imageUrl = crop['image_url'] ?? '';
    if (imageUrl.isNotEmpty && !imageUrl.startsWith('http')) {
      imageUrl = _client.storage.from('crop_images').getPublicUrl(imageUrl);
    }

    String farmerName = crop['profiles']?['first_name'] ?? 'Farmer';
    String variety =
        crop['crop_variety'] ?? crop['variety'] ?? crop['crop_type'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 10,
                offset: const Offset(0, 4))
          ]),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      BuyerCropDetailsScreen(crop: crop, cropData: crop)),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Image
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200)),
                  child: imageUrl.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => const Center(
                                child:
                                    CircularProgressIndicator(strokeWidth: 2)),
                            errorWidget: (context, url, error) =>
                                const Icon(Icons.grass, color: Colors.grey),
                          ),
                        )
                      : const Icon(Icons.grass, color: Colors.grey),
                ),
                const SizedBox(width: 16),

                // Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(crop['crop_name'] ?? 'Crop',
                          style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      if (variety.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(variety,
                            style: GoogleFonts.poppins(
                                fontSize: 12, color: Colors.grey.shade600)),
                      ],
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.storefront, size: 14, color: _primaryBlue),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(farmerName,
                                style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: _primaryBlue,
                                    fontWeight: FontWeight.w500),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      )
                    ],
                  ),
                ),

                // Price & Action
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.favorite, color: Colors.red),
                      onPressed: () => _removeFavorite(favoriteId),
                      constraints: const BoxConstraints(),
                      padding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 10),
                    Text("₹${crop['price'] ?? 0}",
                        style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade700)),
                    Text("per ${crop['unit'] ?? 'Kg'}",
                        style: GoogleFonts.poppins(
                            fontSize: 10, color: Colors.grey.shade500)),
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
