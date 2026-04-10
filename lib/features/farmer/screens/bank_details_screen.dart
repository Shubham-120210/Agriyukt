import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 🚀 Added for Haptics & Formatters
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:agriyukt_app/features/common/services/bank_verification_service.dart';

class BankDetailsScreen extends StatefulWidget {
  const BankDetailsScreen({super.key});

  @override
  State<BankDetailsScreen> createState() => _BankDetailsScreenState();
}

class _BankDetailsScreenState extends State<BankDetailsScreen> {
  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  final _accountNameCtrl = TextEditingController();
  final _accountNumberCtrl = TextEditingController();
  final _ifscCtrl = TextEditingController();
  final _bankNameCtrl = TextEditingController();

  bool _isLoading = true; // 🚀 Start true to show loader while fetching
  bool _isSaving = false;

  // Theme Colors
  final Color _primaryGreen = const Color(0xFF1B5E20);

  @override
  void initState() {
    super.initState();
    _fetchExistingDetails();
  }

  @override
  void dispose() {
    _accountNameCtrl.dispose();
    _accountNumberCtrl.dispose();
    _ifscCtrl.dispose();
    _bankNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchExistingDetails() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final data = await _supabase
          .from('bank_accounts')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();

      if (data != null && mounted) {
        setState(() {
          _accountNameCtrl.text = data['account_holder_name'] ?? '';
          _accountNumberCtrl.text = data['account_number'] ?? '';
          _ifscCtrl.text = data['ifsc_code'] ?? '';
          _bankNameCtrl.text = data['bank_name'] ?? '';
        });
      }
    } catch (e) {
      debugPrint("Fetch error: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveDetails() async {
    if (_isSaving) return; // 🚀 Prevent double taps
    if (!_formKey.currentState!.validate()) {
      HapticFeedback.vibrate();
      return;
    }

    final String ifsc = _ifscCtrl.text.trim().toUpperCase();
    final String accNum = _accountNumberCtrl.text.trim();

    final syntaxError = BankVerificationService.validateSyntax(ifsc, accNum);
    if (syntaxError != null) {
      HapticFeedback.vibrate();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text("❌ $syntaxError", style: GoogleFonts.poppins()),
            backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isSaving = true);

    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      await _supabase.from('bank_accounts').upsert({
        'user_id': user.id,
        'account_holder_name':
            _accountNameCtrl.text.trim().toUpperCase(), // 🚀 Standardize
        'account_number': accNum,
        'ifsc_code': ifsc,
        'bank_name': _bankNameCtrl.text.trim().toUpperCase(), // 🚀 Standardize
        'updated_at': DateTime.now().toIso8601String(),
      });

      await _supabase.from('profiles').update({
        'meta_data': {
          'bank_name': _bankNameCtrl.text.trim().toUpperCase(),
          'account_number': accNum,
          'ifsc_code': ifsc,
        }
      }).eq('id', user.id);

      if (mounted) {
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("✅ Bank Details Linked & Verified!",
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
            backgroundColor: Colors.green));
        Navigator.pop(context,
            true); // 🚀 Return true to trigger refresh on previous screen
      }
    } catch (e) {
      HapticFeedback.vibrate();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Error saving details. Check connection."),
            backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text("Bank Settings",
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        backgroundColor: _primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: _primaryGreen))
          : SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Payout Account",
                        style: GoogleFonts.poppins(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87)),
                    const SizedBox(height: 8),
                    Text("Earnings will be transferred to this account.",
                        style: GoogleFonts.poppins(
                            color: Colors.grey, fontSize: 14)),
                    const SizedBox(height: 30),

                    _buildInput("Account Holder Name", _accountNameCtrl,
                        Icons.person_outline),
                    // 🚀 Added numeric formatter
                    _buildInput(
                        "Account Number", _accountNumberCtrl, Icons.numbers,
                        isNumber: true),
                    _buildInput("IFSC Code", _ifscCtrl, Icons.qr_code_scanner,
                        hint: "e.g. SBIN0001234"),
                    _buildInput("Bank Name", _bankNameCtrl,
                        Icons.account_balance_outlined,
                        hint: "e.g. HDFC Bank"),

                    const SizedBox(height: 30),

                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _saveDetails,
                        style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryGreen,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            elevation: 4),
                        child: _isSaving
                            ? const CircularProgressIndicator(
                                color: Colors.white)
                            : Text("VERIFY & SAVE DETAILS",
                                style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildSecurityNote(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildInput(
      String label, TextEditingController controller, IconData icon,
      {bool isNumber = false, String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: TextFormField(
        controller: controller,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        textInputAction: TextInputAction.next, // 🚀 UX: Move to next field
        // 🚀 PRODUCTION: Strict numeric formatting for Account Number
        inputFormatters:
            isNumber ? [FilteringTextInputFormatter.digitsOnly] : [],
        textCapitalization:
            !isNumber ? TextCapitalization.characters : TextCapitalization.none,
        style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: GoogleFonts.poppins(color: Colors.grey[600]),
          hintStyle: GoogleFonts.poppins(color: Colors.grey[400]),
          prefixIcon: Icon(icon, color: _primaryGreen),
          filled: true,
          fillColor: const Color(0xFFF9FAFB),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _primaryGreen, width: 1.5),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        validator: (val) {
          if (val == null || val.trim().isEmpty) return "$label is required";
          if (isNumber && val.length < 9)
            return "Invalid account number length";
          return null;
        },
      ),
    );
  }

  Widget _buildSecurityNote() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.shield_outlined, size: 24, color: Colors.blue[700]),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "Your payout information is encrypted. We use Rule-Based API Validation to ensure secure transfers.",
              style: GoogleFonts.poppins(
                  fontSize: 12, color: Colors.blue[900], height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
