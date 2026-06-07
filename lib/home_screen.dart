// ─────────────────────────────────────────────────────────────────────────────
// HOW BLOC CONNECTS TO THE UI
// ─────────────────────────────────────────────────────────────────────────────
//
// BlocBuilder rebuilds its child whenever the BLoC emits a new state — it's
// like a StreamBuilder but specifically wired for BLoC. Think of it like
// React's useSelector: the widget re-renders only when the relevant slice of
// state changes.
//
// BlocBuilder<TransactionBloc, TransactionState> means: "watch TransactionBloc,
// rebuild whenever its TransactionState changes".
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'settings_drawer.dart';
import 'bloc/transaction_bloc.dart';
import 'bloc/transaction_state.dart';
import 'bloc/transaction_event.dart';
import 'models/transaction_models.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      drawer: const SettingsDrawer(),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
        leading: Builder(
          builder: (context) => GestureDetector(
            onTap: () => Scaffold.of(context).openDrawer(),
            child: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.menu, color: Colors.white, size: 20),
            ),
          ),
        ),
        title: const Text(
          'Smart Insights',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync, color: Color(0xFF7B61FF)),
            onPressed: () {
              context.read<TransactionBloc>().add(const TransactionSyncRequested());
            },
          ),
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            color: const Color(0xFF888888),
            onPressed: () {},
          ),
        ],
      ),
      body: BlocBuilder<TransactionBloc, TransactionState>(
        builder: (context, state) {
          if (state is TransactionLoading || state is TransactionInitial) {
            return const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF7B61FF),
              ),
            );
          }

          if (state is TransactionPermissionDenied) {
            return _buildPermissionPrompt(context);
          }

          if (state is TransactionError) {
            return Center(
              child: Text(
                state.message,
                style: const TextStyle(color: Colors.red),
              ),
            );
          }

          if (state is TransactionLoaded) {
            return _buildHomeContent(context, state);
          }

          return const SizedBox();
        },
      ),
    );
  }

  Widget _buildPermissionPrompt(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.sms_outlined, size: 64, color: Color(0xFF7B61FF)),
          const SizedBox(height: 16),
          const Text(
            'SMS Permission Required',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Grant SMS access to track your UPI transactions',
            style: TextStyle(color: Color(0xFF888888), fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7B61FF),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
            ),
            onPressed: () {
              context.read<TransactionBloc>().add(const TransactionSyncRequested());
            },
            child: const Text(
              'Grant Permission',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeContent(BuildContext context, TransactionLoaded state) {
    return RefreshIndicator(
      color: const Color(0xFF7B61FF),
      backgroundColor: const Color(0xFF1A1A1A),
      onRefresh: () async {
        context.read<TransactionBloc>().add(const TransactionSyncRequested());
        await Future.delayed(const Duration(seconds: 2));
      },
      child: SingleChildScrollView(
        child: Column(
          children: [
            _buildSpendingCard(
              totalSpent: state.totalSpent,
              comparisonAmount: 2140,
              isUp: true,
            ),
            const SizedBox(height: 16),
            _buildIncomeAndSavingsRow(
              income: state.totalIncome,
              incomeTag: 'credited',
              savingsRate: state.savingsRate,
              savingsTag: state.savingsRate >= 20 ? 'on track' : 'low',
            ),
            const SizedBox(height: 16),
            _buildDonutChartCard(
              month: _monthName(state.selectedMonth),
              categories: state.spendingByCategory.entries.map((entry) {
                return {
                  'name': entry.key.name,
                  'amount': entry.value.toStringAsFixed(0),
                  'color': _categoryColor(entry.key),
                };
              }).toList(),
            ),
            _buildRecentTransactions(
              transactions: state.recentTransactions.map((t) {
                return {
                  'time': t.formattedDate,
                  'category': t.category.name,
                  'amount': t.amount,
                  'isDebit': t.isDebit,
                  'upiRef': t.upiRef ?? 'UPI Transaction',
                };
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Color _categoryColor(TransactionCategory category) {
    switch (category) {
      case TransactionCategory.food:
        return const Color(0xFF7B61FF);
      case TransactionCategory.transport:
        return const Color(0xFF4CAF50);
      case TransactionCategory.shopping:
        return const Color(0xFFFF9800);
      case TransactionCategory.bills:
        return const Color(0xFFE91E63);
      case TransactionCategory.entertainment:
        return const Color(0xFF00BCD4);
      case TransactionCategory.transfer:
        return const Color(0xFF2196F3);
      case TransactionCategory.other:
        return const Color(0xFF888888);
    }
  }

  String _monthName(int month) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return months[month - 1];
  }
}

Widget _buildSpendingCard({
  required double totalSpent,
  required double comparisonAmount,
  required bool isUp,
}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: const Color(0xFFEFEAFF),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Total spent this month",
          style: TextStyle(color: Colors.black, fontSize: 14),
        ),
        const SizedBox(height: 8),

        Text(
          "₹${totalSpent.toStringAsFixed(0)}",
          style: const TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 8),

        Text(
          "${isUp ? '↑' : '↓'} ₹${comparisonAmount.toStringAsFixed(0)} vs last month",
          style: const TextStyle(color: Colors.deepPurple),
        ),
      ],
    ),
  );
}

Widget _buildIncomeAndSavingsRow({
  required double income,
  required double savingsRate,
  required String incomeTag,
  required String savingsTag,
}) {
  return Row(
    children: [
      Expanded(
        child: _buildSmallCard(
          title: "Income",
          value: income.toStringAsFixed(0),
          tag: incomeTag,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _buildSmallCard(
          title: "Savings Rate",
          value: '${savingsRate.toStringAsFixed(1)}%',
          tag: savingsTag,
        ),
      ),
    ],
  );
}

Widget _buildSmallCard({
  required String title,
  required String value,
  required String tag,
}) {
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF1F1F1F),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title),

        const SizedBox(height: 8),

        Text(
          value,
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),

        const SizedBox(height: 8),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.green.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(tag, style: TextStyle(color: Colors.green.shade900)),
        ),
      ],
    ),
  );
}

Widget _buildDonutChartCard({
  required String month,
  required List<Map<String, dynamic>> categories,
}) {
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF1A1A1A),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: [
        // LEFT: Donut chart placeholder
        SizedBox(
          width: 100,
          height: 100,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // placeholder circle — we'll replace with fl_chart later
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF7B61FF), width: 12),
                ),
              ),
              Text(
                month,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(width: 16),

        // RIGHT: Category legend
        Expanded(
          child: Column(
            children: categories.map((category) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    // colored dot
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: category['color'] as Color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // category name
                    Text(
                      category['name'] as String,
                      style: const TextStyle(
                        color: Color(0xFF888888),
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    // amount
                    Text(
                      '₹${category['amount']}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    ),
  );
}

IconData _getCategoryIcon(String category) {
  switch (category) {
    case 'Food':
      return Icons.restaurant_outlined;
    case 'Transport':
      return Icons.directions_bus_outlined;
    case 'Bills':
      return Icons.bolt_outlined;
    case 'Shopping':
      return Icons.shopping_bag_outlined;
    default:
      return Icons.arrow_downward_outlined;
  }
}

Color _getCategoryColor(String category) {
  switch (category) {
    case 'Food':
      return const Color(0xFF7B61FF);
    case 'Transport':
      return const Color(0xFF4CAF50);
    case 'Bills':
      return const Color(0xFFE91E63);
    case 'Shopping':
      return const Color(0xFFFF9800);
    default:
      return const Color(0xFF888888);
  }
}

Widget _buildRecentTransactions({
  required List<Map<String, dynamic>> transactions,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'RECENT',
        style: TextStyle(
          color: Color(0xFF888888),
          fontSize: 12,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w500,
        ),
      ),
      const SizedBox(height: 12),
      Column(
        children: transactions.map((transaction) {
          final String category = transaction['category'] as String;
          final bool isDebit = transaction['isDebit'] as bool;
          final Color categoryColor = _getCategoryColor(category);

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                // icon circle
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: categoryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _getCategoryIcon(category),
                    color: categoryColor,
                    size: 20,
                  ),
                ),

                const SizedBox(width: 12),

                // time + category + upi ref
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${transaction['time']} · $category',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        transaction['upiRef'] as String,
                        style: const TextStyle(
                          color: Color(0xFF888888),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),

                // amount
                Text(
                  '${isDebit ? '-' : '+'}₹${transaction['amount']}',
                  style: TextStyle(
                    color: isDebit
                        ? const Color(0xFFFF5252)
                        : const Color(0xFF4CAF50),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    ],
  );
}
