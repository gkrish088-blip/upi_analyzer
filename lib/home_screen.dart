import 'package:flutter/material.dart';
import 'settings_drawer.dart';

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
            icon: const Icon(Icons.notifications_outlined),
            color: const Color(0xFF888888),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildSpendingCard(),
            const SizedBox(height: 16),
            _buildIncomeAndSavingsRow(
              income: 2345,
              incomeTag: "credited",
              savingsRate: 23,
              savingsTag: "on  track",
            ),
            const SizedBox(height: 16),
            _buildDonutChartCard(
              month: 'June',
              categories: [
                {
                  'name': 'Food',
                  'amount': 5800,
                  'color': const Color(0xFF7B61FF),
                },
                {
                  'name': 'Transport',
                  'amount': 3200,
                  'color': const Color(0xFF4CAF50),
                },
                {
                  'name': 'Shopping',
                  'amount': 2500,
                  'color': const Color(0xFFFF9800),
                },
                {
                  'name': 'Bills',
                  'amount': 4200,
                  'color': const Color(0xFFE91E63),
                },
                {
                  'name': 'Other',
                  'amount': 2720,
                  'color': const Color(0xFF888888),
                },
              ],
            ),
            _buildRecentTransactions(
              transactions: [
                {
                  'time': 'Today, 1:34 PM',
                  'category': 'Food',
                  'amount': 340,
                  'isDebit': true,
                  'upiRef': 'UPI Ref: 2345678',
                },
                {
                  'time': 'Today, 10:12 AM',
                  'category': 'Transport',
                  'amount': 180,
                  'isDebit': true,
                  'upiRef': 'UPI Ref: 2345600',
                },
                {
                  'time': 'Jun 1',
                  'category': 'Income',
                  'amount': 52000,
                  'isDebit': false,
                  'upiRef': 'UPI Ref: 2300001',
                },
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Widget _buildSpendingCard() {
  final double totalSpent = 34567;
  final double difference_with_last_month = 4356;
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
        Text(
          "Total spent this month",
          style: TextStyle(color: Colors.black, fontSize: 14),
        ),
        SizedBox(height: 8),

        Text(
          "₹$totalSpent",
          style: TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        SizedBox(height: 8),

        Text(
          "↑ ₹$difference_with_last_month vs last month",
          style: TextStyle(color: Colors.deepPurple),
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
          value: "$income",
          tag: "$incomeTag",
        ),
      ),
      SizedBox(width: 12),
      Expanded(
        child: _buildSmallCard(
          title: "Savings Rate",
          value: "$savingsRate%",
          tag: "$savingsTag",
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

        SizedBox(height: 8),

        Text(
          value,
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),

        SizedBox(height: 8),

        Container(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                    color: categoryColor.withOpacity(0.1),
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
