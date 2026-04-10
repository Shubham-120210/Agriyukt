import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

// ✅ LOCALIZATION IMPORTS
import 'package:agriyukt_app/features/farmer/farmer_translations.dart';

class WithdrawalScreen extends StatefulWidget {
  final double currentBalance;

  const WithdrawalScreen({super.key, required this.currentBalance});

  @override
  State<WithdrawalScreen> createState() => _WithdrawalScreenState();
}

class _WithdrawalScreenState extends State<WithdrawalScreen> {
  final _amountController = TextEditingController();
  final _supabase = Supabase.instance.client;
  bool _isLoading = false;

  // Hardcoded for demo, usually fetched from DB
  // ⚠️ LOGIC: Keep these in English as per Bank Passbook
  final String _bankName = "State Bank of India (SBI)";
  final String _acNumber = "**** **** 1234";
  final String _ifsc = "SBIN0001234";

  // ✅ Helper for Localized Text (UI Labels Only)
  String _text(String key) => FarmerText.get(context, key);

  Future<void> _processWithdrawal() async {
    final amount = double.tryParse(_amountController.text);

    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_text('invalid_amount') == 'invalid_amount'
              ? 'Invalid Amount'
              : _text('invalid_amount'))));
      return;
    }

    if (amount > widget.currentBalance) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              _text('insufficient_balance') == 'insufficient_balance'
                  ? 'Insufficient Balance'
                  : _text('insufficient_balance'),
              style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.red));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = _supabase.auth.currentUser;
      if (user != null) {
        // 1. Insert Transaction Record (Always English for Audit)
        await _supabase.from('transactions').insert({
          'user_id': user.id,
          'amount': amount,
          'type': 'debit', // Internal system tag
          'description':
              'Withdrawal to $_bankName', // ✅ Keeping Bank Name in English
          'status': 'Pending',
          'created_at': DateTime.now().toIso8601String(),
        });

        // 2. Update Wallet Balance (Logic handled by trigger or manual update)
        // For demo UI only:
        if (mounted) {
          Navigator.pop(context, true); // Return success to refresh wallet
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  "${_text('withdrawal_initiated')}: ₹$amount"), // ✅ "Withdrawal Initiated: ₹500"
              backgroundColor: Colors.green));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text(
            _text('withdraw_money') == 'withdraw_money'
                ? 'Withdraw Money'
                : _text('withdraw_money'),
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1B5E20),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. BALANCE CARD (Localized Label, Numeric Data)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: Colors.green.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 5))
                ],
              ),
              child: Column(
                children: [
                  Text(
                      _text('available_balance') == 'available_balance'
                          ? 'Available Balance'
                          : _text('available_balance'),
                      style: GoogleFonts.poppins(
                          color: Colors.white70, fontSize: 14)),
                  const SizedBox(height: 8),
                  Text(
                      "₹${NumberFormat('#,##0.00').format(widget.currentBalance)}",
                      style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),

            const SizedBox(height: 30),

            // 2. BANK DETAILS (⚠️ STRICTLY ENGLISH AS PER PASBOOK)
            Text(
                _text('transfer_to') == 'transfer_to'
                    ? 'Transfer To'
                    : _text('transfer_to'),
                style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700])),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(10)),
                    child:
                        const Icon(Icons.account_balance, color: Colors.blue),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ✅ Bank Name remains in English (No Translation)
                        Text(_bankName,
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 4),
                        // ✅ Account Number remains Numeric/English
                        Text("A/C: $_acNumber",
                            style: GoogleFonts.poppins(
                                color: Colors.grey[600],
                                fontSize: 13,
                                letterSpacing: 1.0)),
                        Text("IFSC: $_ifsc",
                            style: GoogleFonts.poppins(
                                color: Colors.grey[600], fontSize: 12)),
                      ],
                    ),
                  ),
                  const Icon(Icons.check_circle, color: Colors.green, size: 20),
                ],
              ),
            ),

            const SizedBox(height: 30),

            // 3. INPUT AMOUNT
            Text(
                _text('enter_amount') == 'enter_amount'
                    ? 'Enter Amount'
                    : _text('enter_amount'),
                style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700])),
            const SizedBox(height: 12),
            TextField(
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: GoogleFonts.poppins(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black),
              decoration: InputDecoration(
                prefixText: "₹ ",
                prefixStyle: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black),
                hintText: "0.00",
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              ),
            ),

            const SizedBox(height: 30),

            // 4. ACTION BUTTON
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _processWithdrawal,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1B5E20),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 5,
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                        _text('withdraw_now') == 'withdraw_now'
                            ? 'WITHDRAW NOW'
                            : _text('withdraw_now'), // ✅ Localized Button Text
                        style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
              ),
            ),

            const SizedBox(height: 20),

            Center(
              child: Text("Safe & Secure Payment",
                  style: GoogleFonts.poppins(
                      color: Colors.grey[400],
                      fontSize: 12,
                      fontWeight: FontWeight.w500)),
            )
          ],
        ),
      ),
    );
  }
}
