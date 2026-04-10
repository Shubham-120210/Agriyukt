import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:agriyukt_app/core/services/location_service.dart';

class AddFarmerScreen extends StatefulWidget {
  const AddFarmerScreen({super.key});

  @override
  State<AddFarmerScreen> createState() => _AddFarmerScreenState();
}

class _AddFarmerScreenState extends State<AddFarmerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _supabase = Supabase.instance.client;

  // 🛡️ Logic Guards
  bool _isLoading = false;
  bool _isProcessingImage = false;
  bool _isSubmitting = false;

  // 🛡️ STABILITY: Using 'latin' to ensure 100% crash-free performance
  final TextRecognizer _textRecognizer =
      TextRecognizer(script: TextRecognitionScript.latin);

  // --- 1. PERSONAL CONTROLLERS ---
  final _firstNameCtrl = TextEditingController();
  final _middleNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  // --- 2. ADDRESS CONTROLLERS ---
  final _addr1Ctrl = TextEditingController();
  final _pinCtrl = TextEditingController();

  // --- 3. BANK CONTROLLERS ---
  final _bankAccCtrl = TextEditingController();
  final _bankIfscCtrl = TextEditingController();
  final _bankNameCtrl = TextEditingController();

  // --- 4. FARM DETAILS ---
  String? _farmSize;
  final List<String> _farmSizeOptions = [
    '< 2 acres',
    '2-5 acres',
    '5-10 acres',
    '10+ acres'
  ];

  // --- 5. ID VERIFICATION STATE ---
  File? _frontImage;
  File? _backImage;
  String _frontMsg = "Tap to Scan Front";
  String _backMsg = "Tap to Scan Back";
  bool _isFrontValid = false;
  bool _isBackValid = false;
  String? _extractedAadharNumber;

  // --- 6. LOCATION STATE ---
  String? _selectedStateId;
  String? _selectedDistrictId;
  String? _selectedTalukaId;
  String? _selectedVillageId;

  List<LocalizedItem> _stateList = [];
  List<LocalizedItem> _districtList = [];
  List<LocalizedItem> _talukaList = [];
  List<LocalizedItem> _villageList = [];

  // Theme Color (Inspector Purple)
  final Color _inspectorColor = const Color(0xFF512DA8);

  @override
  void initState() {
    super.initState();
    _loadStates();
  }

  void _loadStates() {
    setState(() {
      _stateList = LocationService.getStates();
    });
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _middleNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _phoneCtrl.dispose();
    _addr1Ctrl.dispose();
    _pinCtrl.dispose();
    _bankAccCtrl.dispose();
    _bankIfscCtrl.dispose();
    _bankNameCtrl.dispose();
    _textRecognizer.close();
    super.dispose();
  }

  // --- 🚀 MEMORY-SAFE IMAGE PICKER & CAMERA BOTTOM SHEET ---
  Future<void> _pickImage(bool isFront) async {
    if (_isProcessingImage || _isSubmitting) return;

    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: Icon(Icons.camera_alt, color: _inspectorColor),
              title: const Text('Take Photo',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: Icon(Icons.photo_library, color: _inspectorColor),
              title: const Text('Choose from Gallery',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    try {
      setState(() => _isProcessingImage = true);

      final picker = ImagePicker();
      // 🚀 CRITICAL FIX: Memory safe limits to prevent OOM
      final img = await picker.pickImage(
          source: source, imageQuality: 50, maxWidth: 1200, maxHeight: 1200);

      if (img == null) {
        setState(() => _isProcessingImage = false);
        return;
      }

      File imageFile = File(img.path);

      if (!mounted) return;
      File? processedFile = await _showRotationDialog(imageFile);

      if (processedFile != null) {
        setState(() {
          if (isFront) {
            _frontImage = processedFile;
            _frontMsg = "⏳ Analyzing...";
          } else {
            _backImage = processedFile;
            _backMsg = "⏳ Analyzing...";
          }
        });

        // 🛡️ SECURITY GATEKEEPER
        await _scanAndValidateAadhar(processedFile, isFront);
      }
    } catch (e) {
      debugPrint("Image Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Error processing image. Please try again."),
            backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isProcessingImage = false);
    }
  }

  // 🚀 PURE FLUTTER ROTATION UI
  Future<File?> _showRotationDialog(File file) async {
    int rotationTurns = 0;
    return await showDialog<File>(
      context: context,
      barrierDismissible: false,
      builder: (c) => StatefulBuilder(builder: (context, setDialogState) {
        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            title: Text("Align Identity Card",
                style: GoogleFonts.poppins(color: Colors.white, fontSize: 16)),
            leading: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(c)),
          ),
          body: Center(
              child: RotatedBox(
                  quarterTurns: rotationTurns,
                  child: Image.file(file, fit: BoxFit.contain))),
          bottomNavigationBar: SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 20),
              color: Colors.black,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                          icon: const Icon(Icons.rotate_right,
                              color: Colors.white, size: 35),
                          onPressed: () => setDialogState(
                              () => rotationTurns = (rotationTurns + 1) % 4)),
                      Text("Rotate 90°",
                          style: GoogleFonts.poppins(
                              color: Colors.white, fontSize: 12)),
                    ],
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                          icon: const Icon(Icons.check_circle,
                              color: Colors.greenAccent, size: 45),
                          onPressed: () => Navigator.pop(c, file)),
                      Text("Confirm",
                          style: GoogleFonts.poppins(
                              color: Colors.white, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  // 🛡️ STRICT VALIDATION LOGIC
  Future<void> _scanAndValidateAadhar(File file, bool isFront) async {
    final inputImage = InputImage.fromFile(file);

    try {
      final RecognizedText recognizedText =
          await _textRecognizer.processImage(inputImage);
      String fullText = recognizedText.text.toLowerCase().replaceAll("\n", " ");
      String textNoSpaces = fullText.replaceAll(RegExp(r'\s+'), '');

      if (isFront) {
        String fName = _firstNameCtrl.text.trim().toLowerCase();
        String lName = _lastNameCtrl.text.trim().toLowerCase();

        if (fName.isEmpty || lName.isEmpty) {
          HapticFeedback.vibrate();
          setState(() {
            _isFrontValid = false;
            _frontImage = null; // Reject image
            _frontMsg = "❌ Enter Farmer Name above first!";
          });
          return;
        }

        bool hasName = fullText.contains(fName) && fullText.contains(lName);
        bool hasAuthority =
            textNoSpaces.contains("uniqueidentificationauthorityofindia") ||
                fullText.contains("government of india");

        RegExp aadharRegex = RegExp(r'\d{4}\s?\d{4}\s?\d{4}');
        RegExpMatch? match = aadharRegex.firstMatch(recognizedText.text);
        bool hasNumber = match != null;

        if (hasName && hasAuthority && hasNumber) {
          HapticFeedback.lightImpact();
          setState(() {
            _isFrontValid = true;
            _frontMsg = "✅ Valid: Name & Aadhaar Match";
            _extractedAadharNumber = match.group(0)!.replaceAll(' ', '');
          });
        } else {
          String errors = "Invalid Document Detected:\n";
          if (!hasName) errors += "❌ Name mismatch with input.\n";
          if (!hasAuthority) errors += "❌ Missing Govt. of India.\n";
          if (!hasNumber) errors += "❌ No valid 12-digit number.\n";

          HapticFeedback.heavyImpact();
          _showStrictErrorDialog(errors.trim());

          setState(() {
            _isFrontValid = false;
            _frontImage = null;
            _frontMsg = "Tap to Scan Front";
          });
        }
      } else {
        // Back Side Logic
        if (fullText.contains("address") ||
            fullText.contains("pin") ||
            recognizedText.text.contains(RegExp(r'\d{6}'))) {
          HapticFeedback.lightImpact();
          setState(() {
            _isBackValid = true;
            _backMsg = "✅ Address Detected";
          });
        } else {
          HapticFeedback.heavyImpact();
          setState(() {
            _isBackValid = false;
            _backImage = null;
            _backMsg = "⚠️ Address unclear. Retake.";
          });
        }
      }
    } catch (e) {
      debugPrint("OCR Error: $e");
      setState(() {
        if (isFront) {
          _isFrontValid = false;
          _frontImage = null;
          _frontMsg = "❌ Processing Failed";
        } else {
          _isBackValid = false;
          _backImage = null;
          _backMsg = "❌ Processing Failed";
        }
      });
    }
  }

  void _showStrictErrorDialog(String errorMsg) {
    showDialog(
        context: context,
        builder: (c) => AlertDialog(
              title: Row(children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.red),
                const SizedBox(width: 8),
                Text("Verification Failed",
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold, fontSize: 18))
              ]),
              content: Text(errorMsg, style: GoogleFonts.poppins(fontSize: 14)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c),
                  child: Text("RETRY",
                      style: GoogleFonts.poppins(
                          color: _inspectorColor, fontWeight: FontWeight.bold)),
                )
              ],
            ));
  }

  // --- SUBMISSION LOGIC ---
  Future<void> _registerFarmer() async {
    if (_isSubmitting || _isProcessingImage) return;

    // 🚀 ANTI-SILENT FAILURE: Form Validation Feedback
    if (!_formKey.currentState!.validate()) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("⚠️ Please fill in all required fields correctly."),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    // 🚀 ANTI-SILENT FAILURE: Location Verification
    if (_selectedStateId == null ||
        _selectedDistrictId == null ||
        _selectedTalukaId == null ||
        _selectedVillageId == null) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("⚠️ Please complete the entire Location section."),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    // 🚀 ANTI-SILENT FAILURE: Strict ID Verification
    if (!_isFrontValid ||
        !_isBackValid ||
        _frontImage == null ||
        _backImage == null) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:
            Text("⚠️ Please successfully scan both sides of the Aadhaar Card."),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    setState(() {
      _isLoading = true;
      _isSubmitting = true;
    });

    List<String> uploadedPaths = [];

    try {
      final inspector = _supabase.auth.currentUser;
      if (inspector == null)
        throw "Inspector session expired. Please log in again.";

      final newFarmerId = const Uuid().v4();
      String frontUrl = "";
      String backUrl = "";
      String time = DateTime.now().millisecondsSinceEpoch.toString();

      // 🚀 CRITICAL FIX: Safe uploadBinary method
      final fileOptions =
          const FileOptions(contentType: 'image/jpeg', upsert: true);

      if (_frontImage != null) {
        String path = 'farmers_docs/${newFarmerId}_front_$time.jpg';
        await _supabase.storage
            .from('verification_docs')
            .uploadBinary(path, await _frontImage!.readAsBytes(),
                fileOptions: fileOptions)
            .timeout(const Duration(seconds: 45));
        uploadedPaths.add(path);
        frontUrl =
            _supabase.storage.from('verification_docs').getPublicUrl(path);
      }

      if (_backImage != null) {
        String path = 'farmers_docs/${newFarmerId}_back_$time.jpg';
        await _supabase.storage
            .from('verification_docs')
            .uploadBinary(path, await _backImage!.readAsBytes(),
                fileOptions: fileOptions)
            .timeout(const Duration(seconds: 45));
        uploadedPaths.add(path);
        backUrl =
            _supabase.storage.from('verification_docs').getPublicUrl(path);
      }

      String mName = _middleNameCtrl.text.trim();
      String bName = _bankNameCtrl.text.trim();
      String bAcc = _bankAccCtrl.text.trim();
      String bIfsc = _bankIfscCtrl.text.trim().toUpperCase();

      final Map<String, dynamic> farmerData = {
        'id': newFarmerId,
        'role': 'farmer',
        'first_name': _firstNameCtrl.text.trim(),
        'middle_name': mName.isEmpty ? null : mName,
        'last_name': _lastNameCtrl.text.trim(),
        'phone': '+91${_phoneCtrl.text.trim()}',
        'address_line_1': _addr1Ctrl.text.trim(),
        'pincode': _pinCtrl.text.trim(),
        'state': _selectedStateId,
        'district': _selectedDistrictId,
        'taluka': _selectedTalukaId,
        'village': _selectedVillageId,
        'bank_account_no': bAcc.isEmpty ? null : bAcc,
        'ifsc_code': bIfsc.isEmpty ? null : bIfsc,
        'bank_name': bName.isEmpty ? null : bName,
        'aadhar_number': _extractedAadharNumber,
        'aadhar_front_url': frontUrl,
        'aadhar_back_url': backUrl,
        'verification_status': 'Verified',
        'wallet_balance': 0.0,
        'created_at': DateTime.now().toIso8601String(),
        'inspector_id': inspector.id,
        // Match the meta_data schema expected by the rest of the app
        'meta_data': {
          'land_size': _farmSize,
        }
      };

      await _supabase
          .from('profiles')
          .insert(farmerData)
          .timeout(const Duration(seconds: 15));

      if (mounted) {
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("✅ Farmer Account Created Successfully!"),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating));
        Navigator.pop(context, true);
      }
    } catch (e) {
      // Rollback images if database insert fails
      if (uploadedPaths.isNotEmpty) {
        try {
          await _supabase.storage
              .from('verification_docs')
              .remove(uploadedPaths);
        } catch (_) {}
      }

      String errorMsg = "Save Failed. Please try again.";

      // 🚀 DUPLICATE PHONE CATCHER
      if (e.toString().contains("unique_phone_number") ||
          e.toString().contains("23505")) {
        errorMsg =
            "❌ This mobile number is already registered to another farmer.";
      } else if (e is TimeoutException) {
        errorMsg = "Connection timed out. Please check your internet.";
      }

      if (mounted) {
        HapticFeedback.heavyImpact();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(errorMsg),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: const Color(0xFFF3E5F5),
        appBar: AppBar(
          title: Text("Register New Farmer",
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          backgroundColor: _inspectorColor,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionHeader("Personal Details"),
                _buildTextField("First Name *", _firstNameCtrl, Icons.person),
                const SizedBox(height: 15),
                _buildTextField(
                    "Middle Name", _middleNameCtrl, Icons.person_outline,
                    required: false),
                const SizedBox(height: 15),
                _buildTextField(
                    "Last Name *", _lastNameCtrl, Icons.person_outline),
                const SizedBox(height: 15),
                _buildTextField("Mobile Number *", _phoneCtrl, Icons.phone,
                    isNumber: true, maxLength: 10),

                const SizedBox(height: 25),
                _sectionHeader("Strict Identity Verification"),
                Row(
                  children: [
                    Expanded(
                        child: _buildIdCard("Front Side", _frontImage,
                            _frontMsg, _isFrontValid, true)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _buildIdCard("Back Side", _backImage, _backMsg,
                            _isBackValid, false)),
                  ],
                ),
                if (_extractedAadharNumber != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text("Detected ID: $_extractedAadharNumber",
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.bold, color: Colors.green)),
                  ),

                const SizedBox(height: 25),
                _sectionHeader("Farming Details"),
                DropdownButtonFormField<String>(
                  value: _farmSize,
                  decoration: _inputDecoration("Farm Size *", Icons.landscape),
                  items: _farmSizeOptions
                      .map((e) => DropdownMenuItem(
                          value: e,
                          child: Text(e, style: GoogleFonts.poppins())))
                      .toList(),
                  onChanged: (v) => setState(() => _farmSize = v),
                  validator: (v) => v == null ? "Required" : null,
                ),

                const SizedBox(height: 25),
                _sectionHeader("Location"),
                _locationDropdown("State *", _selectedStateId, _stateList,
                    (val) {
                  setState(() {
                    _selectedStateId = val;
                    _districtList = LocationService.getDistricts(val!);
                    _selectedDistrictId =
                        _selectedTalukaId = _selectedVillageId = null;
                    _talukaList = _villageList = [];
                  });
                }),
                const SizedBox(height: 15),
                _locationDropdown(
                    "District *", _selectedDistrictId, _districtList, (val) {
                  setState(() {
                    _selectedDistrictId = val;
                    _talukaList =
                        LocationService.getTalukas(_selectedStateId!, val!);
                    _selectedTalukaId = _selectedVillageId = null;
                    _villageList = [];
                  });
                }),
                const SizedBox(height: 15),
                Row(
                  children: [
                    Expanded(
                      child: _locationDropdown(
                          "Taluka *", _selectedTalukaId, _talukaList, (val) {
                        setState(() {
                          _selectedTalukaId = val;
                          _villageList = LocationService.getVillages(
                              _selectedStateId!, _selectedDistrictId!, val!);
                          _selectedVillageId = null;
                        });
                      }),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _locationDropdown(
                          "Village *", _selectedVillageId, _villageList, (val) {
                        setState(() => _selectedVillageId = val);
                      }),
                    ),
                  ],
                ),

                const SizedBox(height: 25),
                _sectionHeader("Address"),
                _buildTextField("Address / Landmark *", _addr1Ctrl, Icons.home),
                const SizedBox(height: 15),
                _buildTextField("Pincode *", _pinCtrl, Icons.pin_drop,
                    isNumber: true, maxLength: 6),

                const SizedBox(height: 25),
                _sectionHeader("Bank Details (Optional)"),
                _buildTextField(
                    "Bank Name", _bankNameCtrl, Icons.account_balance,
                    required: false),
                const SizedBox(height: 15),
                _buildTextField("Account Number", _bankAccCtrl, Icons.numbers,
                    isNumber: true, required: false),
                const SizedBox(height: 15),
                _buildTextField("IFSC Code", _bankIfscCtrl, Icons.qr_code,
                    required: false),

                const SizedBox(height: 40),

                // --- SUBMIT ---
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    onPressed: _isLoading || _isProcessingImage || _isSubmitting
                        ? null
                        : _registerFarmer,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _inspectorColor,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 4,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : Text("Create Farmer Account",
                            style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Row(
        children: [
          Container(width: 4, height: 18, color: _inspectorColor),
          const SizedBox(width: 8),
          Text(title,
              style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87)),
        ],
      ),
    );
  }

  Widget _buildTextField(
      String label, TextEditingController controller, IconData icon,
      {bool isNumber = false, int? maxLength, bool required = true}) {
    return TextFormField(
      controller: controller,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      maxLength: maxLength,
      inputFormatters: isNumber ? [FilteringTextInputFormatter.digitsOnly] : [],
      validator: (value) {
        if (required && (value == null || value.trim().isEmpty)) {
          return "$label is required";
        }
        if (isNumber &&
            maxLength != null &&
            value != null &&
            value.trim().length != maxLength) {
          return "Must be exactly $maxLength digits";
        }
        return null;
      },
      style: GoogleFonts.poppins(),
      decoration: _inputDecoration(label, icon).copyWith(counterText: ""),
    );
  }

  Widget _locationDropdown(String label, String? value,
      List<LocalizedItem> items, Function(String?) onChanged) {
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      items: items
          .map((e) => DropdownMenuItem(
              value: e.id,
              child: Text(e.nameEn,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins())))
          .toList(),
      onChanged: onChanged,
      validator: (v) => label.contains("*") && v == null ? "Required" : null,
      decoration: _inputDecoration(label, Icons.map),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.poppins(fontSize: 14),
      prefixIcon: Icon(icon, color: _inspectorColor.withOpacity(0.6)),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _inspectorColor, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      errorStyle: GoogleFonts.poppins(color: Colors.red),
    );
  }

  Widget _buildIdCard(
      String title, File? img, String msg, bool isValid, bool isFront) {
    Color borderColor = isValid
        ? Colors.green
        : (msg.contains("❌") ? Colors.red : Colors.grey.shade300);
    return GestureDetector(
      onTap: () => _pickImage(isFront),
      child: Container(
        height: 130,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 2),
        ),
        child: Column(
          children: [
            Expanded(
              child: img == null
                  ? Icon(Icons.add_a_photo,
                      color: _inspectorColor.withOpacity(0.3), size: 35)
                  : ClipRRect(
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(10)),
                      child: Image.file(img,
                          width: double.infinity, fit: BoxFit.cover)),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              decoration: BoxDecoration(
                color: isValid
                    ? Colors.green
                    : (img != null
                        ? (msg.contains("❌") ? Colors.red : Colors.orange)
                        : Colors.grey.shade100),
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(10)),
              ),
              child: Text(
                isValid ? "Verified" : msg,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: (isValid || img != null)
                        ? Colors.white
                        : Colors.black54),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            )
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 📍 FORMATTER HELPERS
// -----------------------------------------------------------------------------
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return TextEditingValue(
        text: newValue.text.toUpperCase(), selection: newValue.selection);
  }
}
