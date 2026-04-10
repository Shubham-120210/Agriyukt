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

// ✅ Navigation Imports
import 'package:agriyukt_app/features/buyer/screens/buyer_marketplace_screen.dart';
import 'package:agriyukt_app/features/buyer/screens/buyer_favorites_screen.dart';
import 'package:agriyukt_app/features/buyer/screens/buyer_orders_screen.dart';

// ✅ DATA VISUALIZATION & INTELLIGENCE IMPORTS
import 'package:agriyukt_app/features/common/widgets/agri_stats_dashboard.dart';
import 'package:agriyukt_app/features/buyer/widgets/buyer_market_intelligence_section.dart';

// ✅ Localization
import 'package:agriyukt_app/features/farmer/farmer_translations.dart';
import 'package:agriyukt_app/core/providers/language_provider.dart';

class BuyerHomeScreen extends StatefulWidget {
  const BuyerHomeScreen({super.key});

  @override
  State<BuyerHomeScreen> createState() => _BuyerHomeScreenState();
}

class _BuyerHomeScreenState extends State<BuyerHomeScreen> {
  String _name = "";
  int _activeOrders = 0;
  int _pendingOrders = 0;
  int _favoritesCount = 0;
  int _freshArrivalsCount = 0;
  bool _loading = true;

  String _temp = "--";
  String _conditionCode = "clear_weather"; // Translated weather key
  IconData _weatherIcon = Icons.cloud;
  bool _weatherLoading = false;

  // 🚀 INFINITE CAROUSEL STATE & TIMER
  final PageController _pageController = PageController(initialPage: 3000);
  int _currentSlide = 0;
  Timer? _carouselTimer;

  final ScrollController _scrollController = ScrollController();
  final _currentUserId = Supabase.instance.client.auth.currentUser?.id ?? "";

  // 🎨 Premium Buyer Themes
  final Color _primaryBlue = const Color(0xFF1565C0);
  final Color _lightBlue = const Color(0xFF42A5F5);

  @override
  void initState() {
    super.initState();
    _fetchRealData();
    _fetchWeather();
    _startAutoScroll();
  }

  @override
  void dispose() {
    _carouselTimer?.cancel();
    _pageController.dispose();
    _scrollController.dispose();
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

  // 🚀 LAUNCH EXTERNAL URL (With Anti-Silent Failure)
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

  // 🚀 The ultimate translation bridge
  String _text(String key) => FarmerText.get(context, key);

  // 🚀 FETCH DATA
  Future<void> _fetchRealData() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final client = Supabase.instance.client;

        final profile = await client
            .from('profiles')
            .select('first_name')
            .eq('id', user.id)
            .maybeSingle()
            .timeout(const Duration(seconds: 10));

        final int favs = await client
            .from('favorites')
            .count(CountOption.exact)
            .eq('user_id', user.id)
            .timeout(const Duration(seconds: 10));

        final DateTime sevenDaysAgo =
            DateTime.now().subtract(const Duration(days: 7));
        final int fresh = await client
            .from('crops')
            .count(CountOption.exact)
            .gte('created_at', sevenDaysAgo.toIso8601String())
            .eq('status', 'Active')
            .timeout(const Duration(seconds: 10));

        final response = await client
            .from('orders')
            .select('status, tracking_status')
            .eq('buyer_id', user.id)
            .timeout(const Duration(seconds: 10));

        int pending = 0;
        int active = 0;
        final List<dynamic> orders = response as List<dynamic>;

        for (var o in orders) {
          final String status =
              (o['status'] ?? '').toString().toLowerCase().trim();
          final String tracking =
              (o['tracking_status'] ?? '').toString().toLowerCase().trim();

          if (status == 'pending') {
            pending++;
          } else if (status == 'accepted' &&
              !['delivered', 'completed'].contains(tracking)) {
            active++;
          }
        }

        if (mounted) {
          setState(() {
            _name = profile?['first_name'] ?? "";
            _favoritesCount = favs;
            _freshArrivalsCount = fresh;
            _pendingOrders = pending;
            _activeOrders = active;
            _loading = false;
          });
        }
      }
    } catch (e) {
      debugPrint("Dashboard Fetch Error: $e");
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fetchWeather() async {
    if (_weatherLoading) return;
    setState(() => _weatherLoading = true);
    try {
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
        await _callWeatherApi(19.0760, 72.8777); // Default Mumbai
      }
    } catch (_) {
      if (mounted) _callWeatherApi(19.0760, 72.8777);
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
            _temp = "${current['temperature'].round()}°C";
            _conditionCode = _getWeatherTranslationKey(current['weathercode']);
            _weatherIcon = _getWeatherIcon(current['weathercode']);
          });
        }
      }
    } catch (_) {}
  }

  String _getWeatherTranslationKey(int code) => code <= 3
      ? "clear_weather"
      : (code >= 51 ? "rainy_weather" : "sunny_weather");

  IconData _getWeatherIcon(int code) => code <= 3
      ? Icons.cloud
      : (code >= 51 ? Icons.water_drop : Icons.wb_sunny);

  @override
  Widget build(BuildContext context) {
    Provider.of<LanguageProvider>(context); // Listen to translation engine
    const EdgeInsets sectionPadding = EdgeInsets.symmetric(horizontal: 20);

    if (_loading) {
      return Center(child: CircularProgressIndicator(color: _primaryBlue));
    }

    return Scaffold(
      backgroundColor: Colors.white, // Match Farmer theme
      body: RefreshIndicator(
        onRefresh: () async {
          HapticFeedback.lightImpact();
          await _fetchRealData();
          await _fetchWeather();
        },
        color: _primaryBlue,
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.only(bottom: 30),
          physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics()),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 15),

              // 🚀 TRANSLATED HEADER
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
                        color: _primaryBlue,
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

              // 🚀 UPGRADED 5-SLIDE CAROUSEL
              Column(
                children: [
                  SizedBox(
                    height: 160,
                    child: PageView.builder(
                      controller: _pageController,
                      onPageChanged: (idx) =>
                          setState(() => _currentSlide = idx % 5),
                      itemBuilder: (context, index) {
                        final int realIndex = index % 5;

                        if (realIndex == 0) {
                          return _buildWeatherCard();
                        } else if (realIndex == 1) {
                          return _buildActionPromoCard(
                            title: "SBI SME Loan",
                            subtitle: "Working capital loans for Agri-Traders.",
                            badge: _text('finance'),
                            icon: Icons.account_balance,
                            colors: [
                              const Color(0xFF1E3C72),
                              const Color(0xFF2A5298)
                            ],
                            url: "https://sbi.co.in/web/sme-enterprise",
                          );
                        } else if (realIndex == 2) {
                          return _buildActionPromoCard(
                            title: "Book Logistics",
                            subtitle: "Fast, reliable crop transport trucks.",
                            badge: "TRANSPORT",
                            icon: Icons.local_shipping,
                            colors: [
                              const Color(0xFFE65100),
                              const Color(0xFFFF8F00)
                            ],
                            url: "https://porter.in/",
                          );
                        } else if (realIndex == 3) {
                          return _buildActionPromoCard(
                            title: "Cold Storage",
                            subtitle: "Find & rent nearby cold storage units.",
                            badge: "WAREHOUSE",
                            icon: Icons.ac_unit,
                            colors: [
                              const Color(0xFF00796B),
                              const Color(0xFF388E3C)
                            ],
                            url: "https://www.nccd.gov.in/",
                          );
                        } else {
                          return _buildActionPromoCard(
                            title: "e-NAM Portal",
                            subtitle: "Access the National Agriculture Market.",
                            badge: "GOVT SCHEME",
                            icon: Icons.storefront,
                            colors: [
                              const Color(0xFF6A1B9A),
                              const Color(0xFF8E24AA)
                            ],
                            url: "https://enam.gov.in/web/",
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

              // 🚀 OVERVIEW TITLE
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

              // 🚀 PREMIUM BENTO BOX OVERVIEW GRID
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
                      count: "$_activeOrders",
                      label: _text('active'), // Or add 'active_orders' to dict
                      icon: Icons.local_shipping_rounded,
                      color: Colors.blue,
                    ),
                    _buildBentoOverviewCard(
                      count: "$_pendingOrders",
                      label: _text('pending_req'),
                      icon: Icons.hourglass_top,
                      color: Colors.orange,
                    ),
                    _buildBentoOverviewCard(
                      count: "$_freshArrivalsCount",
                      label: "Fresh Arrivals", // Add to dict later if needed
                      icon: Icons.new_releases_rounded,
                      color: Colors.green,
                    ),
                    _buildBentoOverviewCard(
                      count: "$_favoritesCount",
                      label: "Watchlist", // Add to dict later if needed
                      icon: Icons.favorite_rounded,
                      color: Colors.red,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 25),

              // 🚀 QUICK ACTIONS TITLE
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
                        "Market",
                        Icons.storefront_outlined,
                        const [Color(0xFF43A047), Color(0xFF2E7D32)], // Green
                        () async {
                          HapticFeedback.selectionClick();
                          await Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const BuyerMarketplaceScreen()));
                          _fetchRealData();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildZeptoActionButton(
                        "Track",
                        Icons.location_on_outlined,
                        const [Color(0xFF1E88E5), Color(0xFF1565C0)], // Blue
                        () async {
                          HapticFeedback.selectionClick();
                          await Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const BuyerOrdersScreen(
                                      initialIndex: 1)));
                          _fetchRealData();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildZeptoActionButton(
                        "Favorites",
                        Icons.favorite_outline_rounded,
                        const [Color(0xFFE53935), Color(0xFFC62828)], // Red
                        () async {
                          HapticFeedback.selectionClick();
                          await Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const BuyerFavoritesScreen()));
                          _fetchRealData();
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),

              // 🚀 MARKET INTELLIGENCE SECTION
              if (_currentUserId.isNotEmpty)
                BuyerMarketIntelligence(
                  buyerId: _currentUserId,
                  themeColor: _primaryBlue,
                ),

              const SizedBox(height: 24),
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

  Widget _buildWeatherCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: [_primaryBlue, _lightBlue],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: _primaryBlue.withOpacity(0.3),
              blurRadius: 15,
              offset: const Offset(0, 8))
        ],
      ),
      child: Row(
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
                      color: Colors.white,
                      fontSize: 34,
                      height: 1.1,
                      fontWeight: FontWeight.bold)),
              Row(children: [
                Icon(_weatherIcon, color: Colors.yellowAccent, size: 16),
                const SizedBox(width: 6),
                Text(_text(_conditionCode),
                    style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
              ]),
            ],
          ),
          Icon(_weatherIcon, size: 60, color: Colors.white.withOpacity(0.9)),
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
      margin: const EdgeInsets.symmetric(horizontal: 4),
      height: 6,
      width: _currentSlide == index ? 20 : 6,
      decoration: BoxDecoration(
          color: _currentSlide == index ? _primaryBlue : Colors.grey.shade300,
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
