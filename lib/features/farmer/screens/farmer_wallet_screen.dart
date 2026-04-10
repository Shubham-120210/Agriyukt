import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

// ✅ LOCALIZATION IMPORT
import 'package:agriyukt_app/features/farmer/farmer_translations.dart';
import 'package:agriyukt_app/core/providers/language_provider.dart';

// SCREEN IMPORTS
import 'package:agriyukt_app/features/farmer/screens/bank_details_screen.dart';
import 'package:agriyukt_app/features/farmer/screens/withdrawal_screen.dart';

class FarmerWalletScreen extends StatelessWidget {
  const FarmerWalletScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final userId = Supabase.instance.client.auth.currentUser!.id;

    // ✅ WRAP IN CONSUMER: Forces instant rebuild on language change
    return Consumer<LanguageProvider>(
      builder: (context, languageProvider, child) {
        // Helper for localized text
        String text(String key) => FarmerText.get(context, key);

        return Scaffold(
          backgroundColor: const Color(0xFFF5F7FA),
          appBar: AppBar(
            title: Text(text('wallet'), // ✅ "My Wallet"
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
            backgroundColor: const Color(0xFF1B5E20),
            foregroundColor: Colors.white,
            elevation: 0,
            actions: [
              IconButton(
                icon: const Icon(Icons.account_balance),
                tooltip: text('bank_settings'), // ✅ "Bank Settings"
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const BankDetailsScreen())),
              )
            ],
          ),
          body: StreamBuilder<List<Map<String, dynamic>>>(
            stream: Supabase.instance.client
                .from('wallets')
                .stream(primaryKey: ['id']).eq('user_id', userId),
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return Center(
                    child: Text(text('wallet_activating'),
                        style: GoogleFonts.poppins(color: Colors.grey)));
              }

              final wallet = snapshot.data!.first;
              final double locked = (wallet['locked_amount'] ?? 0).toDouble();
              final double available =
                  (wallet['available_amount'] ?? 0).toDouble();
              final double total = (wallet['total_earned'] ?? 0).toDouble();

              return SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. MAIN BALANCE CARD
                    _buildMainCard(context, available, locked, text),

                    const SizedBox(height: 25),

                    // 2. STATS ROW
                    Row(
                      children: [
                        Expanded(
                            child: _buildStatBox(
                                text('total_earned'), // ✅ "Total Earnings"
                                "₹${NumberFormat('#,##0').format(total)}",
                                Colors.blue)),
                        const SizedBox(width: 15),
                        Expanded(
                            child: _buildStatBox(
                                text('locked_balance'), // ✅ "Locked Balance"
                                "₹${NumberFormat('#,##0').format(locked)}",
                                Colors.orange)),
                      ],
                    ),

                    const SizedBox(height: 30),
                    Text(text('history'), // ✅ "History"
                        style: GoogleFonts.poppins(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),

                    // 3. TRANSACTION LIST
                    _buildTransactions(userId, text),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildMainCard(BuildContext context, double available, double locked,
      String Function(String) text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.green.withOpacity(0.3),
              blurRadius: 15,
              offset: const Offset(0, 5))
        ],
      ),
      child: Column(
        children: [
          Text(text('available_balance'), // ✅ "Available Balance"
              style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 5),
          Text("₹${NumberFormat('#,##0.00').format(available)}",
              style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: available > 0
                  ? () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              WithdrawalScreen(currentBalance: available)))
                  : null,
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF1B5E20),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              child: Text(text('withdraw_money'), // ✅ "Withdraw Money"
                  style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
            ),
          ),
          if (locked > 0)
            Padding(
              padding: const EdgeInsets.only(top: 15),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock, color: Colors.white70, size: 14),
                  const SizedBox(width: 5),
                  Text(
                      "₹${locked.toStringAsFixed(0)} ${text('locked_in_orders')}", // ✅
                      style: GoogleFonts.poppins(
                          color: Colors.white70, fontSize: 12)),
                ],
              ),
            )
        ],
      ),
    );
  }

  Widget _buildStatBox(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
              color: Colors.grey.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: GoogleFonts.poppins(
                  fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text(label,
              style:
                  GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600])),
        ],
      ),
    );
  }

  Widget _buildTransactions(String userId, String Function(String) text) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('transactions')
          .stream(primaryKey: ['id'])
          .eq('user_id', userId)
          .order('created_at', ascending: false),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
              child: Padding(
                  padding: const EdgeInsets.all(20),
                  child:
                      Text(text('no_transactions'), // ✅ "No transactions yet"
                          style: GoogleFonts.poppins(color: Colors.grey))));
        }
        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: snapshot.data!.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final tx = snapshot.data![i];
            final bool isCredit = tx['type'] == 'credit';
            final bool isLocked = tx['status'] == 'locked';

            return Container(
              color: Colors.white,
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: CircleAvatar(
                  backgroundColor: isLocked
                      ? Colors.orange[50]
                      : (isCredit ? Colors.green[50] : Colors.red[50]),
                  child: Icon(
                    isLocked
                        ? Icons.lock_clock
                        : (isCredit
                            ? Icons.arrow_downward
                            : Icons.arrow_upward),
                    color: isLocked
                        ? Colors.orange
                        : (isCredit ? Colors.green : Colors.red),
                    size: 20,
                  ),
                ),
                title: Text(
                    // Fallback to localized 'Transfer' if description is missing
                    tx['description'] ?? text('transfer'),
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                subtitle: Text(
                    DateFormat('dd MMM, hh:mm a')
                        .format(DateTime.parse(tx['created_at'])),
                    style:
                        GoogleFonts.poppins(fontSize: 12, color: Colors.grey)),
                trailing: Text(
                  "${isCredit ? '+' : '-'} ₹${tx['amount']}",
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      color: isLocked
                          ? Colors.grey
                          : (isCredit ? Colors.green : Colors.red)),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
