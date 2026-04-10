import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

// ✅ ACTIVE: Using your actual Location Service
import 'package:agriyukt_app/core/services/location_service.dart';

class EditFarmerScreen extends StatefulWidget {
  final Map<String, dynamic> farmer;
  const EditFarmerScreen({super.key, required this.farmer});

  @override
  State<EditFarmerScreen> createState() => _EditFarmerScreenState();
}

class _EditFarmerScreenState extends State<EditFarmerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _supabase = Supabase.instance.client;

  // 🛡️ Logic Guards
  bool _isLoading = false;
  bool _canPop =
      false; // 🚀 PRODUCTION FIX: Prevents infinite dialog loops on back swipe
  AutovalidateMode _autoValidateMode = AutovalidateMode.disabled;

  // --- CONTROLLERS ---
  late TextEditingController _firstNameCtrl;
  late TextEditingController _middleNameCtrl;
  late TextEditingController _lastNameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _addr1Ctrl;
  late TextEditingController _pinCtrl;

  // --- BANK CONTROLLERS ---
  late TextEditingController _bankAccCtrl;
  late TextEditingController _bankIfscCtrl;
  late TextEditingController _bankNameCtrl;

  // --- FARM DETAILS ---
  String? _farmSize;
  final List<String> _farmSizeOptions = [
    '< 2 acres',
    '2-5 acres',
    '5-10 acres',
    '10+ acres'
  ];

  // --- LOCATION STATE ---
  String? _selectedStateId;
  String? _selectedDistrictId;
  String? _selectedTalukaId;
  String? _selectedVillageId;

  List<LocalizedItem> _stateList = [];
  List<LocalizedItem> _districtList = [];
  List<LocalizedItem> _talukaList = [];
  List<LocalizedItem> _villageList = [];

  final Color _inspectorColor = const Color(0xFF512DA8);

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  // 🛡️ Robust Initialization: Solves the Name vs ID Mismatch Bug!
  void _initializeData() {
    final f = widget.farmer;

    _firstNameCtrl =
        TextEditingController(text: f['first_name']?.toString() ?? '');
    _middleNameCtrl =
        TextEditingController(text: f['middle_name']?.toString() ?? '');
    _lastNameCtrl =
        TextEditingController(text: f['last_name']?.toString() ?? '');

    String rawPhone =
        f['phone']?.toString().replaceAll(RegExp(r'\D'), '') ?? '';
    if (rawPhone.length > 10 && rawPhone.startsWith('91')) {
      rawPhone = rawPhone.substring(2);
    }
    if (rawPhone.length > 10)
      rawPhone = rawPhone.substring(rawPhone.length - 10);
    _phoneCtrl = TextEditingController(text: rawPhone);

    _addr1Ctrl =
        TextEditingController(text: f['address_line_1']?.toString() ?? '');
    _pinCtrl = TextEditingController(
        text: f['pincode']?.toString().replaceAll(RegExp(r'\D'), '') ?? '');

    _bankNameCtrl =
        TextEditingController(text: f['bank_name']?.toString() ?? '');
    _bankAccCtrl = TextEditingController(
        text: f['bank_account_no']?.toString().replaceAll(RegExp(r'\D'), '') ??
            '');
    _bankIfscCtrl =
        TextEditingController(text: f['ifsc_code']?.toString() ?? '');

    String? dbFarmSize = f['land_size']?.toString();
    if (dbFarmSize != null) {
      try {
        _farmSize = _farmSizeOptions
            .firstWhere((e) => e.toLowerCase() == dbFarmSize.toLowerCase());
      } catch (_) {
        _farmSize = null;
      }
    }

    // 🚀 PRODUCTION FIX: Bi-Directional Location Resolver
    _stateList = LocationService.getStates();
    String? stateStr = f['state']?.toString();

    if (stateStr != null) {
      final matchedState = _stateList
          .where((e) => e.id == stateStr || e.nameEn == stateStr)
          .firstOrNull;
      if (matchedState != null) {
        _selectedStateId = matchedState.id;
        _districtList = LocationService.getDistricts(matchedState.id);

        String? distStr = f['district']?.toString();
        if (distStr != null) {
          final matchedDist = _districtList
              .where((e) => e.id == distStr || e.nameEn == distStr)
              .firstOrNull;
          if (matchedDist != null) {
            _selectedDistrictId = matchedDist.id;
            _talukaList =
                LocationService.getTalukas(matchedState.id, matchedDist.id);

            String? talukaStr = f['taluka']?.toString();
            if (talukaStr != null) {
              final matchedTaluka = _talukaList
                  .where((e) => e.id == talukaStr || e.nameEn == talukaStr)
                  .firstOrNull;
              if (matchedTaluka != null) {
                _selectedTalukaId = matchedTaluka.id;
                _villageList = LocationService.getVillages(
                    matchedState.id, matchedDist.id, matchedTaluka.id);

                String? villageStr = f['village']?.toString();
                if (villageStr != null) {
                  final matchedVillage = _villageList
                      .where(
                          (e) => e.id == villageStr || e.nameEn == villageStr)
                      .firstOrNull;
                  if (matchedVillage != null) {
                    _selectedVillageId = matchedVillage.id;
                  }
                }
              }
            }
          }
        }
      }
    }
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
    super.dispose();
  }

  Future<void> _updateFarmer() async {
    if (_isLoading) return;

    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      setState(() => _autoValidateMode = AutovalidateMode.onUserInteraction);
      HapticFeedback.heavyImpact();
      return;
    }

    setState(() => _isLoading = true);

    try {
      final inspector = _supabase.auth.currentUser;
      if (inspector == null) throw "Session expired. Please log in.";

      if (widget.farmer['id'] == null)
        throw "Invalid farmer record: ID is missing.";
      String currentFarmerId = widget.farmer['id'].toString();

      String newPhone = _phoneCtrl.text.trim();
      String? originalPhone =
          widget.farmer['phone']?.toString().replaceAll(RegExp(r'\D'), '');
      if (originalPhone != null &&
          originalPhone.length > 10 &&
          originalPhone.startsWith('91')) {
        originalPhone = originalPhone.substring(2);
      }

      if (newPhone != originalPhone) {
        final existingPhoneCheck = await _supabase
            .from('profiles')
            .select('id')
            .eq('phone', newPhone)
            .neq('id', currentFarmerId)
            .maybeSingle()
            .timeout(const Duration(seconds: 10));

        if (existingPhoneCheck != null) {
          throw "This phone number is already registered to another farmer.";
        }
      }

      String? mName = _middleNameCtrl.text.trim();
      if (mName.isEmpty) mName = null;
      String? bName = _bankNameCtrl.text.trim();
      if (bName.isEmpty) bName = null;
      String? bAcc = _bankAccCtrl.text.trim();
      if (bAcc.isEmpty) bAcc = null;
      String? bIfsc = _bankIfscCtrl.text.trim().toUpperCase();
      if (bIfsc.isEmpty) bIfsc = null;

      // 🚀 PRODUCTION FIX: Resolve IDs back to Names before saving to DB
      String? stateName = _selectedStateId != null
          ? _stateList
              .where((e) => e.id == _selectedStateId)
              .firstOrNull
              ?.nameEn
          : null;
      String? distName = _selectedDistrictId != null
          ? _districtList
              .where((e) => e.id == _selectedDistrictId)
              .firstOrNull
              ?.nameEn
          : null;
      String? talukaName = _selectedTalukaId != null
          ? _talukaList
              .where((e) => e.id == _selectedTalukaId)
              .firstOrNull
              ?.nameEn
          : null;
      String? villageName = _selectedVillageId != null
          ? _villageList
              .where((e) => e.id == _selectedVillageId)
              .firstOrNull
              ?.nameEn
          : null;

      final updates = {
        'first_name': _firstNameCtrl.text.trim(),
        'middle_name': mName,
        'last_name': _lastNameCtrl.text.trim(),
        'phone': newPhone,
        'land_size': _farmSize,
        'address_line_1': _addr1Ctrl.text.trim(),
        'pincode': _pinCtrl.text.trim(),
        'state': stateName,
        'district': distName,
        'taluka': talukaName,
        'village': villageName,
        'bank_name': bName,
        'bank_account_no': bAcc,
        'ifsc_code': bIfsc,
      };

      await _supabase
          .from('profiles')
          .update(updates)
          .eq('id', currentFarmerId)
          .timeout(const Duration(seconds: 15));

      if (mounted) {
        setState(() => _canPop = true); // Unlock PopScope
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("✅ Farmer Updated Successfully!",
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            backgroundColor: Colors.green.shade700));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        String errorMsg = e.toString().replaceAll(RegExp(r'Exception:\s*'), "");
        if (e is TimeoutException)
          errorMsg = "Update timed out. Check connection.";

        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Error: $errorMsg",
                style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
            backgroundColor: Colors.red.shade700));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _canPop,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        if (_isLoading) return;

        final bool? discard = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text("Discard Changes?",
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
            content: Text("If you go back, any unsaved changes will be lost.",
                style: GoogleFonts.poppins(fontSize: 14)),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text("KEEP EDITING",
                      style: GoogleFonts.poppins(
                          color: _inspectorColor,
                          fontWeight: FontWeight.bold))),
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
          setState(() => _canPop = true); // Prevent infinite loop
          Navigator.pop(context);
        }
      },
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          backgroundColor: const Color(0xFFF3E5F5),
          appBar: AppBar(
            title: Text("Edit Farmer Details",
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold, fontSize: 18)),
            backgroundColor: _inspectorColor,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          body: Stack(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  autovalidateMode: _autoValidateMode,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionHeader("Personal Details"),
                      _buildTextField(
                          "First Name *", _firstNameCtrl, Icons.person,
                          capitalization: TextCapitalization.words,
                          action: TextInputAction.next),
                      const SizedBox(height: 15),
                      _buildTextField(
                          "Middle Name", _middleNameCtrl, Icons.person_outline,
                          required: false,
                          capitalization: TextCapitalization.words,
                          action: TextInputAction.next),
                      const SizedBox(height: 15),
                      _buildTextField(
                          "Last Name *", _lastNameCtrl, Icons.person_outline,
                          capitalization: TextCapitalization.words,
                          action: TextInputAction.next),
                      const SizedBox(height: 15),
                      _buildTextField(
                          "Mobile Number *", _phoneCtrl, Icons.phone,
                          isNumber: true,
                          maxLength: 10,
                          isPhone: true,
                          action: TextInputAction.done),
                      const SizedBox(height: 25),
                      _sectionHeader("Farming Details"),
                      DropdownButtonFormField<String>(
                        value: _farmSize,
                        decoration:
                            _inputDecoration("Farm Size *", Icons.landscape),
                        items: _farmSizeOptions
                            .map((e) => DropdownMenuItem(
                                value: e,
                                child: Text(e,
                                    style: GoogleFonts.poppins(fontSize: 14))))
                            .toList(),
                        onChanged: (v) => setState(() => _farmSize = v),
                        validator: (v) => v == null ? "Required" : null,
                      ),
                      const SizedBox(height: 25),
                      _sectionHeader("Location"),
                      _locationDropdown("State *", _selectedStateId, _stateList,
                          (val) {
                        if (val == null || _selectedStateId == val) return;
                        setState(() {
                          _selectedStateId = val;
                          _selectedDistrictId = null;
                          _selectedTalukaId = null;
                          _selectedVillageId = null;

                          _districtList = LocationService.getDistricts(val);
                          _talukaList = [];
                          _villageList = [];
                        });
                      }),
                      const SizedBox(height: 15),
                      _locationDropdown(
                          "District *", _selectedDistrictId, _districtList,
                          (val) {
                        if (val == null || _selectedDistrictId == val) return;
                        setState(() {
                          _selectedDistrictId = val;
                          _selectedTalukaId = null;
                          _selectedVillageId = null;

                          _talukaList = LocationService.getTalukas(
                              _selectedStateId!, val);
                          _villageList = [];
                        });
                      }),
                      const SizedBox(height: 15),
                      Row(
                        children: [
                          Expanded(
                            child: _locationDropdown(
                                "Taluka", _selectedTalukaId, _talukaList,
                                (val) {
                              if (val == null || _selectedTalukaId == val)
                                return;
                              setState(() {
                                _selectedTalukaId = val;
                                _selectedVillageId = null;

                                _villageList = LocationService.getVillages(
                                    _selectedStateId!,
                                    _selectedDistrictId!,
                                    val);
                              });
                            }),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _locationDropdown(
                                "Village", _selectedVillageId, _villageList,
                                (val) {
                              if (val != null)
                                setState(() => _selectedVillageId = val);
                            }),
                          ),
                        ],
                      ),
                      const SizedBox(height: 25),
                      _sectionHeader("Address"),
                      _buildTextField(
                          "Address / Landmark *", _addr1Ctrl, Icons.home,
                          capitalization: TextCapitalization.sentences,
                          action: TextInputAction.next),
                      const SizedBox(height: 15),
                      _buildTextField("Pincode *", _pinCtrl, Icons.pin_drop,
                          isNumber: true,
                          maxLength: 6,
                          action: TextInputAction.next),
                      const SizedBox(height: 25),
                      _sectionHeader("Bank Details"),
                      _buildTextField(
                          "Bank Name", _bankNameCtrl, Icons.account_balance,
                          required: false,
                          capitalization: TextCapitalization.words,
                          action: TextInputAction.next),
                      const SizedBox(height: 15),
                      _buildTextField(
                          "Account Number", _bankAccCtrl, Icons.numbers,
                          isNumber: true,
                          required: false,
                          maxLength: 18,
                          action: TextInputAction.next),
                      const SizedBox(height: 15),
                      _buildTextField("IFSC Code", _bankIfscCtrl, Icons.qr_code,
                          required: false,
                          isIfsc: true,
                          maxLength: 11,
                          action: TextInputAction.done,
                          inputFormatters: [
                            UpperCaseTextFormatter(),
                            FilteringTextInputFormatter.allow(
                                RegExp(r'[a-zA-Z0-9]'))
                          ]),
                      const SizedBox(height: 40),
                      SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _updateFarmer,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _inspectorColor,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            elevation: 4,
                          ),
                          child: Text("Save Changes",
                              style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                  color: Colors.white)),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
              if (_isLoading)
                Container(
                  color: Colors.black.withOpacity(0.3),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 10)
                          ]),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: _inspectorColor),
                          const SizedBox(height: 16),
                          Text("Updating Farmer...",
                              style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600,
                                  color: _inspectorColor)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
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
          Container(
              width: 4,
              height: 18,
              decoration: BoxDecoration(
                  color: _inspectorColor,
                  borderRadius: BorderRadius.circular(2))),
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
      {bool isNumber = false,
      int? maxLength,
      bool required = true,
      bool isPhone = false,
      bool isIfsc = false,
      TextInputAction action = TextInputAction.done,
      TextCapitalization capitalization = TextCapitalization.none,
      List<TextInputFormatter>? inputFormatters}) {
    List<TextInputFormatter> formatters =
        inputFormatters != null ? List.from(inputFormatters) : [];
    if (isNumber) {
      formatters.add(FilteringTextInputFormatter.digitsOnly);
    }

    return TextFormField(
      controller: controller,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      maxLength: maxLength,
      textInputAction: action,
      textCapitalization: capitalization,
      inputFormatters: formatters,
      style: GoogleFonts.poppins(fontSize: 14, color: Colors.black87),
      validator: (value) {
        if (!required && (value == null || value.trim().isEmpty)) return null;
        if (required && (value == null || value.trim().isEmpty))
          return "$label is required";

        if (isNumber &&
            maxLength != null &&
            value!.trim().length != maxLength) {
          return "Must be exactly $maxLength digits";
        }

        if (isPhone &&
            value != null &&
            !RegExp(r'^[6-9]\d{9}$').hasMatch(value.trim())) {
          return "Invalid Indian mobile number";
        }

        if (label.contains("Pincode") &&
            value != null &&
            !RegExp(r'^[1-9][0-9]{5}$').hasMatch(value.trim())) {
          return "Invalid Pincode";
        }

        if (isIfsc && value != null && value.trim().isNotEmpty) {
          if (value.trim().length != 11)
            return "IFSC must be exactly 11 characters";
          if (!RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$').hasMatch(value.trim()))
            return "Invalid IFSC format";
        }

        return null;
      },
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
                  style: GoogleFonts.poppins(
                      fontSize: 14, color: Colors.black87))))
          .toList(),
      onChanged: items.isEmpty ? null : onChanged,
      validator: (v) => label.contains("*") && v == null ? "Required" : null,
      decoration: _inputDecoration(label, Icons.map),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle:
          GoogleFonts.poppins(color: Colors.grey.shade600, fontSize: 14),
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
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.red.shade400, width: 1.2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }
}

// -----------------------------------------------------------------------------
// 📍 FORMATTER HELPER
// -----------------------------------------------------------------------------
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
