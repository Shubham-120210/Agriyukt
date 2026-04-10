import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';

// ✅ CORE & FEATURE IMPORTS
import 'package:agriyukt_app/core/providers/language_provider.dart';
import 'package:agriyukt_app/features/farmer/farmer_translations.dart';
import 'package:agriyukt_app/core/services/translation_service.dart';
import 'package:agriyukt_app/features/farmer/screens/add_crop_screen.dart';
import 'package:agriyukt_app/features/farmer/screens/edit_crop_screen.dart';
import 'package:agriyukt_app/features/farmer/screens/view_crop_screen.dart';

class MyCropsTab extends StatefulWidget {
  const MyCropsTab({super.key});

  @override
  State<MyCropsTab> createState() => _MyCropsTabState();
}

class _MyCropsTabState extends State<MyCropsTab> {
  final _client = Supabase.instance.client;

  // 🛡️ LIFECYCLE & CACHING
  late Stream<List<Map<String, dynamic>>> _cropsStream;
  Timer? _debounce;
  int _refreshTrigger = 0;

  final Map<String, String> _translationCache = {};

  // 🚀 THE MAGIC: OPTIMISTIC UI CACHE
  // Any crop ID added here will instantly vanish from the screen without waiting for the DB
  final Set<String> _optimisticHiddenIds = {};

  bool _showActive = true;
  String _searchQuery = "";
  final _searchCtrl = TextEditingController();

  final Color _primaryGreen = const Color(0xFF1B5E20);

  // Translation Helper
  String _text(String key) => FarmerText.get(context, key);

  @override
  void initState() {
    super.initState();
    _initStream();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _initStream() {
    final user = _client.auth.currentUser;
    if (user != null) {
      _cropsStream = _client
          .from('crops')
          .stream(primaryKey: ['id']).eq('farmer_id', user.id);
    }
  }

  Future<void> _refreshList() async {
    HapticFeedback.selectionClick();
    setState(() {
      _initStream();
      _refreshTrigger++;
      _translationCache.clear();
      _optimisticHiddenIds.clear(); // Clear local cache on hard refresh
    });
    await Future.delayed(const Duration(milliseconds: 300));
  }

  Future<String> _getCachedTranslation(String text, String langCode) async {
    final cacheKey = '${text}_$langCode';
    if (_translationCache.containsKey(cacheKey)) {
      return _translationCache[cacheKey]!;
    }
    try {
      final translated = await TranslationService.toLocal(text, langCode);
      _translationCache[cacheKey] = translated;
      return translated;
    } catch (e) {
      return text;
    }
  }

  // ---------------------------------------------------------------------------
  // 🗑️ DELETE LOGIC (🚀 INSTANT OPTIMISTIC UPDATE)
  // ---------------------------------------------------------------------------
  Future<void> _deleteCrop(String id, String titleTxt, String msgTxt,
      String cancelTxt, String deleteTxt, String successTxt) async {
    HapticFeedback.mediumImpact();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titleTxt,
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Text(msgTxt, style: GoogleFonts.poppins()),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(cancelTxt, style: GoogleFonts.poppins())),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(deleteTxt,
                  style: GoogleFonts.poppins(
                      color: Colors.red, fontWeight: FontWeight.bold))),
        ],
      ),
    );

    if (confirm == true) {
      // 🚀 OPTIMISTIC UI: Hide the crop INSTANTLY!
      setState(() {
        _optimisticHiddenIds.add(id);
      });

      try {
        // Now talk to the database in the background
        await _client.from('crops').update({'status': 'Archived'}).eq('id', id);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(successTxt, style: GoogleFonts.poppins()),
              backgroundColor: Colors.green));
        }
      } catch (e) {
        // 🔄 REVERT UI: If the database fails, bring the crop back to the screen
        setState(() {
          _optimisticHiddenIds.remove(id);
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text("Error archiving crop: $e",
                  style: GoogleFonts.poppins()),
              backgroundColor: Colors.red));
        }
      }
    }
  }

  String _safeStr(dynamic val, [String fallback = '']) {
    if (val == null) return fallback;
    return val.toString().trim();
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

  @override
  Widget build(BuildContext context) {
    final user = _client.auth.currentUser;
    final langCode =
        Provider.of<LanguageProvider>(context).appLocale.languageCode;

    if (user == null) {
      return Center(
          child: Text(_text('login_required'), style: GoogleFonts.poppins()));
    }

    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      behavior: HitTestBehavior.opaque,
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F6F8),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            await Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AddCropScreen()));
            if (!mounted) return;
            _refreshList(); // Instantly fetch new crop upon returning
          },
          label: Text(_text('add_crop'),
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          icon: const Icon(Icons.add),
          backgroundColor: _primaryGreen,
          foregroundColor: Colors.white,
        ),
        body: Column(
          children: [
            Container(
              padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top, bottom: 8),
              decoration: BoxDecoration(
                color: _primaryGreen,
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 4))
                ],
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (v) {
                        if (_debounce?.isActive ?? false) _debounce!.cancel();
                        _debounce =
                            Timer(const Duration(milliseconds: 300), () {
                          if (mounted)
                            setState(
                                () => _searchQuery = v.toLowerCase().trim());
                        });
                      },
                      style: GoogleFonts.poppins(),
                      decoration: InputDecoration(
                        hintText: _text('search_crops_hint'),
                        hintStyle: GoogleFonts.poppins(color: Colors.grey[500]),
                        prefixIcon: Icon(Icons.search, color: _primaryGreen),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon:
                                    const Icon(Icons.clear, color: Colors.grey),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() => _searchQuery = "");
                                  FocusScope.of(context).unfocus();
                                })
                            : null,
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 10, horizontal: 16),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.white)),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.white)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        children: [
                          Expanded(
                              child: _tabBtn(_text('active_crops_tab'), true)),
                          Expanded(
                              child:
                                  _tabBtn(_text('inactive_sold_tab'), false)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                key: ValueKey(_refreshTrigger),
                stream: _cropsStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return Center(
                        child: CircularProgressIndicator(color: _primaryGreen));
                  }

                  if (snapshot.hasError) {
                    return Center(
                        child: Text("Error loading crops.",
                            style: GoogleFonts.poppins(color: Colors.red)));
                  }

                  List<Map<String, dynamic>> rawData =
                      List<Map<String, dynamic>>.from(snapshot.data ?? []);

                  if (rawData.isEmpty) {
                    return RefreshIndicator(
                      onRefresh: _refreshList,
                      color: _primaryGreen,
                      child: ListView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                              height: MediaQuery.of(context).size.height * 0.3),
                          Center(
                              child: Text(_text('no_crops_found'),
                                  style: GoogleFonts.poppins(
                                      color: Colors.grey[500]))),
                        ],
                      ),
                    );
                  }

                  rawData.sort((a, b) {
                    final dateA =
                        DateTime.tryParse(_safeStr(a['created_at'])) ??
                            DateTime.fromMillisecondsSinceEpoch(0);
                    final dateB =
                        DateTime.tryParse(_safeStr(b['created_at'])) ??
                            DateTime.fromMillisecondsSinceEpoch(0);
                    return dateB.compareTo(dateA);
                  });

                  // 🧠 BULLETPROOF FILTER LOGIC
                  final filtered = rawData.where((c) {
                    final String safeId = _safeStr(c['id']);

                    // 🚀 INSTANT VANISH: Check our optimistic UI cache first!
                    if (_optimisticHiddenIds.contains(safeId)) return false;

                    final status =
                        _safeStr(c['status'], 'Active').toLowerCase();
                    if (status == 'archived') return false;

                    final double totalStock = _parseQuantity(c['quantity']) +
                        _parseQuantity(c['quantity_kg']);

                    final isActiveGroup =
                        ['active', 'verified', 'growing'].contains(status) &&
                            (totalStock > 0);

                    final matchesTab =
                        _showActive ? isActiveGroup : !isActiveGroup;

                    final name = _safeStr(c['crop_name']).toLowerCase();
                    final variety = _safeStr(c['variety']).toLowerCase();
                    final matchesSearch = name.contains(_searchQuery) ||
                        variety.contains(_searchQuery);

                    return matchesTab && matchesSearch;
                  }).toList();

                  if (filtered.isEmpty) {
                    return RefreshIndicator(
                      onRefresh: _refreshList,
                      color: _primaryGreen,
                      child: ListView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                              height: MediaQuery.of(context).size.height * 0.3),
                          Center(
                              child: Text(_text('no_crops_found'),
                                  style: GoogleFonts.poppins(
                                      color: Colors.grey[500]))),
                        ],
                      ),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: _refreshList,
                    color: _primaryGreen,
                    child: ListView.separated(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(
                          top: 8, left: 16, right: 16, bottom: 80),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (ctx, i) =>
                          _buildLargeCard(filtered[i], langCode),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabBtn(String label, bool target) {
    bool isSel = _showActive == target;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        FocusScope.of(context).unfocus();
        setState(() => _showActive = target);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSel ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSel
              ? [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2))
                ]
              : null,
        ),
        child: Text(label,
            style: GoogleFonts.poppins(
                color: isSel ? _primaryGreen : Colors.white.withOpacity(0.9),
                fontSize: 13,
                fontWeight: isSel ? FontWeight.bold : FontWeight.w600)),
      ),
    );
  }

  Widget _buildTranslatedName(String name, String langCode) {
    final cacheKey = '${name}_$langCode';
    if (_translationCache.containsKey(cacheKey)) {
      return Text(_translationCache[cacheKey]!,
          style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis);
    }
    return FutureBuilder<String>(
      future: _getCachedTranslation(name, langCode),
      initialData: name,
      builder: (context, snapshot) => Text(snapshot.data ?? name,
          style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
    );
  }

  Widget _buildLargeCard(Map<String, dynamic> crop, String langCode) {
    final String safeCropId = _safeStr(crop['id']).isNotEmpty
        ? _safeStr(crop['id'])
        : UniqueKey().toString();

    final String dialogTitle = _text('delete_listing');
    final String dialogMsg = _text('delete_confirm_msg');
    final String btnCancel = _text('cancel');
    final String btnDelete = _text('delete');
    final String snackSuccess = _text('crop_deleted');

    ImageProvider imgProvider;
    String imgUrl = _safeStr(crop['image_url']);
    if (imgUrl.isNotEmpty) {
      if (imgUrl.startsWith('http')) {
        imgProvider = NetworkImage(imgUrl);
      } else {
        imgProvider = NetworkImage(
            _client.storage.from('crop_images').getPublicUrl(imgUrl));
      }
    } else {
      imgProvider = const AssetImage('assets/images/placeholder_crop.png');
    }

    final String name = _safeStr(crop['crop_name'], 'Unknown Crop');
    final String variety = _safeStr(crop['variety'], 'Generic');
    final String status = _safeStr(crop['status'], 'ACTIVE').toUpperCase();

    double qtyNum = _parseQuantity(crop['quantity']);
    if (qtyNum == 0) qtyNum = _parseQuantity(crop['quantity_kg']);
    String qtyValue =
        qtyNum.toString().replaceAll(RegExp(r"([.]*0)(?!.*\d)"), "");

    String unit = _safeStr(crop['unit'], 'Kg');

    String displayUnit = unit;
    String lowerUnit = unit.toLowerCase();
    if (lowerUnit.contains('kg'))
      displayUnit = 'kg';
    else if (lowerUnit.contains('quintal') || lowerUnit == 'q')
      displayUnit = 'q';
    else if (lowerUnit.contains('ton') || lowerUnit == 't')
      displayUnit = 't';
    else if (lowerUnit.contains('crate'))
      displayUnit = 'crates';
    else
      displayUnit = _text(lowerUnit) == lowerUnit ? unit : _text(lowerUnit);

    String displayQty = "$qtyValue $displayUnit";

    double priceNum = _parseQuantity(crop['price']);
    if (priceNum == 0) priceNum = _parseQuantity(crop['price_per_qty']);
    String priceVal =
        priceNum.toString().replaceAll(RegExp(r"([.]*0)(?!.*\d)"), "");

    final String displayPrice = "₹$priceVal / $displayUnit";

    final String harvestDate = _formatDate(_safeStr(crop['harvest_date']));
    final String availDate = _formatDate(_safeStr(crop['available_from']));
    final String localizedStatus = _text(status.toLowerCase());

    Color statusColor = Colors.green;
    if (status == 'SOLD')
      statusColor = Colors.red;
    else if (status == 'INACTIVE' || status == 'SOLD OUT')
      statusColor = Colors.grey;
    else if (status == 'VERIFIED') statusColor = Colors.orange;

    return Container(
      key: ValueKey(safeCropId),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade100),
          boxShadow: [
            BoxShadow(
                color: Colors.grey.withOpacity(0.08),
                blurRadius: 10,
                offset: const Offset(0, 4))
          ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
                child: Container(
                  height: 140,
                  width: double.infinity,
                  decoration: const BoxDecoration(color: Color(0xFFE8F5E9)),
                  child: imgUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: imgUrl.startsWith('http')
                              ? imgUrl
                              : _client.storage
                                  .from('crop_images')
                                  .getPublicUrl(imgUrl),
                          fit: BoxFit.cover,
                          memCacheWidth: 600,
                          placeholder: (context, url) =>
                              Container(color: Colors.grey[200]),
                          errorWidget: (context, url, error) => Image.asset(
                              'assets/images/placeholder_crop.png',
                              fit: BoxFit.cover),
                        )
                      : Image.asset('assets/images/placeholder_crop.png',
                          fit: BoxFit.cover),
                ),
              ),
              Positioned(
                top: 15,
                left: 15,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                      color: statusColor,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [
                        BoxShadow(color: Colors.black12, blurRadius: 4)
                      ]),
                  child: Text(localizedStatus.toUpperCase(),
                      style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 11)),
                ),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: InkWell(
                  onTap: () => _deleteCrop(safeCropId, dialogTitle, dialogMsg,
                      btnCancel, btnDelete, snackSuccess),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: Colors.black12, blurRadius: 4)
                        ]),
                    child: const Icon(Icons.delete_outline,
                        color: Colors.red, size: 20),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          _buildTranslatedName(name, langCode),
                          Text(variety,
                              style: GoogleFonts.poppins(
                                  fontSize: 12, color: Colors.grey[600]),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ])),
                    Text(displayPrice,
                        style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: _primaryGreen)),
                  ],
                ),
                const SizedBox(height: 8),
                const Divider(height: 1, color: Color(0xFFEEEEEE)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                        child: _infoItem(Icons.scale, _text('quantity'),
                            displayQty, Colors.blue)),
                    Expanded(
                        child: _infoItem(Icons.agriculture,
                            _text('harvest_date'), harvestDate, Colors.orange)),
                  ],
                ),
                const SizedBox(height: 6),
                _infoItem(Icons.event_available, _text('avail_from'), availDate,
                    Colors.purple),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                        child: ElevatedButton.icon(
                            onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        ViewCropScreen(crop: crop))),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: _primaryGreen,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8))),
                            icon: const Icon(Icons.visibility,
                                color: Colors.white, size: 16),
                            label: Text(_text('view'),
                                style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)))),
                    const SizedBox(width: 10),
                    Expanded(
                        child: OutlinedButton.icon(
                            onPressed: () async {
                              await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          EditCropScreen(cropData: crop)));
                              _refreshList(); // Instantly update when returning from edit screen!
                            },
                            style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Colors.orange),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8))),
                            icon: const Icon(Icons.edit,
                                color: Colors.orange, size: 16),
                            label: Text(_text('edit'),
                                style: GoogleFonts.poppins(
                                    color: Colors.orange,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)))),
                  ],
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _infoItem(IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6)),
            child: Icon(icon, size: 14, color: color)),
        const SizedBox(width: 8),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey)),
          Text(value,
              style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: Colors.black87,
                  fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis)
        ])),
      ],
    );
  }

  String _formatDate(String dateStr) {
    if (dateStr.isEmpty) return "N/A";
    try {
      final d = DateTime.parse(dateStr).toLocal();
      return DateFormat('dd/MM/yyyy').format(d);
    } catch (_) {
      return "N/A";
    }
  }
}
