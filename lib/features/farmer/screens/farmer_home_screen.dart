import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

// --- CUSTOM LOCALIZATION ENGINE ---
import 'package:agriyukt_app/features/farmer/farmer_translations.dart';
import 'package:agriyukt_app/core/providers/language_provider.dart';

import 'package:agriyukt_app/features/farmer/screens/add_crop_screen.dart';
import 'package:agriyukt_app/features/farmer/screens/orders_screen.dart';
import 'package:agriyukt_app/features/common/widgets/agri_stats_dashboard.dart';
import 'package:agriyukt_app/features/farmer/screens/widgets/farmer_drawer.dart';
import 'package:agriyukt_app/features/farmer/screens/widgets/market_intelligence_section.dart';

class FarmerHomeScreen extends StatefulWidget {
  const FarmerHomeScreen({super.key});

  @override
  State<FarmerHomeScreen> createState() => _FarmerHomeScreenState();
}

class _FarmerHomeScreenState extends State<FarmerHomeScreen> {
  String _name = "Farmer";
  int _cropCount = 0;
  int _pendingOrderCount = 0;
  int _activeOrderCount = 0;
  int _completedOrderCount = 0;
  bool _loading = true;

  String _temp = "--";
  String _condition = "--";
  IconData _weatherIcon = Icons.cloud;
  bool _weatherLoading = false;

  final PageController _pageController = PageController(initialPage: 3000);
  int _currentSlide = 0;
  Timer? _carouselTimer;

  final ScrollController _scrollController = ScrollController();

  final Color _primaryGreen = const Color(0xFF1B5E20);
  final Color _lightGreen = const Color(0xFF4CAF50);

  String _currentUserId = "";

  @override
  void initState() {
    super.initState();
    _currentUserId = Supabase.instance.client.auth.currentUser?.id ?? "";
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

  void _startAutoScroll() {
    _carouselTimer = Timer.periodic(const Duration(milliseconds: 3000), (
      timer,
    ) {
      if (_pageController.hasClients) {
        _pageController.nextPage(
          duration: const Duration(milliseconds: 600),
          curve: Curves.fastOutSlowIn,
        );
      }
    });
  }

  Future<void> _launchUrl(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Could not launch $urlString")));
      }
    }
  }

  // 🚀 Custom Translation Dictionary Access
  String _text(String key) => FarmerText.get(context, key);

  Future<void> _fetchRealData() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final client = Supabase.instance.client;

        final profile = await client
            .from('profiles')
            .select('first_name')
            .eq('id', user.id)
            .maybeSingle();
        final int crops = await client
            .from('crops')
            .count(CountOption.exact)
            .eq('farmer_id', user.id)
            .neq('status', 'Archived');
        final int pending = await client
            .from('orders')
            .count(CountOption.exact)
            .eq('farmer_id', user.id)
            .eq('status', 'Pending');
        final int active = await client
            .from('orders')
            .count(CountOption.exact)
            .eq('farmer_id', user.id)
            .or(
              'status.eq.Accepted,status.eq.Packed,status.eq.Shipped,status.eq.In Transit',
            );
        final int completed = await client
            .from('orders')
            .count(CountOption.exact)
            .eq('farmer_id', user.id)
            .or(
              'status.eq.Delivered,status.eq.Completed,status.eq.Rejected,status.eq.Cancelled',
            );

        if (mounted) {
          setState(() {
            _name = profile?['first_name'] ?? "Farmer";
            _cropCount = crops;
            _pendingOrderCount = pending;
            _activeOrderCount = active;
            _completedOrderCount = completed;
          });
        }
      }
    } catch (e) {
      debugPrint("Error: $e");
    } finally {
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
          timeLimit: const Duration(seconds: 5),
        );
        await _callWeatherApi(position.latitude, position.longitude);
      } else {
        await _callWeatherApi(21.1458, 79.0882);
      }
    } catch (e) {
      if (mounted) _callWeatherApi(21.1458, 79.0882);
    } finally {
      if (mounted) setState(() => _weatherLoading = false);
    }
  }

  Future<void> _callWeatherApi(double lat, double long) async {
    try {
      final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$long&current_weather=true',
      );
      final response = await http.get(url).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final current = data['current_weather'];
        if (mounted) {
          setState(() {
            _temp = "${current['temperature'].round()}°C";
            _condition = _getWeatherCode(current['weathercode']);
            _weatherIcon = _getWeatherIcon(current['weathercode']);
          });
        }
      }
    } catch (_) {}
  }

  String _getWeatherCode(int code) =>
      code <= 3 ? "Clear" : (code >= 51 ? "Rainy" : "Sunny");
  IconData _getWeatherIcon(int code) => code <= 3
      ? Icons.cloud
      : (code >= 51 ? Icons.water_drop : Icons.wb_sunny);

  @override
  Widget build(BuildContext context) {
    Provider.of<LanguageProvider>(context); // Rebuilds UI when language changes
    const EdgeInsets sectionPadding = EdgeInsets.symmetric(horizontal: 20);

    if (_loading) {
      return Center(child: CircularProgressIndicator(color: _primaryGreen));
    }

    return RefreshIndicator(
      onRefresh: () async {
        await _fetchRealData();
        await _fetchWeather();
        setState(() {});
      },
      color: _primaryGreen,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.only(bottom: 30),
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 15),

            // 🚀 Header (Uses the clean Custom Dictionary!)
            Padding(
              padding: sectionPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "${_text('namaste')}, $_name 👋",
                    style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: _primaryGreen,
                    ),
                  ),
                  Text(
                    DateFormat('EEEE, d MMMM').format(DateTime.now()),
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

            // Carousel
            Column(
              children: [
                SizedBox(
                  height: 160,
                  child: PageView.builder(
                    controller: _pageController,
                    onPageChanged: (idx) =>
                        setState(() => _currentSlide = idx % 4),
                    itemBuilder: (context, index) {
                      final int realIndex = index % 4;

                      if (realIndex == 0) {
                        return _buildWeatherCard();
                      } else if (realIndex == 1) {
                        return _buildActionPromoCard(
                          title: "SBI Agri Loan",
                          subtitle: "Apply for KCC with lowest rates",
                          badge: "FINANCE",
                          icon: Icons.account_balance,
                          colors: [
                            const Color(0xFF1E3C72),
                            const Color(0xFF2A5298),
                          ],
                          url:
                              "https://sbi.co.in/web/agri-rural/agriculture-banking/crop-loan/kisan-credit-card",
                        );
                      } else if (realIndex == 2) {
                        return _buildActionPromoCard(
                          title: "IFFCO Nano Urea",
                          subtitle: "Boost yield safely. Buy online now!",
                          badge: "FERTILIZER",
                          icon: Icons.science,
                          colors: [
                            const Color(0xFF00796B),
                            const Color(0xFF388E3C),
                          ],
                          url: "https://www.iffcobazar.in/en/product/nano-urea",
                        );
                      } else {
                        return _buildActionPromoCard(
                          title: "Premium Seeds",
                          subtitle: "Get up to 20% off high-yield seeds",
                          badge: "OFFER",
                          icon: Icons.spa,
                          colors: [
                            const Color(0xFFE65100),
                            const Color(0xFFFF8F00),
                          ],
                          url: "https://mahadhan.co.in/seeds/",
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(4, (index) => _buildDot(index)),
                ),
              ],
            ),
            const SizedBox(height: 25),

            // Overview Title
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

            // 🚀 "Bento Box" style Overview Grid
            Padding(
              padding: sectionPadding,
              child: GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 15,
                crossAxisSpacing: 15,
                childAspectRatio: 1.25,
                padding: EdgeInsets.zero,
                children: [
                  _buildBentoOverviewCard(
                    count: "$_cropCount",
                    label: _text('active_crops'),
                    icon: Icons.grass,
                    color: Colors.green,
                  ),
                  _buildBentoOverviewCard(
                    count: "$_pendingOrderCount",
                    label: _text('pending_req'),
                    icon: Icons.hourglass_top,
                    color: Colors.orange,
                  ),
                  _buildBentoOverviewCard(
                    count: "$_activeOrderCount",
                    label: _text('active_ship'),
                    icon: Icons.local_shipping_rounded,
                    color: Colors.blue,
                  ),
                  _buildBentoOverviewCard(
                    count: "$_completedOrderCount",
                    label: _text('total_history'),
                    icon: Icons.history_rounded,
                    color: Colors.purple,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 25),

            // Quick Actions Title
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

            // 🚀 Zepto-Style High Contrast Action Tabs
            Padding(
              padding: sectionPadding,
              child: Row(
                children: [
                  Expanded(
                    child: _buildZeptoActionButton(
                      _text('add_crop'),
                      Icons.add_circle_outline,
                      const [Color(0xFF43A047), Color(0xFF2E7D32)],
                      () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AddCropScreen(),
                          ),
                        );
                        _fetchRealData();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildZeptoActionButton(
                      _text('orders'),
                      Icons.receipt_long_rounded,
                      const [Color(0xFFFB8C00), Color(0xFFE65100)],
                      () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const OrdersScreen(),
                          ),
                        );
                        _fetchRealData();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildZeptoActionButton(
                      _text('live_track'),
                      Icons.location_on_outlined,
                      const [Color(0xFF1E88E5), Color(0xFF1565C0)],
                      () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const OrdersScreen(initialIndex: 1),
                          ),
                        );
                        _fetchRealData();
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),

            if (_currentUserId.isNotEmpty)
              MarketIntelligenceSection(farmerId: _currentUserId),

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
                  child: const AgriStatsDashboard(),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
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
          colors: [_primaryGreen, _lightGreen],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _primaryGreen.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _text('weather'),
                style: GoogleFonts.poppins(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _temp,
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Row(
                children: [
                  Icon(_weatherIcon, color: Colors.yellowAccent, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    _condition,
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Icon(_weatherIcon, color: Colors.white.withOpacity(0.9), size: 60),
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
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: colors[0].withOpacity(0.3),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      badge,
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.arrow_forward_ios,
                        color: Colors.white70,
                        size: 14,
                      ),
                    ],
                  ),
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

  Widget _buildDot(int index) => AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        height: 6,
        width: _currentSlide == index ? 20 : 6,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: _currentSlide == index ? _primaryGreen : Colors.grey[300],
          borderRadius: BorderRadius.circular(3),
        ),
      );

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
