import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 🚀 Required for HapticFeedback
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

// ✅ Screen Imports
import 'package:agriyukt_app/features/inspector/screens/add_farmer_screen.dart';
import 'package:agriyukt_app/features/inspector/screens/inspector_orders_tab.dart';
import 'package:agriyukt_app/features/common/widgets/agri_stats_dashboard.dart';
import 'package:agriyukt_app/features/inspector/screens/inspector_add_crop_tab.dart';

// 🚀 MARKET INTELLIGENCE IMPORT
import 'package:agriyukt_app/features/inspector/widgets/inspector_market_intelligence_section.dart';

// ✅ Localization
import 'package:agriyukt_app/features/farmer/farmer_translations.dart';
import 'package:agriyukt_app/core/providers/language_provider.dart';

class InspectorHomeTab extends StatefulWidget {
  const InspectorHomeTab({super.key});

  @override
  State<InspectorHomeTab> createState() => _InspectorHomeTabState();
}

class _InspectorHomeTabState extends State<InspectorHomeTab> {
  // 🛡️ ENTERPRISE: Refresh Spam Lock
  bool _isFetchingStats = false;
  bool _loading = true;

  // Inspector Data
  String _name = "";
  int _assignedFarmers = 0;
  int _pendingOrders = 0;
  int _activeOrders = 0;
  int _totalCropsManaged = 0;

  final _currentUserId = Supabase.instance.client.auth.currentUser?.id ?? "";

  // 🚨 RESTORED WEATHER VARIABLES
  String _temp = "--";
  String _conditionCode = "clear_weather";
  IconData _weatherIcon = Icons.cloud;

  // 🛡️ ENTERPRISE: Weather API Cache
  static DateTime? _lastWeatherFetch;
  static String _cachedTemp = "--";
  static String _cachedConditionCode = "clear_weather";
  static IconData _cachedIcon = Icons.cloud;
  bool _weatherLoading = false;

  // 🚀 INFINITE CAROUSEL STATE & TIMER
  final PageController _pageController = PageController(initialPage: 3000);
  int _currentSlide = 0;
  Timer? _carouselTimer;

  // 🎨 Premium Themes - Deep Purple for Inspectors
  final Color _primaryColor = const Color(0xFF512DA8);
  final Color _lightColor = const Color(0xFF7E57C2);

  @override
  void initState() {
    super.initState();
    _fetchInspectorStats();
    _fetchWeatherSafely();
    _startAutoScroll();
  }

  @override
  void dispose() {
    _carouselTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  // --- 🚀 INFINITE AUTO-SCROLL LOGIC ---
  void _startAutoScroll() {
    _carouselTimer =
        Timer.periodic(const Duration(milliseconds: 3500), (timer) {
      if (_pageController.hasClients) {
        _pageController.nextPage(
          duration: const Duration(milliseconds: 600),
          curve: Curves.fastOutSlowIn,
        );
      }
    });
  }

  // 🚀 LAUNCH EXTERNAL URL
  Future<void> _launchUrl(String urlString) async {
    final Uri url = Uri.parse(urlString);
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw Exception("Could not launch URL");
      }
    } catch (e) {
      HapticFeedback.heavyImpact();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_text('could_not_launch'),
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
            backgroundColor: Colors.red.shade800,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // 🚀 Translation Bridge
  String _text(String key) => FarmerText.get(context, key);

  // --- 1. FETCH STATS ---
  Future<void> _fetchInspectorStats() async {
    if (_isFetchingStats) return;

    setState(() {
      _isFetchingStats = true;
      if (_assignedFarmers == 0) _loading = true;
    });

    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;

      if (user == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final initialData = await Future.wait<dynamic>([
        client
            .from('profiles')
            .select('first_name')
            .eq('id', user.id)
            .maybeSingle(),
        client.from('profiles').select('id, role').eq('inspector_id', user.id)
      ]);

      final profile = initialData[0] as Map<String, dynamic>?;
      final String inspectorName = profile?['first_name']?.toString() ?? "";

      final List<dynamic> farmersList = initialData[1] as List<dynamic>;

      final List<String> farmerIds = farmersList
          .where((f) =>
              (f['role']?.toString().toLowerCase().trim() ?? '') == 'farmer')
          .map((f) => f['id'].toString())
          .toList();

      int cropsCount = 0;
      int pendingCount = 0;
      int activeCount = 0;

      if (farmerIds.isNotEmpty) {
        final relatedData = await Future.wait<dynamic>([
          client.from('crops').select('id').inFilter('farmer_id', farmerIds),
          client
              .from('orders')
              .select('id, status')
              .inFilter('farmer_id', farmerIds)
        ]);

        cropsCount = (relatedData[0] as List).length;
        final List<dynamic> ordersList = relatedData[1] as List<dynamic>;

        for (var o in ordersList) {
          String status = (o['status'] ?? '').toString().toLowerCase().trim();
          if (['pending', 'ordered', 'request', 'requested'].contains(status)) {
            pendingCount++;
          } else if ([
            'accepted',
            'packed',
            'shipped',
            'in transit',
            'processing',
            'confirmed'
          ].contains(status)) {
            activeCount++;
          }
        }
      }

      if (mounted) {
        setState(() {
          _name = inspectorName;
          _assignedFarmers = farmerIds.length;
          _totalCropsManaged = cropsCount;
          _pendingOrders = pendingCount;
          _activeOrders = activeCount;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint("❌ Fatal Stats Fetch Error: $e");
      if (mounted) setState(() => _loading = false);
    } finally {
      _isFetchingStats = false;
    }
  }

  // --- 2. FETCH WEATHER ---
  Future<void> _fetchWeatherSafely() async {
    if (_lastWeatherFetch != null &&
        DateTime.now().difference(_lastWeatherFetch!).inMinutes < 30) {
      if (mounted) {
        setState(() {
          _temp = _cachedTemp;
          _conditionCode = _cachedConditionCode;
          _weatherIcon = _cachedIcon;
        });
      }
      return;
    }

    if (_weatherLoading) return;
    setState(() => _weatherLoading = true);

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await _callWeatherApi(21.1458, 79.0882);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        Position position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.low,
            timeLimit: const Duration(seconds: 5));
        await _callWeatherApi(position.latitude, position.longitude);
      } else {
        await _callWeatherApi(21.1458, 79.0882);
      }
    } catch (e) {
      if (mounted) await _callWeatherApi(21.1458, 79.0882);
    } finally {
      if (mounted) setState(() => _weatherLoading = false);
    }
  }

  Future<void> _callWeatherApi(double lat, double long) async {
    try {
      final url = Uri.parse(
          'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$long&current_weather=true');

      final response = await http.get(url).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final current = data['current_weather'];

        if (mounted) {
          setState(() {
            final num tempRaw = current['temperature'] as num? ?? 0;
            final int codeRaw =
                int.tryParse(current['weathercode'].toString()) ?? 0;

            _temp = "${tempRaw.round()}°C";
            _conditionCode = _getWeatherTranslationKey(codeRaw);
            _weatherIcon = _getWeatherIcon(codeRaw);

            _cachedTemp = _temp;
            _cachedConditionCode = _conditionCode;
            _cachedIcon = _weatherIcon;
            _lastWeatherFetch = DateTime.now();
          });
        }
      }
    } catch (_) {}
  }

  String _getWeatherTranslationKey(int code) => code <= 3
      ? "clear_weather"
      : (code >= 51 ? "rainy_weather" : "sunny_weather");

  IconData _getWeatherIcon(int code) {
    if (code == 0) return Icons.wb_sunny;
    if (code < 4) return Icons.cloud;
    if (code < 80) return Icons.water_drop;
    return Icons.thunderstorm;
  }

  void _safeNavigateAndRefresh(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen))
        .then((_) {
      if (mounted) _fetchInspectorStats();
    });
  }

  @override
  Widget build(BuildContext context) {
    Provider.of<LanguageProvider>(context); // Listen to translation engine
    const EdgeInsets sectionPadding = EdgeInsets.symmetric(horizontal: 20);

    if (_loading) {
      return Center(child: CircularProgressIndicator(color: _primaryColor));
    }

    return Scaffold(
      backgroundColor: Colors.white, // Match ecosystem theme
      body: RefreshIndicator(
        onRefresh: () async {
          HapticFeedback.lightImpact();
          await _fetchInspectorStats();
          await _fetchWeatherSafely();
        },
        color: _primaryColor,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 30),
          physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics()),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 15),

              // 1. 🚀 TRANSLATED HEADER
              Padding(
                padding: sectionPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _name.isNotEmpty
                          ? "${_text('namaste')}, $_name 👋"
                          : "${_text('namaste')} 👋",
                      style: GoogleFonts.poppins(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: _primaryColor,
                      ),
                    ),
                    Text(
                      "${_text('today')}, ${DateFormat('d MMM').format(DateTime.now())}",
                      style: GoogleFonts.poppins(
                        color: Colors.grey[600],
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 2. 🚀 UPGRADED 5-SLIDE CAROUSEL (Inspector Specific Ads)
              Column(
                children: [
                  SizedBox(
                    height: 160,
                    child: PageView.builder(
                      controller: _pageController,
                      onPageChanged: (index) =>
                          setState(() => _currentSlide = index % 5),
                      itemBuilder: (context, index) {
                        final int realIndex = index % 5;

                        if (realIndex == 0) {
                          return _buildWeatherCard();
                        } else if (realIndex == 1) {
                          return _buildActionPromoCard(
                            title: "Agmarknet Portal",
                            subtitle:
                                "Check official Govt Mandi prices & trends.",
                            badge: "MARKET DATA",
                            icon: Icons.query_stats,
                            colors: [
                              const Color(0xFF1E3C72),
                              const Color(0xFF2A5298)
                            ],
                            url: "https://agmarknet.gov.in/",
                          );
                        } else if (realIndex == 2) {
                          return _buildActionPromoCard(
                            title: "Soil Health Card",
                            subtitle: "Verify soil quality and lab reports.",
                            badge: "VERIFICATION",
                            icon: Icons.landscape,
                            colors: [
                              const Color(0xFF00796B),
                              const Color(0xFF388E3C)
                            ],
                            url: "https://soilhealth.dac.gov.in/",
                          );
                        } else if (realIndex == 3) {
                          return _buildActionPromoCard(
                            title: "PM Fasal Bima",
                            subtitle:
                                "Review crop insurance & risk guidelines.",
                            badge: "GOVT SCHEME",
                            icon: Icons.security,
                            colors: [
                              const Color(0xFFE65100),
                              const Color(0xFFFF8F00)
                            ],
                            url: "https://pmfby.gov.in/",
                          );
                        } else {
                          return _buildActionPromoCard(
                            title: "FSSAI Standards",
                            subtitle:
                                "Food safety and agricultural grading rules.",
                            badge: "COMPLIANCE",
                            icon: Icons.verified_user,
                            colors: [
                              const Color(0xFF6A1B9A),
                              const Color(0xFF8E24AA)
                            ],
                            url: "https://fssai.gov.in/",
                          );
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) => _buildDot(index)),
                  ),
                ],
              ),
              const SizedBox(height: 25),

              // 3. 🚀 OVERVIEW TITLE
              Padding(
                padding: sectionPadding,
                child: Text(
                  _text('overview'),
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // 4. 🚀 PREMIUM BENTO BOX OVERVIEW GRID
              Padding(
                padding: sectionPadding,
                child: GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  mainAxisSpacing: 15,
                  crossAxisSpacing: 15,
                  childAspectRatio: 1.25, // Zero whitespace geometry
                  padding: EdgeInsets.zero,
                  children: [
                    _buildBentoOverviewCard(
                      count: "$_assignedFarmers",
                      label: "Farmers", // Fallbacks to dict safely
                      icon: Icons.people_outline_rounded,
                      color: Colors.orange,
                    ),
                    _buildBentoOverviewCard(
                      count: "$_pendingOrders",
                      label: _text('pending_req'),
                      icon: Icons.hourglass_top_rounded,
                      color: Colors.red,
                    ),
                    _buildBentoOverviewCard(
                      count: "$_activeOrders",
                      label: "Active Orders",
                      icon: Icons.local_shipping_rounded,
                      color: Colors.blue,
                    ),
                    _buildBentoOverviewCard(
                      count: "$_totalCropsManaged",
                      label: "Total Crops",
                      icon: Icons.grass_rounded,
                      color: Colors.green,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 25),

              // 5. 🚀 QUICK ACTIONS TITLE
              Padding(
                padding: sectionPadding,
                child: Text(
                  _text('quick_actions'),
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // 🚀 ZEPTO-STYLE HIGH CONTRAST TABS
              Padding(
                padding: sectionPadding,
                child: Row(
                  children: [
                    Expanded(
                      child: _buildZeptoActionButton(
                        "Add Farmer",
                        Icons.person_add_alt_1_rounded,
                        const [Color(0xFFFB8C00), Color(0xFFE65100)], // Orange
                        () async {
                          HapticFeedback.selectionClick();
                          _safeNavigateAndRefresh(const AddFarmerScreen());
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildZeptoActionButton(
                        _text('add_crop'),
                        Icons.add_circle_outline_rounded,
                        const [Color(0xFF43A047), Color(0xFF2E7D32)], // Green
                        () async {
                          HapticFeedback.selectionClick();
                          _safeNavigateAndRefresh(const InspectorAddCropTab());
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildZeptoActionButton(
                        _text('orders'),
                        Icons.receipt_long_rounded,
                        const [Color(0xFF1E88E5), Color(0xFF1565C0)], // Blue
                        () async {
                          HapticFeedback.selectionClick();
                          _safeNavigateAndRefresh(const InspectorOrdersTab());
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),

              // 🚀 6. PERSONALIZED MARKET INTELLIGENCE SECTION
              if (_currentUserId.isNotEmpty)
                InspectorMarketIntelligence(
                  inspectorId: _currentUserId,
                  themeColor: _primaryColor,
                ),

              const SizedBox(height: 24),

              // 7. GLOBAL MARKET TRENDS
              Padding(
                padding: sectionPadding,
                child: Text(
                  _text('market_trends'),
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
              const SizedBox(height: 10),

              SizedBox(
                width: double.infinity,
                child: FittedBox(
                  fit: BoxFit.fitWidth,
                  child: Container(
                      width: MediaQuery.of(context).size.width,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: const AgriStatsDashboard()),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // --- WIDGETS ---

  Widget _buildWeatherCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: [_primaryColor, _lightColor],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: _primaryColor.withOpacity(0.4),
              blurRadius: 15,
              offset: const Offset(0, 8))
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -20,
            bottom: -20,
            child: Icon(_weatherIcon,
                size: 130, color: Colors.white.withOpacity(0.15)),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_text('weather'),
                      style: GoogleFonts.poppins(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(_temp,
                      style: GoogleFonts.poppins(
                          fontSize: 36,
                          height: 1.1,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(_weatherIcon, color: Colors.yellowAccent, size: 16),
                      const SizedBox(width: 6),
                      Text(_text(_conditionCode),
                          style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionPromoCard({
    required String title,
    required String subtitle,
    required String badge,
    required IconData icon,
    required List<Color> colors,
    required String url,
  }) {
    return GestureDetector(
      onTap: () => _launchUrl(url),
      child: Container(
        padding: const EdgeInsets.all(20),
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
            gradient: LinearGradient(
                colors: colors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                  color: colors[0].withOpacity(0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 8))
            ]),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6)),
                      child: Text(badge,
                          style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1))),
                  const SizedBox(height: 8),
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          height: 1.1)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 13,
                                fontWeight: FontWeight.w500)),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_forward_ios,
                          color: Colors.white70, size: 14),
                    ],
                  )
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDot(int index) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: 6,
      width: _currentSlide == index ? 20 : 6,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
          color: _currentSlide == index ? _primaryColor : Colors.grey[300],
          borderRadius: BorderRadius.circular(3)),
    );
  }

  // 🚀 PREMIUM BENTO BOX STYLE OVERVIEW CARDS
  Widget _buildBentoOverviewCard({
    required String count,
    required String label,
    required IconData icon,
    required MaterialColor color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.shade200, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    count,
                    style: GoogleFonts.poppins(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: color.shade800,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: color.shade200,
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      )
                    ]),
                child: Icon(icon, color: color.shade700, size: 24),
              ),
            ],
          ),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: color.shade900,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  // 🚀 ZEPTO-STYLE HIGH CONTRAST TABS
  Widget _buildZeptoActionButton(
    String label,
    IconData icon,
    List<Color> gradientColors,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: gradientColors[0].withOpacity(0.4),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 30),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
