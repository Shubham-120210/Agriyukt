import 'dart:io';
import 'dart:async'; // 🚀 Required for network timeouts
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

// 🚀 ARCHITECTURE PACKAGES
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

import 'package:agriyukt_app/features/farmer/farmer_translations.dart';
import 'package:agriyukt_app/core/providers/language_provider.dart';
import 'package:agriyukt_app/core/services/translation_service.dart';

extension StringCasingExtension on String {
  String toCapitalized() =>
      length > 0 ? '${this[0].toUpperCase()}${substring(1).toLowerCase()}' : '';
  String toTitleCase() => replaceAll(RegExp(' +'), ' ')
      .split(' ')
      .map((str) => str.toCapitalized())
      .join(' ');
}

class EditCropScreen extends StatefulWidget {
  final Map<String, dynamic> cropData;

  const EditCropScreen({super.key, required this.cropData});

  @override
  State<EditCropScreen> createState() => _EditCropScreenState();
}

class _EditCropScreenState extends State<EditCropScreen> {
  int _currentStep = 0;
  bool _isLoading = false;
  bool _isDirty = false;
  bool _isScanningAI = false;
  bool _canPop = false; // 🚀 Modern PopScope protection

  final Color _primaryGreen = const Color(0xFF1B5E20);
  final Color _surfaceColor = const Color(0xFFF4F6F8);
  final Color _inputFillColor = const Color(0xFFFFFFFF);

  Map<String, dynamic>? _aiPrediction;
  bool _isFetchingAI = false;

  // ----------------------------------------------------------------------
  // 🇮🇳 THE ULTIMATE ICAR HYBRID DATASET
  // ----------------------------------------------------------------------
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
    // VEGETABLES
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
    "Sweet Potato": [
      "Sree Kanaka",
      "Pusa Safed",
      "Sree Arun",
      "Bhu Krishna",
      "Bhu Sona",
      "Bhu Jiv"
    ],
    "Cauliflower": [
      "Pusa Sharad",
      "Pusa Snowball",
      "Kashi Kunwari",
      "Pusa Katki",
      "Pusa Himjyoti",
      "Kashi Gobhi-25",
      "Ooty-1",
      "Pusa Early Synthetic",
      "Early Kunwari"
    ],
    "Cabbage": [
      "Golden Acre",
      "Pusa Drumhead",
      "Pride of India",
      "Pusa Mukta",
      "K-1",
      "Arka Samraj",
      "Red Cabbage",
      "Pusa Cabbage-1"
    ],
    "Broccoli": [
      "Pusa KTS-1",
      "Palampura Samridhi",
      "Green Magic",
      "Pusa Broccoli-1"
    ],
    "Okra": [
      "Pusa Sawani",
      "Arka Anamika",
      "Parbhani Kranti",
      "Pusa Nayantara",
      "Varsha Uphar",
      "Kashi Pragati",
      "Kashi Lalima (Red)",
      "Arka Abhay",
      "Local Desi"
    ],
    "Bitter Gourd": [
      "Pusa Hybrid-1",
      "Arka Harit",
      "Pusa Do Mausmi",
      "Priya",
      "Kashi Mayuri",
      "Konkan Tara",
      "Arka Shweta",
      "Preethi"
    ],
    "Bottle Gourd": [
      "Pusa Naveen",
      "Arka Bahar",
      "Kashi Ganga",
      "Pusa Sandesh",
      "Pusa Meghdoot",
      "Kashi Kirti",
      "Arka Shreyas"
    ],
    "Snake Gourd": [
      "CO-1",
      "CO-2",
      "PKM-1",
      "Kashi Shweta",
      "Arka Snehitha",
      "MDU-1"
    ],
    "Ridge Gourd": [
      "Arka Sumeet",
      "Arka Prasan",
      "Pusa Nasdar",
      "Pusa Supriya",
      "Kashi Shivani",
      "Arka Sujata",
      "CO-1"
    ],
    "Ivy Gourd": [
      "Arka Neelachal Sabuja",
      "Kashi Kundru",
      "Sulabha",
      "Indira Kundru-5"
    ],
    "Pumpkin": [
      "Arka Suryamukhi",
      "Pusa Vishwas",
      "Ambili",
      "Kashi Harit",
      "Arka Chandan",
      "CO-2"
    ],
    "Cucumber": [
      "Pusa Barkha",
      "Arka Sheetal",
      "Japanese Long Green",
      "Pant Khira-1",
      "Poinsette",
      "Gherkin",
      "Kashi Imli"
    ],
    "Peas": [
      "Arka Ajit",
      "Pusa Pragati",
      "Bonneville",
      "Azad P-1",
      "Kashi Nandini",
      "Arka Apoorva",
      "Pusa Shree"
    ],
    "French Bean": [
      "Arka Komal",
      "Pusa Parvati",
      "Arka Suvidha",
      "Pant Anupama",
      "Arka Arjun",
      "Lakshmi"
    ],
    "Cluster Bean": [
      "Pusa Sadabahar",
      "Pusa Navbahar",
      "HG-365",
      "MDU-1",
      "Pusa Mousmi"
    ],
    "Drumstick": [
      "PKM-1",
      "PKM-2",
      "Bhagya (KDM-1)",
      "ODC-3",
      "Rohit-1",
      "Pusa Kanak"
    ],
    "Radish": [
      "Pusa Chetki",
      "Japanese White",
      "Pusa Reshmi",
      "Arka Nishant",
      "Pusa Himani",
      "Kashi Hans"
    ],
    "Carrot": [
      "Pusa Rudhira",
      "Pusa Nayanjyoti",
      "Nantes",
      "Pusa Kesar",
      "Pusa Yamdagni",
      "Arka Suraj",
      "Pusa Asita (Black)"
    ],
    "Spinach": [
      "Pusa Bharati",
      "All Green",
      "Pusa Jyoti",
      "Arka Anupama",
      "Pusa Harit"
    ],
    "Fenugreek": [
      "Pusa Early Bunching",
      "Kasuri Methi",
      "Pusa Kasuri",
      "Lam Selection-1",
      "AFG-3"
    ],
    "Elephant Foot Yam": ["Gajendra", "Sree Padma", "Kusum", "Sree Athira"],
    "Colocasia": [
      "Pusa Panchali",
      "Arka Anamika",
      "Muktakeshi",
      "Panchmukhi",
      "Sree Rashmi"
    ],
    "Capsicum": [
      "Indra",
      "Bomby",
      "Orobelle",
      "Arka Mohini",
      "California Wonder",
      "Arka Gaurav"
    ],
    "Ash Gourd": ["Pusa Ujwal", "Kashi Dhawal", "CO-1", "Pusa Sabzimandi"],
    "Pointed Gourd": [
      "Kashi Alankar",
      "Swarna Alaukik",
      "Rajendra Parwal",
      "FP-1"
    ],
    "Teasel Gourd": ["Arka Bharath", "Indira Kankoda-1", "Ambika-12"],
    "Amaranthus": [
      "CO-1",
      "CO-2",
      "CO-3",
      "Arka Suguna",
      "Arka Varna",
      "Pusa Kiran"
    ],
    "Knol Khol": ["Early White Vienna", "Purple Vienna", "Pusa Virat"],

    // FRUITS
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
    "Guava": [
      "Allahabad Safeda",
      "Lucknow-49",
      "Arka Mridula",
      "Lalit",
      "Shweta",
      "Arka Poorna",
      "VNR Bihi",
      "Arka Kiran"
    ],
    "Papaya": [
      "Pusa Nanha",
      "Co-7",
      "Arka Prabhath",
      "Red Lady 786",
      "Pusa Dwarf",
      "Surya",
      "Co-8",
      "Arka Prabhat",
      "Washington"
    ],
    "Pomegranate": [
      "Bhagwa",
      "Mridula",
      "Phule Arakta",
      "Ganesh",
      "Kandhari",
      "Super Bhagwa",
      "Jyoti",
      "Arakta",
      "Ruby"
    ],
    "Grapes": [
      "Thompson Seedless",
      "Bangalore Blue",
      "Sonaka",
      "Sharad Seedless",
      "Tas-A-Ganesh",
      "Manjari Medika",
      "Red Globe",
      "Dilkhush",
      "Flame Seedless",
      "Manik Chaman"
    ],
    "Lemon": [
      "Pramalini",
      "Vikram",
      "Sai Sharbati",
      "Kagzi Lime",
      "Balaji",
      "Gondhoraj",
      "Jai Devi"
    ],
    "Orange": [
      "Nagpur Santra",
      "Coorg Mandarin",
      "Kinnow",
      "Darjeeling Orange",
      "Mudkhed Seedless"
    ],
    "Sweet Lime": [
      "Katol Gold",
      "Sathgudi",
      "Phule Mosambi",
      "Nucellar Mosambi"
    ],
    "Apple": [
      "Ambri",
      "Red Delicious",
      "Golden Delicious",
      "Anna",
      "Granny Smith",
      "HRMN-99",
      "Dorsett Golden",
      "Royal Gala",
      "Fuji",
      "Kashmiri"
    ],
    "Jackfruit": [
      "Swarna Haldi",
      "Palur-1",
      "Konkan Prolific",
      "Siddu",
      "Muttom Varikka",
      "Tubigere",
      "Lalbagh Madhura"
    ],
    "Sapota": [
      "Kalipatti",
      "Cricket Ball",
      "DHS-1",
      "DHS-2",
      "PKM-1",
      "Pala",
      "CO-2"
    ],
    "Watermelon": [
      "Arka Muthu",
      "Sugar Baby",
      "Pusa Bedana",
      "Arka Manik",
      "Kiran",
      "Durgapura Kesar"
    ],
    "Muskmelon": [
      "Pusa Sharbati",
      "Arka Jeet",
      "Hara Madhu",
      "Arka Rajhans",
      "Kajal",
      "Pusa Maduras"
    ],
    "Pineapple": ["Giant Kew", "Queen", "Mauritius", "Jaldhup", "Amrutha"],
    "Custard Apple": [
      "Balanagar",
      "Arka Sahan",
      "Arka Neelanchal Vikram",
      "Mammoth",
      "Washington"
    ],
    "Litchi": [
      "Shahi",
      "China",
      "Bedana",
      "Dehradun",
      "Swarna Roopa",
      "Rose Scented"
    ],
    "Dragon Fruit": ["Kamalam Pink", "Kamalam White", "Kamalam Yellow"],
    "Strawberry": [
      "Chandler",
      "Tioga",
      "Sweet Charlie",
      "Winter Dawn",
      "Camarosa"
    ],
    "Jamun": [
      "Konkan Bahadoli",
      "Pusa Jamun",
      "CISH-J-42",
      "Goma Priyanka",
      "Narendra Jamun-6"
    ],
    "Amla": ["Banarasi", "Francis", "NA-7", "Kanchan", "Krishna", "Chakaiya"],
    "Coconut": [
      "West Coast Tall",
      "East Coast Tall",
      "Chowghat Orange Dwarf",
      "Kalpa Suvarna",
      "Kalpa Raksha"
    ],
    "Avocado": ["Hass", "Fuerte", "Pinkerton", "Arka Shankar", "Pollock"],
    "Pummelo": ["Arka Anantha", "Arka Chandra", "Devenahalli"],
    "Ber": ["Gola", "Umran", "Banarasi Karaka", "Apple Ber", "Seb"],
    "Pear": ["Patharnakh", "Gola", "Pusa Gulabi", "Bagugosha", "Nijisseiki"],
    "Peach": ["Prabhat", "Partap", "Shan-e-Punjab", "Florida Prince"],
    "Cashew": [
      "Vengurla-4",
      "Vengurla-7",
      "Ullal-4",
      "Madakkathara-2",
      "Priyanka"
    ],
    "Areca Nut": [
      "Mangala",
      "Sumangala",
      "Sreemangala",
      "Mohitnagar",
      "Vittal-11"
    ],
    "Bael": ["Narendra Bael-5", "Narendra Bael-9", "CISH B-1", "Pant Shivani"],
    "Wood Apple": ["Local Selections", "Goma Yashi"],
    "Phalsa": ["Sharbati", "Tall", "Dwarf"],
    "Karonda": ["Pant Manohar", "Pant Suvarna", "Konkan Bold"],
    "Kokum": ["Konkan Amrita", "Konkan Hasti"],
    "Fig": ["Poona Fig", "Deanna", "Conadria"],
    "Rambutan": ["Arka Coorg Arun", "Home Selection"],

    // GRAINS & CEREALS
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
    "Maize": [
      "Pusa Vivek QPM-9",
      "HQPM-1",
      "African Tall",
      "Deccan-103",
      "Prabhat",
      "Ganga-11",
      "Sweet Corn (Madhuri)"
    ],
    "Jowar": [
      "M-35-1 (Maldandi)",
      "CSH-16",
      "Phule Vasudha",
      "Parbhani Moti",
      "CSV-216R"
    ],
    "Bajra": ["Pusa-444", "ICTP-8203", "HHB-67", "Nandi-32", "Dhani"],
    "Ragi": ["GPU-28", "Indaf-5", "ML-365", "Arka Falguni", "VL-352"],
    "Barley": ["RD-2035", "Jyoti", "Pusa Losar", "Azad", "DWRB-137"],
    "Little Millet": ["JK-8", "OLM-203", "Phule Ekadashi"],
    "Foxtail Millet": ["SIA-3088", "Prasad", "HMT-100"],
    "Buckwheat": ["VL-7", "Himpriya", "PRB-1"],
    "Cotton": ["BT Cotton", "Desi Cotton", "MCU-5", "DCH-32"],

    // SPICES & PLANTATION
    "Turmeric": [
      "Pratibha",
      "Kedaram",
      "Alleppey Supreme",
      "Erode Local",
      "Salem",
      "IISR Pragati",
      "IISR Prabha",
      "Rajapuri"
    ],
    "Ginger": [
      "IISR Varada",
      "IISR Rejatha",
      "Mahim",
      "Maran",
      "Rio-de-Janeiro",
      "IISR Mahima",
      "Suprabha",
      "Suruchi",
      "Surabhi",
      "Local"
    ],
    "Black Pepper": [
      "Panniyur-1",
      "Panniyur-3",
      "Panniyur-5",
      "Sreekara",
      "Subhakara",
      "IISR Thevam"
    ],
    "Cardamom": [
      "Appangala-1",
      "IISR Avinash",
      "IISR Vijetha",
      "ICRI-5",
      "Sikkim Local",
      "Golsey",
      "Ramsey",
      "Sawney"
    ],
    "Cinnamon": ["IISR Navashree", "IISR Nithyashree"],
    "Nutmeg": ["IISR Viswashree", "IISR Keralashree", "Konkan Swad"],
    "Clove": ["Local Selections", "Amrut"],
    "Saffron": ["Pampore Local"],
    "Coffee": ["S.795 (Arabica)", "Cauvery", "Sln.274 (Robusta)", "CxR"],
    "Tea": ["TV-1 to TV-31 (Tocklai Releases)", "UPASI-2 to UPASI-28"],
    "Rubber": ["RRII 105", "RRII 414", "RRII 430"],

    // MEDICINAL & AROMATIC
    "Ashwagandha": ["Jawahar Asgand-20", "Pusa Asgand-1", "WS-20"],
    "Aloe Vera": ["AL-1", "IC111271", "Desert Aloe"],
    "Lemongrass": ["OD-19", "Krishna", "Cauvery", "Nima"],
    "Menthol Mint": ["Kosi", "Himalaya", "Saksham", "Kushal"],
    "Tulsi": ["Krishna Tulsi", "Rama Tulsi", "CIM-Ayu", "CIM-Soumya"],
    "Isabgol": ["Gujarat Isabgol-1", "Gujarat Isabgol-2", "Jawahar Isabgol-4"],
    "Vetiver": ["KS-1", "Sugandha", "Dharini"]
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
    _prefillData();
    _qtyCtrl.addListener(() => setState(() {}));
    _priceCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _cropNameCtrl.dispose();
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  String _text(String key) => FarmerText.get(context, key);

  String _safeString(dynamic value, [String fallback = '']) {
    if (value == null) return fallback;
    return value.toString().trim();
  }

  void _markDirty() {
    if (!_isDirty) setState(() => _isDirty = true);
  }

  void _showError(String msg) {
    HapticFeedback.heavyImpact();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            Text(msg, style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating));
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
          List<String> apiResults = records
              .map((e) => e['attributes']['name'].toString().toTitleCase())
              .toList();
          combinedResults.addAll(apiResults);
        }
      } catch (e) {
        debugPrint("OpenFarm API Error: $e");
      }
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
      if (mounted)
        setState(() {
          _aiPrediction = response;
          _isFetchingAI = false;
        });
    } catch (e) {
      if (mounted) setState(() => _isFetchingAI = false);
    }
  }

  void _prefillData() {
    final c = widget.cropData;

    String dbStatus = _safeString(c['status'], 'Active');
    if (dbStatus.isNotEmpty) {
      dbStatus =
          dbStatus[0].toUpperCase() + dbStatus.substring(1).toLowerCase();
    }
    _status = _statusOptions.contains(dbStatus) ? dbStatus : 'Active';

    String dbCategory = _safeString(c['category']);
    _selectedCategory = _masterCategories.contains(dbCategory)
        ? dbCategory
        : _masterCategories.first;

    _cropNameCtrl.text =
        _safeString(c['crop_name'], _safeString(c['name'])).toTitleCase();

    _selectedVariety = _safeString(c['variety']).toTitleCase();
    if (_selectedVariety!.isEmpty) _selectedVariety = null;

    _selectedGrade = _gradeOptions.contains(c['grade']) ? c['grade'] : null;

    _cropType = _safeString(c['crop_type'], "Organic");
    if (!["Organic", "Inorganic"].contains(_cropType)) _cropType = "Organic";

    // 🚀 Robust parsing logic matches latest standard
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

    if (_cropNameCtrl.text.isNotEmpty) {
      _fetchAIPredictedPrice(_cropNameCtrl.text);
    }
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
              toolbarColor: _primaryGreen,
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
      setState(() => _selectedImage = finalImage);

      if (isSmartScan) await _analyzeImageWithAI(finalImage);
    } catch (e) {
      debugPrint("Image Error: $e");
      if (mounted) _showError("Error processing image.");
    }
  }

  Future<void> _analyzeImageWithAI(File imageFile) async {
    setState(() => _isScanningAI = true);

    try {
      const apiKey = 'AIzaSyB5dYG5TJ4xKHWJjHGZs_HPJc7xu0UZw2Q';
      final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: apiKey);
      final imageBytes = await imageFile.readAsBytes();

      final prompt = TextPart('''
        Analyze this agricultural crop/flower image. 
        Respond ONLY with a valid, raw JSON object. Do not include markdown formatting.
        Format strictly like this:
        {
          "category": "Vegetables",
          "crop_name": "Tomato",
          "variety": "Hybrid Tomato",
          "grade": "Grade A (Premium)",
          "estimated_weight_kg": "10",
          "days_until_harvest": "0",
          "short_note": "Fresh, bright red tomatoes with excellent firmness."
        }
        Instructions:
        - "category": Map to one of: Vegetables, Fruits, Grains & Cereals, Spices & Plantation, Medicinal & Aromatic, Flowers, Pulses.
        - "estimated_weight_kg": Estimate weight shown in kg (only number).
        - "days_until_harvest": 0 if ready today, else estimated days.
        - "short_note": 1-to-2 sentence catchy marketing description.
        If not a crop/flower, return empty strings.
      ''');

      final response = await model.generateContent([
        Content.multi([prompt, DataPart('image/jpeg', imageBytes)])
      ]);
      String responseText = response.text ?? '{}';

      final match = RegExp(r'\{[\s\S]*\}').firstMatch(responseText);
      if (match != null) responseText = match.group(0)!;
      final data = jsonDecode(responseText);

      if (mounted) {
        setState(() {
          if (data['category'] != null &&
              data['category'].toString().isNotEmpty)
            _selectedCategory = data['category'].toString().toTitleCase();
          if (data['grade'] != null && data['grade'].toString().isNotEmpty)
            _selectedGrade = data['grade'];

          if (data['crop_name'] != null &&
              data['crop_name'].toString().isNotEmpty) {
            _cropNameCtrl.text = data['crop_name'].toString().toTitleCase();
          }
          if (data['variety'] != null &&
              data['variety'].toString().isNotEmpty) {
            _selectedVariety = data['variety'].toString().toTitleCase();
          }

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
              data['short_note'].toString().isNotEmpty)
            _notesCtrl.text = data['short_note'].toString();
        });

        if (_cropNameCtrl.text.isNotEmpty)
          _fetchAIPredictedPrice(_cropNameCtrl.text);

        HapticFeedback.mediumImpact();

        if (_cropNameCtrl.text.isEmpty) {
          _showError("Hmm, AI couldn't detect a crop in this photo.");
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text("🤖 AI detected: ${_cropNameCtrl.text}!",
                  style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
              backgroundColor: Colors.green.shade700,
              behavior: SnackBarBehavior.floating));
        }
      }
    } catch (e) {
      debugPrint("🚨 AI ERROR: $e");
      if (mounted) _showError("AI Error: ${e.toString()}");
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
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
                isSmartScan
                    ? "Smart Crop Detection 🤖"
                    : _text('upload_crop_photo'),
                style: GoogleFonts.poppins(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _pickerOption(Icons.camera_alt, "Camera", ImageSource.camera,
                    isSmartScan: isSmartScan),
                _pickerOption(
                    Icons.photo_library, "Gallery", ImageSource.gallery,
                    isSmartScan: isSmartScan),
              ],
            ),
            const SizedBox(height: 10),
          ],
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
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 110,
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.green.shade100)),
        child: Column(children: [
          Icon(icon, size: 36, color: _primaryGreen),
          const SizedBox(height: 8),
          Text(label,
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: _primaryGreen))
        ]),
      ),
    );
  }

  void _handleStepContinue() {
    FocusScope.of(context).unfocus();

    if (_currentStep == 0) {
      if (_selectedCategory == null)
        return _showError("⚠️ Please select a Category.");
      if (_cropNameCtrl.text.isEmpty)
        return _showError("⚠️ Please enter a Crop Name.");

      final String cleanQty = _qtyCtrl.text.replaceAll(',', '').trim();
      final String cleanPrice = _priceCtrl.text.replaceAll(',', '').trim();

      if (cleanQty.isEmpty || double.tryParse(cleanQty) == null)
        return _showError("⚠️ Please enter a valid Quantity.");
      if (cleanPrice.isEmpty || double.tryParse(cleanPrice) == null)
        return _showError("⚠️ Please enter a valid Price.");
    }

    if (_currentStep < 1)
      setState(() => _currentStep++);
    else
      _updateCrop();
  }

  // 🚀 UPDATE ENGINE WITH SMART PGRST204 FALLBACK
  Future<void> _updateCrop() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw "Authentication error. Please log in again.";

      String? imageUrl = _existingImageUrl;

      if (_selectedImage != null) {
        final ext = _selectedImage!.path.split('.').last.toLowerCase();
        final safeExt =
            ['jpg', 'jpeg', 'png', 'webp'].contains(ext) ? ext : 'jpg';
        final fileName =
            'crops/${DateTime.now().millisecondsSinceEpoch}_${user.id}.$safeExt';

        await Supabase.instance.client.storage
            .from('crop_images')
            .uploadBinary(fileName, await _selectedImage!.readAsBytes(),
                fileOptions:
                    FileOptions(upsert: true, contentType: 'image/$safeExt'))
            .timeout(const Duration(seconds: 30),
                onTimeout: () =>
                    throw "Image upload timed out. Check your internet.");

        imageUrl = Supabase.instance.client.storage
            .from('crop_images')
            .getPublicUrl(fileName);
      }

      // 🚀 SAFE MATH & COMMA REPLACEMENT
      double qtyVal =
          double.tryParse(_qtyCtrl.text.replaceAll(',', '').trim()) ?? 0;
      double parsedPrice =
          double.tryParse(_priceCtrl.text.replaceAll(',', '').trim()) ?? 0.0;
      double finalKg = qtyVal;

      if (_selectedUnit == 'Quintal (q)') {
        finalKg = qtyVal * 100;
      } else if (_selectedUnit == 'Ton') {
        finalKg = qtyVal * 1000;
      }

      // 🚀 Smart Translation Logic
      String englishNotes = _notesCtrl.text.trim();
      try {
        if (englishNotes.isNotEmpty) {
          englishNotes = await TranslationService.toEnglish(englishNotes);
        }
      } catch (_) {}

      final Map<String, dynamic> cropData = {
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
        'updated_at': DateTime.now().toIso8601String(),
      };

      // 🛡️ DYNAMIC COLUMN INJECTION: ONLY IF THE DB HAS IT
      if (widget.cropData.containsKey('quantity_kg')) {
        cropData['quantity_kg'] = finalKg;
      }
      if (widget.cropData.containsKey('price_per_qty')) {
        cropData['price_per_qty'] = parsedPrice;
      }

      try {
        await Supabase.instance.client
            .from('crops')
            .update(cropData)
            .eq('id', widget.cropData['id'])
            .timeout(const Duration(seconds: 15),
                onTimeout: () => throw "Database update timed out.");
      } catch (dbError) {
        // 🛡️ THE PGRST204 FALLBACK ENGINE
        if (dbError.toString().contains('PGRST204') ||
            dbError.toString().contains('Could not find the')) {
          debugPrint(
              "🔄 PGRST204 Triggered! Falling back to old database schema...");
          cropData.remove('quantity_kg');
          cropData.remove('price_per_qty');

          await Supabase.instance.client
              .from('crops')
              .update(cropData)
              .eq('id', widget.cropData['id']);
        } else {
          rethrow;
        }
      }

      if (mounted) {
        HapticFeedback.mediumImpact();
        _markDirty();
        setState(() {
          _isDirty = false;
          _canPop = true;
        });

        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("✅ Crop Updated Successfully!",
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating));
      }
    } catch (e) {
      if (mounted) {
        String err = e.toString();
        if (err.contains("message:"))
          err = err.split("message:")[1].split(",")[0];
        _showError("Failed to update: $err");
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Provider.of<LanguageProvider>(context);

    final String titleCropName = _cropNameCtrl.text.isNotEmpty
        ? _cropNameCtrl.text
        : _safeString(widget.cropData['crop_name'], 'Crop');

    return PopScope(
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
            title: Text("Discard Changes?",
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
            content: Text(
                "You have unsaved crop data. Are you sure you want to go back?",
                style: GoogleFonts.poppins(fontSize: 14)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text("KEEP EDITING",
                      style: GoogleFonts.poppins(
                          color: _primaryGreen, fontWeight: FontWeight.bold))),
              ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade600, elevation: 0),
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
          appBar: AppBar(
            title: Text("Edit: $titleCropName",
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600, fontSize: 18)),
            backgroundColor: _primaryGreen,
            foregroundColor: Colors.white,
            elevation: 0,
            centerTitle: true,
          ),
          body: Stack(
            children: [
              Theme(
                data: ThemeData(
                    colorScheme: ColorScheme.light(primary: _primaryGreen),
                    canvasColor: Colors.white),
                child: Stepper(
                  type: StepperType.horizontal,
                  currentStep: _currentStep,
                  elevation: 0,
                  margin: EdgeInsets.zero,
                  controlsBuilder: (context, details) => _buildButtons(details),
                  onStepContinue: _handleStepContinue,
                  onStepCancel: () =>
                      _currentStep > 0 ? setState(() => _currentStep--) : null,
                  steps: _getSteps(),
                ),
              ),
              if (_isLoading) _buildFullScreenLoader("Updating Crop..."),
              if (_isScanningAI)
                _buildFullScreenLoader("🤖 AI Analyzing Image..."),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFullScreenLoader(String message) {
    return Container(
        color: Colors.black.withOpacity(0.3),
        child: Center(
            child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.1), blurRadius: 10)
                    ]),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  CircularProgressIndicator(color: _primaryGreen),
                  const SizedBox(height: 16),
                  Text(message,
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600, color: _primaryGreen))
                ]))));
  }

  Widget _buildButtons(ControlsDetails details) {
    return Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 20),
        child: Row(children: [
          Expanded(
              flex: 2,
              child: ElevatedButton(
                  onPressed: details.onStepContinue,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryGreen,
                      elevation: 2,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                  child: Text(_currentStep == 1 ? "UPDATE CROP" : "CONTINUE",
                      style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          letterSpacing: 0.5)))),
          if (_currentStep > 0) ...[
            const SizedBox(width: 12),
            Expanded(
                child: OutlinedButton(
                    onPressed: details.onStepCancel,
                    style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side:
                            BorderSide(color: Colors.grey.shade400, width: 1.5),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                    child: Text(_text('back'),
                        style: GoogleFonts.poppins(
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5)))),
          ]
        ]));
  }

  Widget _buildAIPricingGuide() {
    if (_isFetchingAI)
      return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(children: [
            const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.green)),
            const SizedBox(width: 10),
            Text("Analyzing market data...",
                style: GoogleFonts.poppins(color: Colors.grey, fontSize: 12))
          ]));
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
        isUpward ? Colors.greenAccent : Colors.orangeAccent;
    final IconData trendIcon =
        isUpward ? Icons.trending_up : Icons.trending_down;

    return Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 10,
                  offset: const Offset(0, 4))
            ]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.auto_awesome, color: Colors.amberAccent, size: 18),
            const SizedBox(width: 8),
            Text("AI Pricing Guide",
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 14))
          ]),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("Current Mandi Avg",
                  style: GoogleFonts.poppins(
                      fontSize: 11, color: Colors.grey.shade400)),
              Text("₹${liveAvg.toStringAsFixed(1)}",
                  style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white))
            ]),
            Container(width: 1, height: 30, color: Colors.grey.shade700),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text("Tomorrow's Prediction",
                  style: GoogleFonts.poppins(
                      fontSize: 11, color: Colors.grey.shade400)),
              Row(children: [
                Icon(trendIcon, color: trendColor, size: 16),
                const SizedBox(width: 4),
                Text("₹${predicted.toStringAsFixed(1)}",
                    style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: trendColor))
              ])
            ])
          ]),
          const SizedBox(height: 12),
          Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                Icon(Icons.lightbulb_outline,
                    color: Colors.amber.shade200, size: 16),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(
                        isUpward
                            ? "Prices are rising by ${trend.toStringAsFixed(1)}%. You can set a slightly higher asking price."
                            : "Prices are dropping by ${trend.toStringAsFixed(1)}%. Set a competitive price to sell quickly.",
                        style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey.shade200)))
              ]))
        ]));
  }

  List<Step> _getSteps() {
    return [
      // ---------------------------------------------------------
      // STEP 1: INFO & RATE
      // ---------------------------------------------------------
      Step(
          title: FittedBox(
              child: Text("Info & Rate",
                  style: GoogleFonts.poppins(
                      fontSize: 11, fontWeight: FontWeight.w600))),
          isActive: _currentStep >= 0,
          state: _currentStep > 0 ? StepState.complete : StepState.indexed,
          content:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // 🚀 SMART AUTO-FILL FOR EDIT
            InkWell(
              onTap: () => _showImagePickerOptions(isSmartScan: true),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                decoration: BoxDecoration(
                    gradient: LinearGradient(
                        colors: [Colors.green.shade50, Colors.teal.shade50],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight),
                    border:
                        Border.all(color: Colors.green.shade300, width: 1.5),
                    borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                                color: Colors.green.shade100, blurRadius: 6)
                          ]),
                      child: const Icon(Icons.document_scanner,
                          color: Colors.teal, size: 28)),
                  const SizedBox(width: 14),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text("Smart Auto-Fill 🤖",
                            style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.teal.shade800)),
                        const SizedBox(height: 4),
                        Text("Take a new photo, AI updates details!",
                            style: GoogleFonts.poppins(
                                fontSize: 12, color: Colors.teal.shade700))
                      ])),
                  const Icon(Icons.arrow_forward_ios,
                      color: Colors.teal, size: 18)
                ]),
              ),
            ),
            const SizedBox(height: 16),

            _sectionLabel("Listing Status", Icons.toggle_on),
            Container(
                margin: const EdgeInsets.only(bottom: 20, top: 10),
                decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.shade200)),
                child: _dropdown(null, _status, _statusOptions, (v) {
                  _markDirty();
                  setState(() => _status = v!);
                }, icon: Icons.storefront)),

            _sectionLabel("Farming Method", Icons.eco),
            const SizedBox(height: 10),
            Row(children: [
              _typeButton("Organic", Colors.green.shade600, Icons.grass),
              const SizedBox(width: 12),
              _typeButton("Inorganic", Colors.blueGrey.shade500, Icons.science),
            ]),
            const SizedBox(height: 24),
            _sectionLabel("Crop Details", Icons.category),
            const SizedBox(height: 10),

            _buildDropdown2(
                "${_text('category')} *", _selectedCategory, _masterCategories,
                (val) {
              _markDirty();
              setState(() {
                _selectedCategory = val;
                _cropNameCtrl.clear();
                _selectedVariety = null;
                _aiPrediction = null;
              });
            }, icon: Icons.grid_view),
            const SizedBox(height: 16),

            TypeAheadField<String>(
              controller: _cropNameCtrl,
              builder: (context, controller, focusNode) {
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  onChanged: (_) => _markDirty(),
                  scrollPadding: const EdgeInsets.only(bottom: 350),
                  style: GoogleFonts.poppins(fontSize: 14),
                  decoration: InputDecoration(
                    labelText: "Crop Name (Search) *",
                    labelStyle: GoogleFonts.poppins(
                        color: Colors.grey.shade600, fontSize: 14),
                    prefixIcon: Icon(Icons.local_florist,
                        color: Colors.grey.shade500, size: 20),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    suffixIcon: const Icon(Icons.arrow_drop_down,
                        color: Colors.green, size: 24),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: _primaryGreen, width: 2)),
                    filled: true,
                    fillColor: _inputFillColor,
                  ),
                );
              },
              suggestionsCallback: (pattern) async =>
                  await _searchCropsFromAPI(pattern),
              itemBuilder: (context, String suggestion) {
                return ListTile(
                  title: Text(suggestion,
                      style: GoogleFonts.poppins(fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  dense: true,
                );
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
                padding: const EdgeInsets.all(12.0),
                child: Text("Type crop manually if not found.",
                    style:
                        GoogleFonts.poppins(color: Colors.grey, fontSize: 13)),
              ),
            ),
            const SizedBox(height: 16),

            // 🚀 INJECTED AI PRICING WIDGET IN STEP 1
            _buildAIPricingGuide(),

            Builder(
              builder: (context) {
                List<String> varieties =
                    _indianVarieties[_cropNameCtrl.text.toTitleCase()] ??
                        ["Local / Desi", "Hybrid", "Other"];
                if (_selectedVariety != null &&
                    !varieties.contains(_selectedVariety)) {
                  varieties.insert(0, _selectedVariety!);
                }
                return _buildDropdown2(
                    "Variety (Optional)", _selectedVariety, varieties, (val) {
                  _markDirty();
                  setState(() => _selectedVariety = val);
                }, icon: Icons.style);
              },
            ),
            const SizedBox(height: 16),
            _buildDropdown2("Quality Grade", _selectedGrade, _gradeOptions,
                (v) {
              _markDirty();
              setState(() => _selectedGrade = v);
            }, icon: Icons.workspace_premium),

            const SizedBox(height: 24),
            _sectionLabel("Inventory Stock", Icons.inventory_2),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                  flex: 2,
                  child: _inputField("Quantity *", _qtyCtrl,
                      type:
                          const TextInputType.numberWithOptions(decimal: true),
                      icon: Icons.scale)),
              const SizedBox(width: 12),
              Expanded(
                  flex: 1,
                  child: _dropdown("Unit", _selectedUnit, _unitOptions, (v) {
                    _markDirty();
                    setState(() => _selectedUnit = v);
                  })),
            ]),
            const SizedBox(height: 24),

            _sectionLabel("Pricing", Icons.payments),
            const SizedBox(height: 10),
            _inputField("Price per Unit (₹) *", _priceCtrl,
                type: const TextInputType.numberWithOptions(decimal: true),
                prefix: "₹ ",
                icon: Icons.sell),
            const SizedBox(height: 20),

            // 🛡️ PRODUCTION FIX: Safe Math + Premium Summary Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  gradient: LinearGradient(
                      colors: [Colors.green.shade50, Colors.green.shade100]),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.green.shade300)),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 4)
                        ]),
                    child: Icon(Icons.account_balance_wallet,
                        color: Colors.green.shade700, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Estimated Total Value",
                            style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: Colors.green.shade800,
                                fontWeight: FontWeight.w600)),
                        Text(
                          "₹${((double.tryParse(_qtyCtrl.text.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0) * (double.tryParse(_priceCtrl.text.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0)).toStringAsFixed(0)}",
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold,
                              color: _primaryGreen,
                              fontSize: 22),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          ])),

      // ---------------------------------------------------------
      // STEP 2: PHOTO & DATES
      // ---------------------------------------------------------
      Step(
          title: FittedBox(
              child: Text("Details & Photo",
                  style: GoogleFonts.poppins(
                      fontSize: 11, fontWeight: FontWeight.w600))),
          isActive: _currentStep >= 1,
          content:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _sectionLabel("Timelines", Icons.calendar_month),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                  child: _datePicker("Harvested", _harvestDate, (d) {
                _markDirty();
                setState(() => _harvestDate = d);
              }, isHarvest: true)),
              const SizedBox(width: 12),
              Expanded(
                  child: _datePicker("Available", _availableDate, (d) {
                _markDirty();
                setState(() => _availableDate = d);
              }, isHarvest: false)),
            ]),
            const SizedBox(height: 24),

            _sectionLabel("Description", Icons.description),
            const SizedBox(height: 10),
            _inputField("Add extra details (Optional)", _notesCtrl,
                type: TextInputType.multiline, maxLines: 3),
            const SizedBox(height: 24),

            _sectionLabel("Crop Photo *", Icons.image),
            const SizedBox(height: 10),

            // 🎨 Premium Interactive Dropzone
            InkWell(
              onTap: () => _showImagePickerOptions(isSmartScan: false),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                  height: 200,
                  width: double.infinity,
                  decoration: BoxDecoration(
                      color: _inputFillColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: _selectedImage != null ||
                                  _existingImageUrl != null
                              ? _primaryGreen
                              : Colors.grey.shade400,
                          width: 2,
                          style: BorderStyle.solid)),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (_selectedImage != null)
                        ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.file(_selectedImage!,
                                width: double.infinity,
                                height: double.infinity,
                                fit: BoxFit.cover))
                      else if (_existingImageUrl != null)
                        ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: _existingImageUrl!.startsWith('http')
                                ? Image.network(_existingImageUrl!,
                                    width: double.infinity,
                                    height: double.infinity,
                                    fit: BoxFit.cover)
                                : Image.network(
                                    Supabase.instance.client.storage
                                        .from('crop_images')
                                        .getPublicUrl(_existingImageUrl!),
                                    width: double.infinity,
                                    height: double.infinity,
                                    fit: BoxFit.cover,
                                    errorBuilder: (c, e, s) => Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.broken_image,
                                                size: 40,
                                                color: Colors.grey.shade400),
                                            Text("Image Unavailable",
                                                style: GoogleFonts.poppins(
                                                    color: Colors.grey)),
                                          ],
                                        )))
                      else
                        Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    shape: BoxShape.circle),
                                child: Icon(Icons.cloud_upload_outlined,
                                    size: 36, color: _primaryGreen),
                              ),
                              const SizedBox(height: 12),
                              Text("Tap to upload photo",
                                  style: GoogleFonts.poppins(
                                      color: Colors.grey.shade700,
                                      fontWeight: FontWeight.w600)),
                              Text("JPG or PNG (Max 5MB)",
                                  style: GoogleFonts.poppins(
                                      color: Colors.grey.shade500,
                                      fontSize: 11)),
                            ]),
                      if (_selectedImage != null || _existingImageUrl != null)
                        Positioned(
                            bottom: 12,
                            right: 12,
                            child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                    color: Colors.black87,
                                    borderRadius: BorderRadius.circular(20)),
                                child: Row(children: [
                                  const Icon(Icons.edit,
                                      size: 14, color: Colors.white),
                                  const SizedBox(width: 6),
                                  Text("Change",
                                      style: GoogleFonts.poppins(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500)),
                                ])))
                    ],
                  )),
            ),
          ])),
    ];
  }

  // --- UI WIDGET HELPERS ---
  Widget _sectionLabel(String l, IconData icon) => Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade700),
          const SizedBox(width: 8),
          Text(l,
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: Colors.grey.shade800)),
        ],
      );

  Widget _buildDropdown2(String label, String? currentValue, List<String> items,
      Function(String?) onChanged,
      {IconData? icon}) {
    if (currentValue != null && !items.contains(currentValue)) {
      items = [currentValue, ...items];
    }

    return DropdownButtonFormField2<String>(
      isExpanded: true,
      iconStyleData: const IconStyleData(
          icon: Icon(Icons.expand_more, color: Colors.grey)),
      items: items
          .map((e) => DropdownMenuItem(
              value: e,
              child: Text(e,
                  style: GoogleFonts.poppins(fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis)))
          .toList(),
      onChanged: onChanged,
      value: currentValue,
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            GoogleFonts.poppins(color: Colors.grey.shade600, fontSize: 14),
        prefixIcon: icon != null
            ? Icon(icon, color: Colors.grey.shade500, size: 20)
            : null,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _primaryGreen, width: 2)),
        filled: true,
        fillColor: _inputFillColor,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      buttonStyleData:
          const ButtonStyleData(padding: EdgeInsets.only(right: 4)),
      dropdownStyleData: DropdownStyleData(
          maxHeight: 300,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12))),
      menuItemStyleData: const MenuItemStyleData(
          padding: EdgeInsets.symmetric(horizontal: 16)),
    );
  }

  Widget _dropdown(String? label, String? value, List<String> items,
      Function(String?) onChanged,
      {IconData? icon}) {
    return _buildDropdown2(label ?? "", value, items, onChanged, icon: icon);
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
      style: GoogleFonts.poppins(fontSize: 14),
      onChanged: (_) => _markDirty(),
      scrollPadding: const EdgeInsets.only(bottom: 350),
      decoration: InputDecoration(
        labelText: label,
        alignLabelWithHint: maxLines > 1,
        labelStyle:
            GoogleFonts.poppins(color: Colors.grey.shade600, fontSize: 14),
        prefixText: prefix,
        prefixStyle: GoogleFonts.poppins(
            fontWeight: FontWeight.bold, color: Colors.black87, fontSize: 14),
        prefixIcon: icon != null
            ? Icon(icon, color: Colors.grey.shade500, size: 20)
            : null,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _primaryGreen, width: 2)),
        filled: true,
        fillColor: _inputFillColor,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
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
                    colorScheme: ColorScheme.light(primary: _primaryGreen)),
                child: child!));
        if (d != null) {
          _markDirty();
          onConfirm(d);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            color: _inputFillColor,
            borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: GoogleFonts.poppins(
                    color: Colors.grey.shade600,
                    fontSize: 11,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
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
                        fontSize: 14,
                        fontWeight: FontWeight.w500)),
                Icon(Icons.calendar_month, color: _primaryGreen, size: 18),
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
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isSelected ? activeColor.withOpacity(0.08) : _inputFillColor,
            border: Border.all(
                color: isSelected ? activeColor : Colors.grey.shade300,
                width: isSelected ? 1.5 : 1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 18,
                  color: isSelected ? activeColor : Colors.grey.shade500),
              const SizedBox(width: 8),
              Text(type,
                  style: GoogleFonts.poppins(
                      color: isSelected ? activeColor : Colors.grey.shade600,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}
