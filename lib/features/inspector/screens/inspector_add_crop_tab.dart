import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart'; // 📍 GEO-TAGGING
import 'package:geocoding/geocoding.dart'; // 🌍 REVERSE GEOCODING

// 🚀 ARCHITECTURE PACKAGES
import 'package:agriyukt_app/features/farmer/screens/add_crop_screen.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

// ✅ LOCALIZATION IMPORTS
import 'package:agriyukt_app/features/farmer/farmer_translations.dart';
import 'package:agriyukt_app/core/providers/language_provider.dart';
import 'package:agriyukt_app/core/services/translation_service.dart';

extension InspectorSpecificStringExtension on String {
  String toInspectorCapitalized() =>
      length > 0 ? '${this[0].toUpperCase()}${substring(1).toLowerCase()}' : '';
  String toInspectorTitleCase() => replaceAll(RegExp(' +'), ' ')
      .split(' ')
      .map((str) => str.toInspectorCapitalized())
      .join(' ');
}

class InspectorAddCropTab extends StatefulWidget {
  final Map<String, dynamic>? preSelectedFarmer;
  final Map<String, dynamic>? cropToEdit;

  const InspectorAddCropTab({
    super.key,
    this.preSelectedFarmer,
    this.cropToEdit,
  });

  @override
  State<InspectorAddCropTab> createState() => _InspectorAddCropTabState();
}

class _InspectorAddCropTabState extends State<InspectorAddCropTab> {
  int _currentStep = 0;
  bool _isLoading = false;
  bool _isEditMode = false;
  bool _isFarmersLoading = true;
  bool _isDirty = false;
  bool _isScanningAI = false;
  bool _canPop = false;

  // 📍 Geo-Tagging Variables
  double? _latitude;
  double? _longitude;
  String _locationMessage = "";

  Map<String, dynamic>? _aiPrediction;
  bool _isFetchingAI = false;

  List<Map<String, dynamic>> _myFarmers = [];
  String? _selectedFarmerId;

  // 🎨 Premium Theme Colors (Inspector Purple)
  final Color _inspectorColor = const Color(0xFF512DA8);
  final Color _surfaceColor = const Color(0xFFF4F6F8);
  final Color _inputFillColor = const Color(0xFFFFFFFF);

  final List<String> _masterCategories = [
    "Vegetables",
    "Fruits",
    "Grains & Cereals",
    "Spices & Plantation",
    "Medicinal & Aromatic",
    "Flowers",
    "Pulses"
  ];

  final Map<String, List<String>> _indianVarieties = {
    "Tomato": [
      "Pusa Ruby",
      "Arka Vikas",
      "Arka Rakshak",
      "Roma",
      "Cherry",
      "Heirloom",
      "Local Desi",
      "Kashi Aman",
      "Pusa Rohini",
      "Abhilash",
      "S-22",
      "Kashi Chayan",
      "Pusa Hybrid-8",
      "Heemsohna",
      "Arka Samrat",
      "Vaibhav",
      "PKM-1",
      "Arka Visesh"
    ],
    "Brinjal": [
      "Pusa Kranti",
      "Arka Neelkanth",
      "Kashi Taru",
      "Pusa Uttam",
      "Manjari Gota",
      "Kashi Himani",
      "Arka Keshav",
      "Pusa Hybrid-6",
      "Arka Anand",
      "Bhanta",
      "CO-2",
      "Kashi Sandesh",
      "Pusa Purple Long",
      "Arka Shirish"
    ],
    "Chilli": [
      "Pusa Jwala",
      "Arka Meghna",
      "Kashi Anmol",
      "G-4",
      "Byadgi",
      "Kashi Ratna",
      "Pant C-1",
      "Teja",
      "Arka Harita",
      "Bird's Eye (Kanthari)",
      "K-1",
      "Kashi Early"
    ],
    "Onion": [
      "Agrifound Dark Red",
      "Pusa Red",
      "Bhima Shakti",
      "Lasalgaon Local",
      "N-2-4-1",
      "Bhima Kiran",
      "Pusa White Flat",
      "Sambar Onion (Shallots)",
      "Arka Kalyan",
      "CO-5",
      "Bhima Shweta"
    ],
    "Garlic": [
      "Yamuna Safed",
      "G-41",
      "Bhima Omkar",
      "Ooty-1",
      "Rajali",
      "HG-17",
      "Godavari"
    ],
    "Potato": [
      "Kufri Jyoti",
      "Kufri Bahar",
      "Kufri Pukhraj",
      "Kufri Chipsona",
      "Kufri Sindhuri",
      "Kufri Lauvkar",
      "Kufri Badshah",
      "Kufri Himsona",
      "Kufri Karan",
      "Kufri Chandramukhi",
      "Rosetta"
    ],
    "Mango": [
      "Alphonso",
      "Kesar",
      "Dashehari",
      "Amrapali",
      "Banganapalli",
      "Langra",
      "Chausa",
      "Totapuri",
      "Arka Anmol",
      "Arka Udaya",
      "CISH Arunika",
      "Mallika",
      "Ratna",
      "Sindhu",
      "Neelam"
    ],
    "Banana": [
      "Grand Naine",
      "Robusta",
      "Yelakki",
      "Poovan",
      "Nendran",
      "Ardhapuri",
      "Basrai",
      "Red Banana",
      "Monthan",
      "Karpuravalli",
      "Dweep Banana (CIARI)"
    ],
    "Rice": [
      "Basmati 1121",
      "Pusa Basmati 1509",
      "IR-64",
      "Swarna (MTU 7029)",
      "Indrayani",
      "Jaya",
      "Sonam",
      "Govind Bhog",
      "Black Rice (Chak-hao)",
      "HMT",
      "Wada Kolam",
      "Ponni"
    ],
    "Wheat": [
      "HD-2967",
      "HD-3086 (Pusa Gautami)",
      "PBW-343",
      "Lok-1",
      "Sharbati",
      "HI-1544 (Pusa Amrita)",
      "K-68",
      "DBW-187 (Karan Vandana)",
      "Sujata",
      "Durum"
    ],
  };

  final List<String> _gradeOptions = [
    "Grade A (Premium)",
    "Grade B (Standard)",
    "Grade C (Fair)",
    "Organic Certified"
  ];
  final List<String> _statusOptions = ['Active', 'Sold', 'Inactive'];
  final List<String> _unitOptions = [
    "Kg",
    "Quintal (q)",
    "Ton",
    "Crates",
    "Dozen"
  ];

  String _cropType = "Organic";
  String _status = "Active";
  String? _selectedCategory;
  String? _selectedVariety;
  String? _selectedGrade;
  String? _selectedUnit = "Quintal (q)";

  final _cropNameCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: "0");
  final _priceCtrl = TextEditingController(text: "0");
  final _notesCtrl = TextEditingController(text: "");

  DateTime? _harvestDate;
  DateTime? _availableDate;

  File? _selectedImage;
  String? _existingImageUrl;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _fetchMyFarmers();

    if (widget.cropToEdit != null) {
      _isEditMode = true;
      _prefillData(widget.cropToEdit!);
    } else if (widget.preSelectedFarmer != null) {
      _selectedFarmerId = widget.preSelectedFarmer!['id']?.toString();
    }

    _qtyCtrl.addListener(() => setState(() {}));
    _priceCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _cropNameCtrl.dispose();
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    _notesCtrl.dispose();
    _cleanupTempImage();
    super.dispose();
  }

  String _safeString(dynamic value, [String fallback = '']) {
    if (value == null) return fallback;
    return value.toString().trim();
  }

  Future<void> _cleanupTempImage() async {
    if (_selectedImage != null && !_isEditMode && !_isLoading) {
      try {
        if (_selectedImage!.existsSync()) {
          _selectedImage!.deleteSync();
        }
      } catch (e) {}
    }
  }

  void _markDirty() {
    if (!_isDirty) setState(() => _isDirty = true);
  }

  void _showError(String msg) {
    HapticFeedback.heavyImpact();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg,
            style:
                GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 13)),
        backgroundColor: Colors.red.shade800,
        duration: const Duration(seconds: 6),
        behavior: SnackBarBehavior.floating));
  }

  Future<void> _fetchMyFarmers() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final response = await Supabase.instance.client
          .from('profiles')
          .select('id, first_name, last_name, district, role')
          .eq('inspector_id', user.id);

      final List<dynamic> rawData = response as List<dynamic>;

      final parsedFarmers = rawData
          .map((e) => e as Map<String, dynamic>)
          .where((f) =>
              (f['role']?.toString().toLowerCase().trim() ?? '') == 'farmer')
          .toList();

      if (mounted) {
        setState(() {
          _myFarmers = parsedFarmers;
          _isFarmersLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isFarmersLoading = false);
    }
  }

  Future<List<String>> _searchCropsFromAPI(String query) async {
    if (query.isEmpty) return _indianVarieties.keys.toList();

    List<String> combinedResults = [];
    var localMatches = _indianVarieties.keys
        .where((k) => k.toLowerCase().contains(query.toLowerCase()))
        .toList();
    combinedResults.addAll(localMatches);

    if (query.length >= 2) {
      try {
        final url = Uri.parse("https://openfarm.cc/api/v1/crops?filter=$query");
        final response =
            await http.get(url).timeout(const Duration(seconds: 5));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final List records = data['data'] ?? [];
          List<String> apiResults = List<String>.from(records.map((e) =>
              e['attributes']['name'].toString().toInspectorTitleCase()));
          combinedResults.addAll(apiResults);
        }
      } catch (e) {}
    }
    return combinedResults.toSet().toList();
  }

  Future<void> _fetchAIPredictedPrice(String cropName) async {
    if (cropName.isEmpty) {
      setState(() => _aiPrediction = null);
      return;
    }
    setState(() => _isFetchingAI = true);
    try {
      final response = await Supabase.instance.client
          .from('market_predictions')
          .select()
          .ilike('crop_name', cropName.trim())
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _aiPrediction = response;
        _isFetchingAI = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isFetchingAI = false);
    }
  }

  // 📍 REVERSE GEOCODING LOCATION FETCHER
  Future<void> _fetchGPSCoordinates() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _locationMessage = "⚠️ Location disabled.");
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => _locationMessage = "⚠️ Permissions denied.");
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() => _locationMessage = "⚠️ Permissions permanently denied.");
      return;
    }

    try {
      setState(() => _locationMessage = "📍 Locating farm...");

      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
      });

      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(
            position.latitude, position.longitude);
        if (placemarks.isNotEmpty) {
          Placemark place = placemarks.first;
          String address = [
            place.street,
            place.subLocality,
            place.locality,
            place.postalCode
          ]
              .where((e) => e != null && e.toString().trim().isNotEmpty)
              .join(', ');

          if (address.isEmpty) {
            address = [place.subAdministrativeArea, place.administrativeArea]
                .where((e) => e != null && e.toString().trim().isNotEmpty)
                .join(', ');
          }

          setState(() {
            _locationMessage = "📍 $address";
          });
        } else {
          setState(() => _locationMessage = "📍 Farm Location Verified");
        }
      } catch (e) {
        setState(() => _locationMessage = "📍 Farm Location Verified");
      }
    } catch (e) {
      setState(() => _locationMessage = "⚠️ Failed to fetch location.");
    }
  }

  void _prefillData(Map<String, dynamic> c) {
    _selectedFarmerId = c['farmer_id']?.toString();

    String dbStatus = _safeString(c['status'], 'Active');
    if (dbStatus.isNotEmpty)
      dbStatus =
          dbStatus[0].toUpperCase() + dbStatus.substring(1).toLowerCase();
    _status = _statusOptions.contains(dbStatus) ? dbStatus : 'Active';

    String dbCategory = _safeString(c['category']);
    _selectedCategory = _masterCategories.contains(dbCategory)
        ? dbCategory
        : _masterCategories.first;

    _cropNameCtrl.text = _safeString(c['crop_name'], _safeString(c['name']))
        .toInspectorTitleCase();
    _selectedVariety = _safeString(c['variety']).toInspectorTitleCase();
    if (_selectedVariety!.isEmpty) _selectedVariety = null;
    _selectedGrade = _gradeOptions.contains(c['grade']) ? c['grade'] : null;

    _cropType = _safeString(c['crop_type'], "Organic");
    if (!["Organic", "Inorganic"].contains(_cropType)) _cropType = "Organic";

    String rawQty =
        _safeString(c['quantity_kg'], _safeString(c['quantity'], "0"));
    String qtyVal = "0";
    String parsedUnit = _safeString(c['unit'], "Quintal (q)");

    if (rawQty.contains(' ') && c['unit'] == null) {
      List<String> parts = rawQty.split(' ');
      qtyVal = parts[0].replaceAll(RegExp(r'[^0-9.]'), '');
      String unitPart = parts.sublist(1).join(' ').trim();
      for (var u in _unitOptions) {
        if (u.toLowerCase() == unitPart.toLowerCase()) {
          parsedUnit = u;
          break;
        }
      }
    } else {
      qtyVal = rawQty.replaceAll(RegExp(r'[^0-9.]'), '');
    }

    if (qtyVal.isEmpty) qtyVal = "0";
    _selectedUnit = parsedUnit;
    _qtyCtrl.text = qtyVal;

    _priceCtrl.text =
        _safeString(c['price_per_qty'], _safeString(c['price'], '0'));
    _notesCtrl.text = _safeString(c['description']);
    _existingImageUrl = _safeString(c['image_url']);
    if (_existingImageUrl!.isEmpty) _existingImageUrl = null;

    try {
      String hDate = _safeString(c['harvest_date']);
      if (hDate.isNotEmpty) _harvestDate = DateTime.tryParse(hDate);
      String aDate = _safeString(c['available_from']);
      if (aDate.isNotEmpty) _availableDate = DateTime.tryParse(aDate);
    } catch (_) {}

    if (_cropNameCtrl.text.isNotEmpty)
      _fetchAIPredictedPrice(_cropNameCtrl.text);
    setState(() {});
  }

  Future<void> _pickAndProcessImage(ImageSource source,
      {bool isSmartScan = false}) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(source: source);
      if (pickedFile == null) return;

      final croppedFile = await ImageCropper().cropImage(
        sourcePath: pickedFile.path,
        compressQuality: 100,
        uiSettings: [
          AndroidUiSettings(
              toolbarTitle: 'Edit Photo',
              toolbarColor: _inspectorColor,
              toolbarWidgetColor: Colors.white,
              initAspectRatio: CropAspectRatioPreset.square,
              lockAspectRatio: false),
          IOSUiSettings(title: 'Edit Photo'),
        ],
      );

      if (croppedFile == null) return;

      final dir = await getTemporaryDirectory();
      final targetPath =
          '${dir.absolute.path}/temp_${DateTime.now().millisecondsSinceEpoch}.jpg';
      var compressedFile = await FlutterImageCompress.compressAndGetFile(
          croppedFile.path, targetPath,
          quality: 70, minWidth: 800, minHeight: 800);

      File finalImage = compressedFile != null
          ? File(compressedFile.path)
          : File(croppedFile.path);

      _markDirty();
      if (!mounted) return;
      setState(() => _selectedImage = finalImage);

      await _fetchGPSCoordinates();

      if (isSmartScan) await _analyzeImageWithAI(finalImage);
    } catch (e) {
      if (mounted) _showError("Error processing image.");
    }
  }

  // 🚀 BULLETPROOF AI ENGINE
  Future<void> _analyzeImageWithAI(File imageFile) async {
    setState(() => _isScanningAI = true);

    try {
      // ⚠️⚠️⚠️ EXACT API KEY PROVIDED
      const apiKey = 'AIzaSyCWt7KjMacPXezn6AG_BIgrnEcgB5KVHXo';

      final model = GenerativeModel(
        model: 'gemini-1.5-flash',
        apiKey: apiKey,
        generationConfig: GenerationConfig(
          responseMimeType: 'application/json',
          temperature: 0.15,
        ),
      );
      final imageBytes = await imageFile.readAsBytes();

      final prompt = TextPart('''
        Analyze this image of an agricultural crop, plant, fruit, or vegetable.
        You must return a valid JSON object strictly matching this format. Do NOT wrap it in Markdown blocks.

        {
          "is_crop": true,
          "category": "Choose exactly one: Vegetables, Fruits, Grains & Cereals, Spices & Plantation, Medicinal & Aromatic, Flowers, Pulses",
          "crop_name": "Accurate common English name (e.g., Tomato, Wheat, Mango, Cotton)",
          "variety": "Identify the specific Indian variety if possible, otherwise output 'Local / Desi'",
          "grade": "Choose exactly one: Grade A (Premium), Grade B (Standard), Grade C (Fair), Organic Certified",
          "estimated_weight_kg": "Estimate the total weight shown in kilograms. Return ONLY a number (e.g., '50', '10', '5')",
          "days_until_harvest": "If already harvested return '0'. If still growing, estimate days left. Return ONLY a number.",
          "short_note": "A short, professional 1-sentence description of the visible quality and health of the crop."
        }

        If the image does NOT contain a crop (e.g., it is a person, an animal, a laptop, or a room), return exactly this:
        {
          "is_crop": false,
          "category": "", "crop_name": "", "variety": "", "grade": "", "estimated_weight_kg": "", "days_until_harvest": "", "short_note": ""
        }
      ''');

      final response = await model.generateContent([
        Content.multi([prompt, DataPart('image/jpeg', imageBytes)])
      ]).timeout(const Duration(seconds: 30));

      String responseText = response.text ?? '{}';
      responseText =
          responseText.replaceAll('```json', '').replaceAll('```', '').trim();
      final data = jsonDecode(responseText);

      if (!mounted) return;

      // 🛑 REJECT FAKE IMAGES
      if (data['is_crop'] == false || data['is_crop'] == 'false') {
        _showError(
            "⚠️ Unrecognized Image. Please capture a clear photo of an agricultural crop.");
        setState(() => _isScanningAI = false);
        return;
      }

      setState(() {
        if (data['category'] != null && data['category'].toString().isNotEmpty)
          _selectedCategory =
              data['category'].toString().toInspectorTitleCase();
        if (data['grade'] != null && data['grade'].toString().isNotEmpty)
          _selectedGrade = data['grade'];
        if (data['crop_name'] != null &&
            data['crop_name'].toString().isNotEmpty)
          _cropNameCtrl.text =
              data['crop_name'].toString().toInspectorTitleCase();
        if (data['variety'] != null && data['variety'].toString().isNotEmpty)
          _selectedVariety = data['variety'].toString().toInspectorTitleCase();

        if (data['estimated_weight_kg'] != null &&
            data['estimated_weight_kg'].toString().isNotEmpty) {
          String weight = data['estimated_weight_kg']
              .toString()
              .replaceAll(RegExp(r'[^0-9.]'), '');
          if (weight.isNotEmpty) {
            _qtyCtrl.text = weight;
            _selectedUnit = "Kg";
          }
        }

        if (data['days_until_harvest'] != null &&
            data['days_until_harvest'].toString().isNotEmpty) {
          int days = int.tryParse(data['days_until_harvest']
                  .toString()
                  .replaceAll(RegExp(r'[^0-9]'), '')) ??
              0;
          _harvestDate = DateTime.now().add(Duration(days: days));
          _availableDate = _harvestDate;
        }

        if (data['short_note'] != null &&
            data['short_note'].toString().isNotEmpty) {
          _notesCtrl.text = data['short_note'].toString();
        }
      });

      if (_cropNameCtrl.text.isNotEmpty)
        _fetchAIPredictedPrice(_cropNameCtrl.text);
      HapticFeedback.mediumImpact();

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("✅ AI verified: ${_cropNameCtrl.text}!",
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          backgroundColor: _inspectorColor,
          behavior: SnackBarBehavior.floating));
    } on TimeoutException {
      debugPrint("🚨 AI Error: Timeout");
      if (mounted)
        _showError("⏳ Connection timed out. Please enter details manually.");
    } on GenerativeAIException catch (e) {
      debugPrint("🚨 AI API Error: ${e.message}");
      if (mounted) _showError("🤖 AI Error: ${e.message}");
    } catch (e) {
      debugPrint("🚨 General AI Error: $e");
      if (mounted)
        _showError("⚠️ Could not auto-detect. Please enter details manually.");
    } finally {
      if (mounted) setState(() => _isScanningAI = false);
    }
  }

  void _showImagePickerOptions({bool isSmartScan = false}) {
    FocusScope.of(context).unfocus();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10))),
              const SizedBox(height: 20),
              Text(
                  isSmartScan ? "Smart Crop Detection 🤖" : "Upload Crop Photo",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87)),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(
                      child: _pickerOption(Icons.camera_alt_rounded, "Camera",
                          ImageSource.camera,
                          isSmartScan: isSmartScan)),
                  const SizedBox(width: 16),
                  Expanded(
                      child: _pickerOption(Icons.photo_library_rounded,
                          "Gallery", ImageSource.gallery,
                          isSmartScan: isSmartScan)),
                ],
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pickerOption(IconData icon, String label, ImageSource src,
      {bool isSmartScan = false}) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        _pickAndProcessImage(src, isSmartScan: isSmartScan);
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
            color: _inspectorColor.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _inspectorColor.withOpacity(0.15))),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 40, color: _inspectorColor),
          const SizedBox(height: 12),
          Text(label,
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: _inspectorColor))
        ]),
      ),
    );
  }

  void _handleStepContinue() {
    FocusScope.of(context).unfocus();
    if (_currentStep == 0) {
      if (_selectedFarmerId == null)
        return _showError("⚠️ Please select a Farmer.");
      if (_selectedCategory == null)
        return _showError("⚠️ Please select a Category.");
      if (_cropNameCtrl.text.isEmpty)
        return _showError("⚠️ Please enter a Crop Name.");

      final String cleanQty = _qtyCtrl.text.replaceAll(',', '').trim();
      final String cleanPrice = _priceCtrl.text.replaceAll(',', '').trim();

      final double parsedQ = double.tryParse(cleanQty) ?? 0.0;
      final double parsedP = double.tryParse(cleanPrice) ?? 0.0;

      if (cleanQty.isEmpty || parsedQ <= 0)
        return _showError("⚠️ Please enter a valid Quantity greater than 0.");
      if (cleanPrice.isEmpty || parsedP <= 0)
        return _showError("⚠️ Please enter a valid Price greater than 0.");
    }

    if (_currentStep < 1) {
      setState(() => _currentStep++);
    } else {
      _submit();
    }
  }

  Future<void> _submit() async {
    if (_isLoading) return;
    if (!_isEditMode && _selectedImage == null) {
      return _showError("⚠️ Please upload a photo of the crop.");
    }
    if (_selectedImage != null &&
        _selectedImage!.lengthSync() > 5 * 1024 * 1024) {
      return _showError("Image is too large. Max allowed is 5MB.");
    }

    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw "Authentication error. Please log in again.";

      String? imageUrl = _existingImageUrl;

      if (_selectedImage != null) {
        final ext = _selectedImage!.path.split('.').last.toLowerCase();
        final safeExt =
            ['jpg', 'jpeg', 'png', 'webp'].contains(ext) ? ext : 'jpg';
        final String uniqueSuffix =
            DateTime.now().millisecondsSinceEpoch.toString();
        final fileName = 'crops/${user.id}_$uniqueSuffix.$safeExt';

        await Supabase.instance.client.storage
            .from('crop_images')
            .uploadBinary(fileName, await _selectedImage!.readAsBytes(),
                fileOptions:
                    FileOptions(upsert: true, contentType: 'image/$safeExt'))
            .timeout(const Duration(seconds: 30));

        imageUrl = Supabase.instance.client.storage
            .from('crop_images')
            .getPublicUrl(fileName);

        if (_isEditMode &&
            _existingImageUrl != null &&
            _existingImageUrl!.contains('/crop_images/')) {
          try {
            final oldPath = _existingImageUrl!.split('/crop_images/').last;
            await Supabase.instance.client.storage
                .from('crop_images')
                .remove([oldPath]);
          } catch (_) {}
        }
      }

      double qtyVal =
          double.tryParse(_qtyCtrl.text.replaceAll(',', '').trim()) ?? 0;
      double parsedPrice =
          double.tryParse(_priceCtrl.text.replaceAll(',', '').trim()) ?? 0.0;
      double finalKg = qtyVal;

      if (_selectedUnit == 'Quintal (q)')
        finalKg = qtyVal * 100;
      else if (_selectedUnit == 'Ton') finalKg = qtyVal * 1000;

      String englishNotes = _notesCtrl.text.trim();

      final Map<String, dynamic> cropData = {
        'farmer_id': _selectedFarmerId,
        'inspector_id': user.id,
        'category': _selectedCategory,
        'crop_name': _cropNameCtrl.text.trim(),
        'variety': _selectedVariety ?? "Local / Other",
        'grade': _selectedGrade,
        'quantity': qtyVal,
        'unit': _selectedUnit,
        'price': parsedPrice,
        'crop_type': _cropType,
        'status': _status,
        'harvest_date': _harvestDate?.toIso8601String(),
        'available_from': _availableDate?.toIso8601String(),
        'description': englishNotes,
        'image_url': imageUrl,
        'latitude': _latitude, // 📍 Appended Geo-Tag
        'longitude': _longitude, // 📍 Appended Geo-Tag
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (_isEditMode && widget.cropToEdit != null) {
        if (widget.cropToEdit!.containsKey('quantity_kg'))
          cropData['quantity_kg'] = finalKg;
        if (widget.cropToEdit!.containsKey('price_per_qty'))
          cropData['price_per_qty'] = parsedPrice;
      } else {
        cropData['quantity_kg'] = finalKg;
        cropData['price_per_qty'] = parsedPrice;
      }

      try {
        if (_isEditMode) {
          await Supabase.instance.client
              .from('crops')
              .update(cropData)
              .eq('id', widget.cropToEdit!['id'])
              .timeout(const Duration(seconds: 15));
        } else {
          cropData['created_at'] = DateTime.now().toIso8601String();
          await Supabase.instance.client
              .from('crops')
              .insert(cropData)
              .timeout(const Duration(seconds: 15));
        }
      } catch (dbError) {
        if (dbError.toString().contains('PGRST204') ||
            dbError.toString().contains('Could not find the')) {
          cropData.remove('quantity_kg');
          cropData.remove('price_per_qty');
          cropData.remove('latitude');
          cropData.remove('longitude');
          if (_isEditMode)
            await Supabase.instance.client
                .from('crops')
                .update(cropData)
                .eq('id', widget.cropToEdit!['id']);
          else
            await Supabase.instance.client.from('crops').insert(cropData);
        } else {
          rethrow;
        }
      }

      if (!mounted) return;
      HapticFeedback.mediumImpact();
      _markDirty();

      setState(() {
        _isDirty = false;
        _canPop = true;
        _currentStep = 0;
        _qtyCtrl.text = "0";
        _priceCtrl.text = "0";
        _notesCtrl.clear();
        _cropNameCtrl.clear();
        _selectedCategory = null;
        _selectedVariety = null;
        _selectedGrade = null;
        _aiPrediction = null;
        _selectedImage = null;
        _harvestDate = null;
        _availableDate = null;
        _cropType = "Organic";
        _latitude = null;
        _longitude = null;
        _locationMessage = ""; // Clear Location
      });

      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              _isEditMode
                  ? "✅ Crop Updated Successfully!"
                  : "✅ Crop Listed Successfully!",
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating));
    } catch (e) {
      if (mounted) _showError("Failed to save. Check connection.");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isPushed = ModalRoute.of(context)?.canPop ?? false;

    return AbsorbPointer(
      absorbing: _isLoading || _isScanningAI,
      child: PopScope(
        canPop: _canPop,
        onPopInvoked: (didPop) async {
          if (didPop) return;
          if (_isLoading || _isScanningAI) return;
          if (!_isDirty) {
            setState(() => _canPop = true);
            Navigator.pop(context);
            return;
          }
          final bool? discard = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: Text("Discard Changes?",
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold, color: Colors.black87)),
              content: Text(
                  "You have unsaved crop data. Are you sure you want to go back?",
                  style: GoogleFonts.poppins(
                      fontSize: 14, color: Colors.grey.shade600)),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text("KEEP EDITING",
                        style: GoogleFonts.poppins(
                            color: _inspectorColor,
                            fontWeight: FontWeight.bold))),
                ElevatedButton(
                    onPressed: () {
                      _cleanupTempImage();
                      Navigator.pop(context, true);
                    },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade600,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10))),
                    child: Text("DISCARD",
                        style: GoogleFonts.poppins(
                            color: Colors.white, fontWeight: FontWeight.bold))),
              ],
            ),
          );
          if (discard == true && mounted) {
            setState(() => _canPop = true);
            Navigator.pop(context);
          }
        },
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Scaffold(
            backgroundColor: _surfaceColor,
            appBar: isPushed || _isEditMode
                ? AppBar(
                    title: Text(
                        _isEditMode ? "Edit Crop Listing" : "Add New Crop",
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            fontSize: 18,
                            color: Colors.black87)),
                    backgroundColor: Colors.white,
                    iconTheme: const IconThemeData(color: Colors.black87),
                    elevation: 0,
                    centerTitle: true,
                  )
                : null,
            body: Stack(
              children: [
                Column(
                  children: [
                    _buildCustomStepperHeader(),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: 120),
                        physics: const BouncingScrollPhysics(),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child:
                              _currentStep == 0 ? _buildStep1() : _buildStep2(),
                        ),
                      ),
                    ),
                  ],
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: EdgeInsets.fromLTRB(
                        20, 16, 20, MediaQuery.of(context).padding.bottom + 16),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 20,
                              offset: const Offset(0, -10))
                        ],
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(30))),
                    child: Row(
                      children: [
                        if (_currentStep > 0)
                          Expanded(
                            child: OutlinedButton(
                                onPressed: () => setState(() => _currentStep--),
                                style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                    side: BorderSide(
                                        color: Colors.grey.shade300, width: 2),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(16))),
                                child: Text("Back",
                                    style: GoogleFonts.poppins(
                                        color: Colors.black87,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15))),
                          ),
                        if (_currentStep > 0) const SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                              onPressed: _handleStepContinue,
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: _inspectorColor,
                                  elevation: 0,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16))),
                              child: Text(
                                  _currentStep == 1
                                      ? (_isEditMode
                                          ? "Update Listing"
                                          : "Publish Crop")
                                      : "Next Step",
                                  style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      letterSpacing: 0.5))),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_isLoading) _buildFullScreenLoader("Saving Crop Data..."),
                if (_isScanningAI)
                  _buildFullScreenLoader("🤖 AI Analyzing Image..."),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCustomStepperHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          _buildStepTab(0, "Info & Rate", Icons.info_outline_rounded),
          const SizedBox(width: 12),
          _buildStepTab(1, "Details", Icons.photo_camera_back_rounded),
        ],
      ),
    );
  }

  Widget _buildStepTab(int stepIndex, String title, IconData icon) {
    bool isActive = _currentStep == stepIndex;
    bool isCompleted = _currentStep > stepIndex;

    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isActive
              ? _inspectorColor
              : (isCompleted
                  ? _inspectorColor.withOpacity(0.1)
                  : _inputFillColor),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(isCompleted ? Icons.check_circle_rounded : icon,
                size: 18,
                color: isActive
                    ? Colors.white
                    : (isCompleted ? _inspectorColor : Colors.grey.shade600)),
            const SizedBox(width: 8),
            Text(title,
                style: GoogleFonts.poppins(
                    color: isActive
                        ? Colors.white
                        : (isCompleted
                            ? _inspectorColor
                            : Colors.grey.shade600),
                    fontWeight: isActive || isCompleted
                        ? FontWeight.bold
                        : FontWeight.w500,
                    fontSize: 13))
          ],
        ),
      ),
    );
  }

  Widget _buildSafeFarmerDropdown() {
    if (_isFarmersLoading) {
      return Container(
          margin: const EdgeInsets.only(bottom: 16, top: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
              color: _inputFillColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300)),
          child: LinearProgressIndicator(color: _inspectorColor));
    }
    String? safeValue = _selectedFarmerId;
    if (safeValue != null &&
        !_myFarmers.any((f) => f['id'].toString() == safeValue)) {
      safeValue = null;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, top: 4),
      child: DropdownButtonFormField2<String>(
        isExpanded: true,
        decoration: _inputDecoration("Select Farmer *", Icons.person),
        value: safeValue,
        items: _myFarmers.map((f) {
          final fullName =
              "${f['first_name'] ?? ''} ${f['last_name'] ?? ''}".trim();
          final dist = f['district'] ?? 'Unknown';
          return DropdownMenuItem(
              value: f['id'].toString(),
              child: Text(
                  fullName.isEmpty
                      ? "Unknown Farmer ($dist)"
                      : "$fullName ($dist)",
                  style:
                      GoogleFonts.poppins(fontSize: 14, color: Colors.black87),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis));
        }).toList(),
        onChanged: _isEditMode || widget.preSelectedFarmer != null
            ? null
            : (v) {
                _markDirty();
                setState(() => _selectedFarmerId = v);
              },
        buttonStyleData:
            const ButtonStyleData(padding: EdgeInsets.only(right: 4)),
        iconStyleData: const IconStyleData(
            icon: Icon(Icons.expand_more, color: Colors.grey)),
        dropdownStyleData: DropdownStyleData(
            maxHeight: 300,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12))),
        menuItemStyleData: const MenuItemStyleData(
            padding: EdgeInsets.symmetric(horizontal: 16)),
      ),
    );
  }

  Widget _buildStep1() {
    return Padding(
      key: const ValueKey('step1'),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSafeFarmerDropdown(),
          const SizedBox(height: 8),
          if (!_isEditMode) ...[
            InkWell(
              onTap: () => _showImagePickerOptions(isSmartScan: true),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFF6200EA), Color(0xFF311B92)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight),
                    boxShadow: [
                      BoxShadow(
                          color: _inspectorColor.withOpacity(0.3),
                          blurRadius: 15,
                          offset: const Offset(0, 6))
                    ],
                    borderRadius: BorderRadius.circular(20)),
                child: Row(children: [
                  Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle),
                      child: const Icon(Icons.document_scanner_rounded,
                          color: Colors.white, size: 28)),
                  const SizedBox(width: 16),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text("Smart Auto-Fill 🤖",
                            style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                        const SizedBox(height: 4),
                        Text("Snap a photo, AI does the data entry.",
                            style: GoogleFonts.poppins(
                                fontSize: 12, color: Colors.white70))
                      ])),
                  const Icon(Icons.arrow_forward_ios_rounded,
                      color: Colors.white70, size: 18)
                ]),
              ),
            ),
            const SizedBox(height: 24),
          ],
          if (_isEditMode) ...[
            _sectionLabel("Listing Status", Icons.toggle_on_rounded),
            const SizedBox(height: 12),
            _dropdown(null, _status, _statusOptions, (v) {
              _markDirty();
              setState(() => _status = v!);
            }, icon: Icons.storefront_rounded),
            const SizedBox(height: 24),
          ],
          _sectionLabel("Farming Method", Icons.eco_rounded),
          const SizedBox(height: 12),
          Row(children: [
            _typeButton(
                "Organic", const Color(0xFF0F9D58), Icons.grass_rounded),
            const SizedBox(width: 16),
            _typeButton(
                "Inorganic", Colors.blueGrey.shade600, Icons.science_rounded),
          ]),
          const SizedBox(height: 32),
          _sectionLabel("Crop Classification", Icons.category_rounded),
          const SizedBox(height: 12),
          _buildDropdown2("Category *", _selectedCategory, _masterCategories,
              (val) {
            _markDirty();
            setState(() {
              _selectedCategory = val;
              _cropNameCtrl.clear();
              _selectedVariety = null;
              _aiPrediction = null;
            });
          }, icon: Icons.grid_view_rounded),
          const SizedBox(height: 16),
          TypeAheadField<String>(
            controller: _cropNameCtrl,
            builder: (context, controller, focusNode) {
              return _inputFieldBase(controller, focusNode,
                  "Crop Name (Search) *", Icons.local_florist_rounded);
            },
            suggestionsCallback: (pattern) async =>
                await _searchCropsFromAPI(pattern),
            itemBuilder: (context, String suggestion) {
              return ListTile(
                  title: Text(suggestion,
                      style: GoogleFonts.poppins(fontSize: 14)),
                  dense: true);
            },
            onSelected: (String suggestion) {
              _markDirty();
              setState(() {
                _cropNameCtrl.text = suggestion;
                _selectedVariety = null;
              });
              _fetchAIPredictedPrice(suggestion);
            },
            emptyBuilder: (context) => Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text("Type manually if not found.",
                    style:
                        GoogleFonts.poppins(color: Colors.grey, fontSize: 13))),
          ),
          const SizedBox(height: 16),
          _buildAIPricingGuide(),
          Builder(builder: (context) {
            List<String> varieties =
                _indianVarieties[_cropNameCtrl.text.toInspectorTitleCase()] ??
                    ["Local / Desi", "Hybrid", "Other"];
            if (_selectedVariety != null &&
                !varieties.contains(_selectedVariety))
              varieties.insert(0, _selectedVariety!);
            return _buildDropdown2(
                "Variety (Optional)", _selectedVariety, varieties, (val) {
              _markDirty();
              setState(() => _selectedVariety = val);
            }, icon: Icons.style_rounded);
          }),
          const SizedBox(height: 16),
          _buildDropdown2("Quality Grade", _selectedGrade, _gradeOptions, (v) {
            _markDirty();
            setState(() => _selectedGrade = v);
          }, icon: Icons.workspace_premium_rounded),
          const SizedBox(height: 32),
          _sectionLabel("Inventory & Pricing", Icons.inventory_2_rounded),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                flex: 5,
                child: _inputField("Quantity Available *", _qtyCtrl,
                    type: const TextInputType.numberWithOptions(decimal: true),
                    icon: Icons.scale_rounded)),
            const SizedBox(width: 12),
            Expanded(
                flex: 4,
                child: _dropdown("Unit", _selectedUnit, _unitOptions, (v) {
                  _markDirty();
                  setState(() => _selectedUnit = v);
                })),
          ]),
          const SizedBox(height: 16),
          _inputField("Price per Unit (₹) *", _priceCtrl,
              type: const TextInputType.numberWithOptions(decimal: true),
              prefix: "₹ ",
              icon: Icons.sell_rounded),
          const SizedBox(height: 24),
          _buildSummaryCard(),
        ],
      ),
    );
  }

  Widget _buildStep2() {
    return Padding(
      key: const ValueKey('step2'),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel("Harvest Timelines", Icons.calendar_month_rounded),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: _datePicker("Harvest Date", _harvestDate, (d) {
              _markDirty();
              setState(() => _harvestDate = d);
            }, isHarvest: true)),
            const SizedBox(width: 16),
            Expanded(
                child: _datePicker("Available From", _availableDate, (d) {
              _markDirty();
              setState(() => _availableDate = d);
            }, isHarvest: false)),
          ]),
          const SizedBox(height: 32),

          _sectionLabel("Additional Notes", Icons.description_rounded),
          const SizedBox(height: 12),
          _inputField("Description", _notesCtrl,
              type: TextInputType.multiline, maxLines: 4),
          const SizedBox(height: 32),

          _sectionLabel("Visual Verification *", Icons.image_rounded),
          const SizedBox(height: 12),
          InkWell(
            onTap: () => _showImagePickerOptions(isSmartScan: false),
            borderRadius: BorderRadius.circular(20),
            child: Container(
                height: 220,
                width: double.infinity,
                decoration: BoxDecoration(
                    color: _inputFillColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color:
                            _selectedImage != null || _existingImageUrl != null
                                ? _inspectorColor
                                : Colors.transparent,
                        width: 2)),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (_selectedImage != null)
                      ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Image.file(_selectedImage!,
                              width: double.infinity,
                              height: double.infinity,
                              fit: BoxFit.cover))
                    else if (_existingImageUrl != null)
                      ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Image.network(
                              _existingImageUrl!.startsWith('http')
                                  ? _existingImageUrl!
                                  : Supabase.instance.client.storage
                                      .from('crop_images')
                                      .getPublicUrl(_existingImageUrl!),
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity))
                    else
                      Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                                padding: const EdgeInsets.all(16),
                                decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle),
                                child: Icon(Icons.cloud_upload_rounded,
                                    size: 36, color: _inspectorColor)),
                            const SizedBox(height: 16),
                            Text("Upload Photo",
                                style: GoogleFonts.poppins(
                                    color: Colors.black87,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15)),
                            const SizedBox(height: 4),
                            Text("High quality JPG or PNG (Max 5MB)",
                                style: GoogleFonts.poppins(
                                    color: Colors.grey.shade500, fontSize: 12)),
                          ]),
                    if (_selectedImage != null || _existingImageUrl != null)
                      Positioned(
                          bottom: 16,
                          right: 16,
                          child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                  color: Colors.black87,
                                  borderRadius: BorderRadius.circular(20)),
                              child: Row(children: [
                                const Icon(Icons.edit_rounded,
                                    size: 16, color: Colors.white),
                                const SizedBox(width: 8),
                                Text("Replace",
                                    style: GoogleFonts.poppins(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600)),
                              ])))
                  ],
                )),
          ),

          // 📍 LOCATION BADGE UI
          if (_locationMessage.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16.0),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                    color: Colors.deepPurple.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.deepPurple.shade200)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.location_on, color: _inspectorColor, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(_locationMessage,
                            style: GoogleFonts.poppins(
                                fontSize: 13,
                                color: Colors.deepPurple.shade800,
                                fontWeight: FontWeight.w600))),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    double q =
        double.tryParse(_qtyCtrl.text.replaceAll(RegExp(r'[^0-9.]'), '')) ??
            0.0;
    double p =
        double.tryParse(_priceCtrl.text.replaceAll(RegExp(r'[^0-9.]'), '')) ??
            0.0;
    String total = (q * p).toStringAsFixed(0);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: _inspectorColor.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _inspectorColor.withOpacity(0.1))),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
                color: Colors.white, shape: BoxShape.circle),
            child: Icon(Icons.account_balance_wallet_rounded,
                color: _inspectorColor, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Estimated Total Value",
                    style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w500)),
                Text("₹$total",
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                        fontSize: 26),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String l, IconData icon) => Row(
        children: [
          Icon(icon, size: 20, color: _inspectorColor),
          const SizedBox(width: 8),
          Text(l,
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.black87)),
        ],
      );

  Widget _buildDropdown2(String label, String? currentValue, List<String> items,
      Function(String?) onChanged,
      {IconData? icon}) {
    if (currentValue != null && !items.contains(currentValue))
      items = [currentValue, ...items];
    return DropdownButtonFormField2<String>(
      isExpanded: true,
      iconStyleData: IconStyleData(
          icon: Icon(Icons.keyboard_arrow_down_rounded,
              color: Colors.grey.shade600)),
      items: items
          .map((e) => DropdownMenuItem(
              value: e,
              child: Text(e,
                  style:
                      GoogleFonts.poppins(fontSize: 15, color: Colors.black87),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis)))
          .toList(),
      onChanged: onChanged,
      value: currentValue,
      decoration: _inputDecoration(label, icon),
      buttonStyleData:
          const ButtonStyleData(padding: EdgeInsets.only(right: 8)),
      dropdownStyleData: DropdownStyleData(
          maxHeight: 300,
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16), color: Colors.white)),
      menuItemStyleData: const MenuItemStyleData(
          padding: EdgeInsets.symmetric(horizontal: 16)),
    );
  }

  Widget _dropdown(String? label, String? value, List<String> items,
      Function(String?) onChanged,
      {IconData? icon}) {
    return _buildDropdown2(label ?? "", value, items, onChanged, icon: icon);
  }

  InputDecoration _inputDecoration(String label, IconData? icon,
      {String? prefix}) {
    return InputDecoration(
      labelText: label,
      labelStyle:
          GoogleFonts.poppins(color: Colors.grey.shade600, fontSize: 14),
      prefixText: prefix,
      prefixStyle: GoogleFonts.poppins(
          fontWeight: FontWeight.bold, color: Colors.black87, fontSize: 15),
      prefixIcon: icon != null
          ? Icon(icon, color: Colors.grey.shade500, size: 22)
          : null,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: _inspectorColor, width: 2)),
      filled: true,
      fillColor: _inputFillColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
    );
  }

  Widget _inputFieldBase(TextEditingController ctrl, FocusNode? focusNode,
      String label, IconData icon) {
    return TextField(
      controller: ctrl,
      focusNode: focusNode,
      onChanged: (_) => _markDirty(),
      style: GoogleFonts.poppins(fontSize: 15, color: Colors.black87),
      decoration: _inputDecoration(label, icon).copyWith(
          suffixIcon: Icon(Icons.keyboard_arrow_down_rounded,
              color: Colors.grey.shade600)),
    );
  }

  Widget _inputField(String label, TextEditingController ctrl,
      {TextInputType type = TextInputType.text,
      int maxLines = 1,
      String? prefix,
      IconData? icon}) {
    return TextFormField(
      controller: ctrl,
      keyboardType: type,
      maxLines: maxLines,
      inputFormatters:
          type == const TextInputType.numberWithOptions(decimal: true)
              ? [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))]
              : null,
      style: GoogleFonts.poppins(fontSize: 15, color: Colors.black87),
      onChanged: (_) => _markDirty(),
      decoration: _inputDecoration(label, icon, prefix: prefix),
    );
  }

  Widget _datePicker(String label, DateTime? date, Function(DateTime) onConfirm,
      {bool isHarvest = false}) {
    return InkWell(
      onTap: () async {
        FocusScope.of(context).unfocus();
        final d = await showDatePicker(
            context: context,
            initialDate: date ?? DateTime.now(),
            firstDate: isHarvest ? DateTime(2020) : DateTime.now(),
            lastDate: DateTime(2030),
            builder: (context, child) => Theme(
                data: Theme.of(context).copyWith(
                    colorScheme: ColorScheme.light(primary: _inspectorColor)),
                child: child!));
        if (d != null) {
          _markDirty();
          onConfirm(d);
        }
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        decoration: BoxDecoration(
            color: _inputFillColor, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: GoogleFonts.poppins(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                    date == null
                        ? "Select"
                        : "${date.day}/${date.month}/${date.year}",
                    style: GoogleFonts.poppins(
                        color: date == null
                            ? Colors.grey.shade400
                            : Colors.black87,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
                Icon(Icons.calendar_month_rounded,
                    color: Colors.grey.shade500, size: 20),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeButton(String type, Color activeColor, IconData icon) {
    bool isSelected = _cropType == type;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus();
          _markDirty();
          setState(() => _cropType = type);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: isSelected ? activeColor : _inputFillColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                        color: activeColor.withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4))
                  ]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 20,
                  color: isSelected ? Colors.white : Colors.grey.shade600),
              const SizedBox(width: 8),
              Flexible(
                  child: Text(type,
                      style: GoogleFonts.poppins(
                          color: isSelected ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.bold,
                          fontSize: 14),
                      overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFullScreenLoader(String message) {
    return Container(
        color: Colors.white.withOpacity(0.9),
        child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  color: _inspectorColor.withOpacity(0.1),
                  shape: BoxShape.circle),
              child: CircularProgressIndicator(
                  color: _inspectorColor, strokeWidth: 3)),
          const SizedBox(height: 24),
          Text(message,
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: _inspectorColor))
        ])));
  }

  Widget _buildAIPricingGuide() {
    if (_isFetchingAI) {
      return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(children: [
            const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.black87)),
            const SizedBox(width: 10),
            Text("Analyzing market data...",
                style: GoogleFonts.poppins(color: Colors.grey, fontSize: 13))
          ]));
    }
    if (_aiPrediction == null) return const SizedBox.shrink();

    final double liveAvg =
        double.tryParse(_aiPrediction!['live_price']?.toString() ?? '0') ?? 0.0;
    final double predicted =
        double.tryParse(_aiPrediction!['predicted_price']?.toString() ?? '0') ??
            0.0;
    final double trend =
        double.tryParse(_aiPrediction!['trend_percent']?.toString() ?? '0') ??
            0.0;
    final bool isUpward = _aiPrediction!['is_upward'] == true;
    final Color trendColor =
        isUpward ? const Color(0xFF10B981) : Colors.orangeAccent;
    final IconData trendIcon =
        isUpward ? Icons.trending_up_rounded : Icons.trending_down_rounded;

    return Container(
        margin: const EdgeInsets.only(bottom: 24),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 15,
                  offset: const Offset(0, 8))
            ]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.auto_awesome_rounded,
                    color: Colors.amberAccent, size: 16)),
            const SizedBox(width: 10),
            Text("AI Market Intelligence",
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 14))
          ]),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("Current Avg",
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: Colors.grey.shade400)),
              Text("₹${liveAvg.toStringAsFixed(1)}",
                  style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white))
            ]),
            Container(width: 1, height: 35, color: Colors.grey.shade800),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text("Prediction",
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: Colors.grey.shade400)),
              Row(children: [
                Icon(trendIcon, color: trendColor, size: 18),
                const SizedBox(width: 6),
                Text("₹${predicted.toStringAsFixed(1)}",
                    style: GoogleFonts.poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: trendColor))
              ])
            ])
          ]),
          const SizedBox(height: 16),
          Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Icon(Icons.info_outline_rounded,
                    color: Colors.grey.shade400, size: 16),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(
                        isUpward
                            ? "Trending up by ${trend.toStringAsFixed(1)}%. Set higher margins."
                            : "Trending down by ${trend.toStringAsFixed(1)}%. Price competitively.",
                        style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey.shade300)))
              ]))
        ]));
  }
}
