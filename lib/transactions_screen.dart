import 'package:flutter/material.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  int _selectedFilterIndex = 0;

  static const List<String> _filters = [
    'All',
    'Food',
    'Transport',
    'Shopping',
    'Bills',
    'Other',
  ];

  static const List<Map<String, dynamic>> _transactionGroups = [
    {
      'label': 'TODAY',
      'transactions': [
        {
          'merchant': 'Swiggy',
          'upiRef': 'UPI Ref: 2345678',
          'category': 'Food',
          'amount': 340,
          'isDebit': true,
          'time': '1:34 PM',
        },
        {
          'merchant': 'Ola',
          'upiRef': 'UPI Ref: 2345600',
          'category': 'Transport',
          'amount': 180,
          'isDebit': true,
          'time': '10:12 AM',
        },
      ],
    },
    {
      'label': 'YESTERDAY',
      'transactions': [
        {
          'merchant': 'BESCOM',
          'upiRef': 'UPI Ref: 2340021',
          'category': 'Bills',
          'amount': 1240,
          'isDebit': true,
          'time': '8:00 AM',
        },
        {
          'merchant': 'Myntra',
          'upiRef': 'UPI Ref: 2339887',
          'category': 'Shopping',
          'amount': 899,
          'isDebit': true,
          'time': '3:22 PM',
        },
        {
          'merchant': 'Rohit (transfer in)',
          'upiRef': 'UPI Ref: 2339001',
          'category': 'Transfer In',
          'amount': 500,
          'isDebit': false,
          'time': '12:05 PM',
        },
      ],
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
        title: const Text(
          'Transactions',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSearchBar(),
              const SizedBox(height: 16),
              _buildFilterChips(
                filters: _filters,
                selectedIndex: _selectedFilterIndex,
                onFilterSelected: (index) {
                  setState(() {
                    _selectedFilterIndex = index;
                  });
                },
              ),
              const SizedBox(height: 16),
              ..._transactionGroups.map((group) => Column(
                    children: [
                      _buildTransactionGroup(
                        label: group['label'] as String,
                        transactions: List<Map<String, dynamic>>.from(
                            group['transactions'] as List),
                      ),
                      const SizedBox(height: 16),
                    ],
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: const Row(
        children: [
          Icon(Icons.search, color: Color(0xFF888888), size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Search merchant, amount...',
              style: TextStyle(
                color: Color(0xFF888888),
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips({
    required List<String> filters,
    required int selectedIndex,
    required Function(int) onFilterSelected,
  }) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(filters.length, (index) {
          final isSelected = index == selectedIndex;
          return Padding(
            padding: EdgeInsets.only(right: index < filters.length - 1 ? 8 : 0),
            child: GestureDetector(
              onTap: () => onFilterSelected(index),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF7B61FF)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  border: isSelected
                      ? null
                      : Border.all(color: const Color(0xFF888888)),
                ),
                child: Text(
                  filters[index],
                  style: TextStyle(
                    color: isSelected
                        ? Colors.white
                        : const Color(0xFF888888),
                    fontSize: 13,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildTransactionGroup({
    required String label,
    required List<Map<String, dynamic>> transactions,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF888888),
            fontSize: 12,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        ...transactions.map((transaction) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildTransactionRow(transaction: transaction),
            )),
      ],
    );
  }

  Widget _buildTransactionRow({required Map<String, dynamic> transaction}) {
    final category = transaction['category'] as String;
    final isDebit = transaction['isDebit'] as bool;
    final amount = transaction['amount'] as int;
    final color = _getCategoryColor(category);

    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            _getCategoryIcon(category),
            color: color,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                transaction['merchant'] as String,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  category,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        Text(
          '${isDebit ? '-' : '+'}₹$amount',
          style: TextStyle(
            color: isDebit
                ? const Color(0xFFFF5252)
                : const Color(0xFF4CAF50),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'Food':
        return Icons.restaurant;
      case 'Transport':
        return Icons.directions_car;
      case 'Shopping':
        return Icons.shopping_bag;
      case 'Bills':
        return Icons.receipt_long;
      case 'Transfer In':
        return Icons.arrow_downward;
      case 'Transfer Out':
        return Icons.arrow_upward;
      default:
        return Icons.category;
    }
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'Food':
        return const Color(0xFF7B61FF);
      case 'Transport':
        return const Color(0xFF4CAF50);
      case 'Shopping':
        return const Color(0xFFFF9800);
      case 'Bills':
        return const Color(0xFFE91E63);
      case 'Transfer In':
        return const Color(0xFF4CAF50);
      case 'Transfer Out':
        return const Color(0xFFFF5252);
      default:
        return const Color(0xFF888888);
    }
  }
}
