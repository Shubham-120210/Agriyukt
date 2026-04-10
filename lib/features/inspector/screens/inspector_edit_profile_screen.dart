import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'package:agriyukt_app/core/services/location_service.dart';

extension StringCasingExtension on String {
  String toCapitalized() =>
      length > 0 ? '${this[0].toUpperCase()}${substring(1).toLowerCase()}' : '';
  String toTitleCase() => replaceAll(RegExp(' +'), ' ')
      .split(' ')
      .map((str) => str.toCapitalized())
      .join(' ');
}

class InspectorEditProfileScreen extends StatefulWidget {
  final Map<String, dynamic> profile;
  const InspectorEditProfileScreen({super.key, required this.profile});

  @override
  State<InspectorEditProfileScreen> createState() =>
      _InspectorEditProfileScreenState();
}

class _InspectorEditProfileScreenState
    extends State<InspectorEditProfileScreen> {
  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();

  // 🚀 DEMO STABILITY: Using 'latin' to ensure it doesn't crash downloading language packs
  final TextRecognizer _textRecognizer =
      TextRecognizer(script: TextRecognitionScript.latin);

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isDirty = false;
  bool _isScanning = false;

  final _idCtrl = TextEditingController();
  final _fnameCtrl = TextEditingController();
  final _mnameCtrl = TextEditingController();
  final _lnameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  final _empIdCtrl = TextEditingController();
  String? _selectedOrg;
  final List<String> _orgOptions = [
    'Govt Dept',
    'Private Quality',
    'FPO',
    'Other'
  ];

  final _address1Ctrl = TextEditingController();
  final _address2Ctrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  final _aadharTextCtrl = TextEditingController();

  String? _selectedStateId,
      _selectedDistrictId,
      _selectedTalukaId,
      _selectedVillageId;
  List<LocalizedItem> _stateList = [],
      _districtList = [],
      _talukaList = [],
      _villageList = [];

  File? _selectedFrontImage, _selectedBackImage;
  String? _existingFrontUrl, _existingBackUrl;
  bool _isVerified = false;

  final Color _primaryPurple = const Color(0xFF512DA8);
  final Color _bgOffWhite = const Color(0xFFF8F9FC);

  @override
  void initState() {
    super.initState();
    _loadStates();
    _loadUserProfile();
  }

  @override
  void dispose() {
    _idCtrl.dispose();
    _fnameCtrl.dispose();
    _mnameCtrl.dispose();
    _lnameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _empIdCtrl.dispose();
    _address1Ctrl.dispose();
    _address2Ctrl.dispose();
    _pinCtrl.dispose();
    _aadharTextCtrl.dispose();
    _textRecognizer.close();
    super.dispose();
  }

  void _markDirty() {
    if (!_isDirty) setState(() => _isDirty = true);
  }

  void _loadStates() =>
      setState(() => _stateList = LocationService.getStates());

  Future<void> _loadUserProfile() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final data = await _supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (data != null && mounted) {
        setState(() {
          _idCtrl.text = data['member_id']?.isNotEmpty == true
              ? data['member_id']
              : "#${user.id.substring(0, 5).toUpperCase()}";
          _fnameCtrl.text = data['first_name'] ?? "";
          _mnameCtrl.text = data['middle_name'] ?? "";
          _lnameCtrl.text = data['last_name'] ?? "";
          _phoneCtrl.text = data['phone'] ?? "";
          _emailCtrl.text = data['email'] ?? user.email ?? "";

          final meta = data['meta_data'] is Map ? data['meta_data'] : {};
          _selectedOrg = _orgOptions.contains(meta['organization'])
              ? meta['organization']
              : null;
          _empIdCtrl.text = meta['employee_id'] ?? "";
          _address1Ctrl.text = meta['address_line_1'] ?? "";
          _address2Ctrl.text = meta['address_line_2'] ?? "";
          _selectedStateId = data['state'];
          _pinCtrl.text = data['pincode'] ?? "";

          String rawAadhar = data['aadhar_number'] ?? "";
          _aadharTextCtrl.text = rawAadhar.length >= 12
              ? "XXXX XXXX ${rawAadhar.substring(rawAadhar.length - 4)}"
              : rawAadhar;

          _existingFrontUrl = data['aadhar_front_url'];
          _existingBackUrl = data['aadhar_back_url'];
          _isVerified = (_existingFrontUrl?.isNotEmpty == true &&
              _existingBackUrl?.isNotEmpty == true &&
              rawAadhar.isNotEmpty);

          if (_selectedStateId != null) {
            _districtList = LocationService.getDistricts(_selectedStateId!);
            if (_districtList.any((e) => e.id == data['district'])) {
              _selectedDistrictId = data['district'];
              _talukaList = LocationService.getTalukas(
                  _selectedStateId!, _selectedDistrictId!);
              if (_talukaList.any((e) => e.id == data['taluka'])) {
                _selectedTalukaId = data['taluka'];
                _villageList = LocationService.getVillages(_selectedStateId!,
                    _selectedDistrictId!, _selectedTalukaId!);
                if (_villageList.any((e) => e.id == data['village'])) {
                  _selectedVillageId = data['village'];
                }
              }
            }
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickIdImage(bool isFront) async {
    try {
      // 🚀 CRITICAL FIX: Stops the Android Out Of Memory (OOM) Crash instantly!
      final XFile? file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 50,
        maxWidth: 1200,
        maxHeight: 1200,
      );

      if (file != null) {
        File imageFile = File(file.path);

        if (!mounted) return;
        File? processedFile = await _showRotationDialog(imageFile);

        if (processedFile != null) {
          if (isFront) {
            // 🛡️ THE GATEKEEPER
            bool isStrictlyValid = await _scanAndValidateAadhar(processedFile);
            if (isStrictlyValid && mounted) {
              _markDirty();
              HapticFeedback.lightImpact();
              setState(() => _selectedFrontImage = processedFile);
            }
          } else {
            if (mounted) {
              _markDirty();
              HapticFeedback.lightImpact();
              setState(() => _selectedBackImage = processedFile);
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Image Error: $e");
    }
  }

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

  // 🛡️ THE STRICT 3-POINT VALIDATION LOGIC
  Future<bool> _scanAndValidateAadhar(File file) async {
    setState(() => _isScanning = true);

    String fName = _fnameCtrl.text.trim().toLowerCase();
    String lName = _lnameCtrl.text.trim().toLowerCase();

    if (fName.isEmpty || lName.isEmpty) {
      _showSnack("Please fill your First and Last name before scanning.",
          isError: true);
      setState(() => _isScanning = false);
      return false;
    }

    try {
      final inputImage = InputImage.fromFile(file);
      final RecognizedText recognizedText =
          await _textRecognizer.processImage(inputImage);

      String rawText = recognizedText.text.toLowerCase();
      String rawTextNoSpaces = rawText.replaceAll(RegExp(r'\s+'), '');

      // 1. Name Match Condition
      bool hasName = rawText.contains(fName) && rawText.contains(lName);

      // 2. Authority Check Condition
      bool hasAuthority =
          rawTextNoSpaces.contains("uniqueidentificationauthorityofindia") ||
              rawText.contains("government of india");

      // 3. 12/14-Character Number Check
      RegExp aadharRegex = RegExp(r'\d{4}\s?\d{4}\s?\d{4}');
      RegExpMatch? match = aadharRegex.firstMatch(recognizedText.text);
      bool hasNumber = match != null;

      // (Marathi disabled for demo stability so it doesn't crash trying to read unsupported font)

      if (hasName && hasAuthority && hasNumber) {
        if (mounted) {
          setState(() {
            _aadharTextCtrl.text = match.group(0)!.replaceAll(' ', '');
          });
        }
        _showSnack("✅ Authentic Aadhaar Verified!", isError: false);
        return true;
      } else {
        String errors = "Invalid Document Detected:\n";
        if (!hasName) errors += "❌ Name mismatch with input.\n";
        if (!hasAuthority) errors += "❌ Missing Govt. of India Authority.\n";
        if (!hasNumber) errors += "❌ No valid 12-digit number.\n";

        if (mounted) _showStrictErrorDialog(errors.trim());
        return false;
      }
    } catch (e) {
      if (mounted)
        _showSnack("Failed to scan document clearly. Please try again.",
            isError: true);
      return false;
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  void _showStrictErrorDialog(String errorMsg) {
    HapticFeedback.heavyImpact();
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
                          color: _primaryPurple, fontWeight: FontWeight.bold)),
                )
              ],
            ));
  }

  Future<String?> _uploadFile(File? file, String userId, String side) async {
    if (file == null) return null;
    try {
      final path =
          'id_proofs/$userId/${side}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await _supabase.storage.from('verification_docs').uploadBinary(
          path, await file.readAsBytes(),
          fileOptions: const FileOptions(upsert: true));
      return _supabase.storage.from('verification_docs').getPublicUrl(path);
    } catch (e) {
      return null;
    }
  }

  Future<void> _saveChanges() async {
    if (_isSaving) return;
    if (!_formKey.currentState!.validate()) {
      HapticFeedback.vibrate();
      return;
    }

    setState(() => _isSaving = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw "Unauthorized";

      String? frontUrl =
          await _uploadFile(_selectedFrontImage, user.id, 'front');
      String? backUrl = await _uploadFile(_selectedBackImage, user.id, 'back');

      String finalFrontUrl = frontUrl ?? _existingFrontUrl ?? '';
      String finalBackUrl = backUrl ?? _existingBackUrl ?? '';

      String aadharToSave = _aadharTextCtrl.text.replaceAll(' ', '');
      if (aadharToSave.startsWith('X')) {
        final existing = await _supabase
            .from('profiles')
            .select('aadhar_number')
            .eq('id', user.id)
            .single();
        aadharToSave = existing['aadhar_number'] ?? '';
      }

      String status = (finalFrontUrl.isNotEmpty &&
              finalBackUrl.isNotEmpty &&
              aadharToSave.isNotEmpty)
          ? 'Verified'
          : 'Pending';

      final Map<String, dynamic> updates = {
        'first_name': _fnameCtrl.text.trim().toTitleCase(),
        'middle_name': _mnameCtrl.text.trim().toTitleCase(),
        'last_name': _lnameCtrl.text.trim().toTitleCase(),
        'phone': _phoneCtrl.text.trim(),
        'state': _selectedStateId,
        'district': _selectedDistrictId,
        'taluka': _selectedTalukaId,
        'village': _selectedVillageId,
        'pincode': _pinCtrl.text.trim(),
        'meta_data': {
          'organization': _selectedOrg,
          'employee_id': _empIdCtrl.text.trim().toUpperCase(),
          'address_line_1': _address1Ctrl.text.trim(),
          'address_line_2': _address2Ctrl.text.trim(),
        },
        'aadhar_number': aadharToSave,
        'aadhar_front_url': finalFrontUrl,
        'aadhar_back_url': finalBackUrl,
        'verification_status': status,
        'updated_at': DateTime.now().toIso8601String(),
      };

      await _supabase.from('profiles').update(updates).eq('id', user.id);

      if (mounted) {
        setState(() => _isDirty = false);
        HapticFeedback.mediumImpact();
        _showSuccessOverlay(context);
      }
    } catch (e) {
      if (mounted) {
        HapticFeedback.vibrate();
        _showSnack("Sync Failed. Please try again.", isError: true);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg, style: GoogleFonts.poppins()),
        backgroundColor: isError ? Colors.red : Colors.green));
  }

  void _showSuccessOverlay(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 70),
            const SizedBox(height: 16),
            Text("Profile Synchronized",
                style: GoogleFonts.poppins(
                    fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text("Your secure Inspector profile has been updated.",
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(color: Colors.grey.shade600)),
            const SizedBox(height: 24),
            SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryPurple,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.pop(context, true);
                    },
                    child: const Text("CONTINUE",
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16))))
          ],
        ),
      ),
    );
  }

  Future<bool?> _showExitDialog() {
    return showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text("Discard Changes?"),
                content: const Text("Any unsaved changes will be lost."),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text("Stay")),
                  TextButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text("Discard",
                          style: TextStyle(color: Colors.red)))
                ]));
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_isSaving) return false;
        if (!_isDirty) return true;
        final res = await _showExitDialog();
        return res ?? false;
      },
      child: Scaffold(
        backgroundColor: _bgOffWhite,
        appBar: AppBar(
            title: Text("Edit Inspector Profile",
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
            backgroundColor: _primaryPurple,
            foregroundColor: Colors.white,
            elevation: 0),
        body: _isLoading
            ? Center(child: CircularProgressIndicator(color: _primaryPurple))
            : SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionHeader("Personal Info", Icons.person_pin),
                      _buildShadowInput("Member ID", _idCtrl, Icons.badge,
                          isReadOnly: true),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(
                            child: _buildShadowInput(
                                "First Name", _fnameCtrl, Icons.person,
                                isRequired: true, isAlphaOnly: true)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: _buildShadowInput(
                                "Middle Name", _mnameCtrl, Icons.person_outline,
                                isAlphaOnly: true)),
                      ]),
                      const SizedBox(height: 12),
                      _buildShadowInput("Last Name", _lnameCtrl, Icons.person,
                          isRequired: true, isAlphaOnly: true),
                      const SizedBox(height: 12),
                      _buildShadowInput(
                          "Mobile Number", _phoneCtrl, Icons.phone,
                          isNumber: true, isRequired: true, maxLength: 10),
                      const SizedBox(height: 12),
                      _buildShadowInput(
                          "Email Address", _emailCtrl, Icons.email,
                          isReadOnly: true),
                      const SizedBox(height: 28),
                      _sectionHeader("Professional Details", Icons.work),
                      _buildShadowDropdown(
                          "Organization", _selectedOrg, _orgOptions, (v) {
                        _markDirty();
                        setState(() => _selectedOrg = v);
                      }),
                      const SizedBox(height: 12),
                      _buildShadowInput(
                          "Employee ID", _empIdCtrl, Icons.badge_outlined),
                      const SizedBox(height: 28),
                      _sectionHeader("Location & Address", Icons.map),
                      _buildLocationDropdown(
                          "State", _selectedStateId, _stateList, (val) {
                        _markDirty();
                        setState(() {
                          _selectedStateId = val;
                          _districtList = LocationService.getDistricts(val!);
                          _selectedDistrictId =
                              _selectedTalukaId = _selectedVillageId = null;
                          _talukaList = _villageList = [];
                        });
                      }),
                      const SizedBox(height: 12),
                      _buildLocationDropdown(
                          "District", _selectedDistrictId, _districtList,
                          (val) {
                        _markDirty();
                        setState(() {
                          _selectedDistrictId = val;
                          _talukaList = LocationService.getTalukas(
                              _selectedStateId!, val!);
                          _selectedTalukaId = _selectedVillageId = null;
                          _villageList = [];
                        });
                      }),
                      const SizedBox(height: 12),
                      _buildLocationDropdown(
                          LocationService.isUrban(_selectedDistrictId ?? "")
                              ? "Ward"
                              : "Taluka",
                          _selectedTalukaId,
                          _talukaList, (val) {
                        _markDirty();
                        setState(() {
                          _selectedTalukaId = val;
                          _villageList = LocationService.getVillages(
                              _selectedStateId!, _selectedDistrictId!, val!);
                          _selectedVillageId = null;
                        });
                      }),
                      const SizedBox(height: 12),
                      _buildLocationDropdown(
                          LocationService.isUrban(_selectedDistrictId ?? "")
                              ? "Locality"
                              : "Village",
                          _selectedVillageId,
                          _villageList, (val) {
                        _markDirty();
                        setState(() => _selectedVillageId = val);
                      }),
                      const SizedBox(height: 12),
                      _buildShadowInput(
                          "Address Line 1", _address1Ctrl, Icons.home,
                          isRequired: true),
                      const SizedBox(height: 12),
                      _buildShadowInput(
                          "Address Line 2", _address2Ctrl, Icons.home_work),
                      const SizedBox(height: 12),
                      _buildShadowInput("Pincode", _pinCtrl, Icons.pin_drop,
                          isNumber: true, maxLength: 6, isRequired: true),
                      const SizedBox(height: 28),
                      _sectionHeader("Verification", Icons.verified_user),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.grey.withOpacity(0.1),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4))
                            ]),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text("Strict Identity Verification",
                                    style: GoogleFonts.poppins(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: _primaryPurple)),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                      color: _isVerified
                                          ? Colors.green.withOpacity(0.1)
                                          : Colors.orange.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: _isVerified
                                              ? Colors.green
                                              : Colors.orange)),
                                  child: Text(
                                      _isVerified ? "Verified" : "Pending",
                                      style: GoogleFonts.poppins(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: _isVerified
                                              ? Colors.green
                                              : Colors.orange)),
                                )
                              ],
                            ),
                            const SizedBox(height: 15),
                            Text("Aadhaar Front (MUST Match Name)",
                                style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red.shade800)),
                            const SizedBox(height: 8),
                            _buildDocumentUploadBox(true),
                            const SizedBox(height: 15),
                            Text("Aadhaar Back",
                                style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.grey.shade600)),
                            const SizedBox(height: 8),
                            _buildDocumentUploadBox(false),
                            const SizedBox(height: 20),
                            // 🚀 FIX: Made Aadhaar text read only so user can't fake it!
                            _buildShadowInput("Aadhar Number", _aadharTextCtrl,
                                Icons.fingerprint,
                                isNumber: true,
                                isRequired: true,
                                maxLength: 12,
                                isReadOnly: true),
                          ],
                        ),
                      ),
                      const SizedBox(height: 40),
                      SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: ElevatedButton(
                          onPressed: _isSaving ? null : _saveChanges,
                          style: ElevatedButton.styleFrom(
                              backgroundColor: _primaryPurple,
                              shadowColor: _primaryPurple.withOpacity(0.4),
                              elevation: 8,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16))),
                          child: _isSaving
                              ? const CircularProgressIndicator(
                                  color: Colors.white)
                              : Text("SAVE CHANGES",
                                  style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold)),
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

  Widget _sectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Row(children: [
        Container(
            height: 24,
            width: 4,
            decoration: BoxDecoration(
                color: _primaryPurple, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Icon(icon, size: 20, color: _primaryPurple),
        const SizedBox(width: 8),
        Text(title,
            style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.black87))
      ]),
    );
  }

  Widget _buildShadowInput(
      String label, TextEditingController ctrl, IconData icon,
      {bool isNumber = false,
      bool isAlphaOnly = false,
      bool isReadOnly = false,
      bool isRequired = false,
      int? maxLength}) {
    List<TextInputFormatter> formatters = [];
    if (isNumber) formatters.add(FilteringTextInputFormatter.digitsOnly);
    if (isAlphaOnly)
      formatters.add(FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]')));
    if (maxLength != null)
      formatters.add(LengthLimitingTextInputFormatter(maxLength));

    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.grey.withOpacity(0.08),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ]),
      child: TextFormField(
        controller: ctrl,
        readOnly: isReadOnly,
        onChanged: (_) => _markDirty(),
        textInputAction: TextInputAction.next,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        inputFormatters: formatters,
        validator: (v) {
          if (isRequired && (v == null || v.trim().isEmpty))
            return "$label is required";
          if (isNumber &&
              maxLength != null &&
              v!.length < maxLength &&
              !v.startsWith('X')) return "Invalid length";
          return null;
        },
        style: GoogleFonts.poppins(fontSize: 15),
        decoration: InputDecoration(
            labelText: label,
            labelStyle:
                GoogleFonts.poppins(color: Colors.grey.shade500, fontSize: 13),
            prefixIcon:
                Icon(icon, color: _primaryPurple.withOpacity(0.7), size: 20),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none),
            filled: true,
            fillColor: isReadOnly ? Colors.grey.shade50 : Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
      ),
    );
  }

  Widget _buildShadowDropdown(String label, String? value, List<String> items,
      Function(String?) onChanged) {
    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.grey.withOpacity(0.08),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ]),
      child: DropdownButtonFormField<String>(
        value: value,
        validator: (v) => v == null ? "Please select $label" : null,
        items: items
            .map((e) => DropdownMenuItem(
                value: e,
                child: Text(e, style: GoogleFonts.poppins(fontSize: 15))))
            .toList(),
        onChanged: onChanged,
        decoration: InputDecoration(
            labelText: label,
            labelStyle:
                GoogleFonts.poppins(color: Colors.grey.shade500, fontSize: 13),
            prefixIcon: Icon(Icons.arrow_drop_down_circle,
                color: _primaryPurple.withOpacity(0.7), size: 20),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
      ),
    );
  }

  Widget _buildLocationDropdown(String label, String? value,
      List<LocalizedItem> items, Function(String?) onChanged) {
    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.grey.withOpacity(0.08),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ]),
      child: DropdownButtonFormField<String>(
        value: value,
        isExpanded: true,
        validator: (v) => v == null ? "Please select $label" : null,
        items: items
            .map((e) => DropdownMenuItem(
                value: e.id,
                child: Text(e.getName(false),
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(fontSize: 15))))
            .toList(),
        onChanged: onChanged,
        decoration: InputDecoration(
            labelText: label,
            labelStyle:
                GoogleFonts.poppins(color: Colors.grey.shade500, fontSize: 13),
            prefixIcon: Icon(Icons.map_outlined,
                color: _primaryPurple.withOpacity(0.7), size: 20),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
      ),
    );
  }

  Widget _buildDocumentUploadBox(bool isFront) {
    File? file = isFront ? _selectedFrontImage : _selectedBackImage;
    String? existingUrl = isFront ? _existingFrontUrl : _existingBackUrl;
    bool hasImage =
        file != null || (existingUrl != null && existingUrl.isNotEmpty);

    if (hasImage) {
      return Container(
        height: 160,
        width: double.infinity,
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200)),
        child: Stack(
          alignment: Alignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: file != null
                  ? Image.file(file, fit: BoxFit.cover, width: double.infinity)
                  : Image.network(existingUrl!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      loadingBuilder: (context, child, p) {
                        if (p == null) return child;
                        return Center(
                            child: CircularProgressIndicator(
                                color: _primaryPurple));
                      },
                      errorBuilder: (c, e, s) => const Center(
                          child: Icon(Icons.broken_image, color: Colors.grey))),
            ),
            if (_isScanning && isFront)
              Container(
                  decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(16)),
                  child: const Center(
                      child: CircularProgressIndicator(color: Colors.white))),
            Positioned(
                right: 10,
                bottom: 10,
                child: InkWell(
                    onTap: () => _pickIdImage(isFront),
                    child: const CircleAvatar(
                        backgroundColor: Colors.white,
                        radius: 18,
                        child:
                            Icon(Icons.edit, size: 18, color: Colors.black87))))
          ],
        ),
      );
    }
    return InkWell(
      onTap: () => _pickIdImage(isFront),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 160,
        width: double.infinity,
        decoration: BoxDecoration(
            color: const Color(0xFFF2F4F7),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade300, width: 1.5)),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.cloud_upload_outlined,
              size: 36, color: Colors.grey.shade400),
          const SizedBox(height: 8),
          Text("Tap to Upload ${isFront ? 'Front' : 'Back'}",
              style: GoogleFonts.poppins(
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                  fontSize: 13))
        ]),
      ),
    );
  }
}
