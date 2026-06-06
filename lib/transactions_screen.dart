import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'bloc/transaction_bloc.dart';
import 'bloc/transaction_state.dart';
import 'bloc/transaction_event.dart';
import 'models/transaction_models.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  static const List<String> _filters = [
    'All',
    'Food',
    'Transport',
    'Shopping',
    'Bills',
    'Entertainment',
    'Transfer',
    'Other',
  ];

  static const List<TransactionCategory?> _filterCategories = [
    null,
    TransactionCategory.food,
    TransactionCategory.transport,
    TransactionCategory.shopping,
    TransactionCategory.bills,
    TransactionCategory.entertainment,
    TransactionCategory.transfer,
    TransactionCategory.other,
  ];

  int _getFilterIndex(TransactionCategory? category) {
    if (category == null) return 0;
    return _filterCategories.indexOf(category).clamp(0, _filterCategories.length - 1);
  }

  TransactionCategory? _indexToCategory(int index) {
    return _filterCategories[index];
  }

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
      body: BlocBuilder<TransactionBloc, TransactionState>(
        builder: (context, state) {
          if (state is TransactionLoading || state is TransactionInitial) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF7B61FF)),
            );
          }
          if (state is TransactionLoaded) {
            return _buildTransactionsContent(context, state);
          }
          return const Center(
            child: Text('No data', style: TextStyle(color: Color(0xFF888888))),
          );
        },
      ),
    );
  }

  Widget _buildTransactionsContent(BuildContext context, TransactionLoaded state) {
    if (state.filteredTransactions.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined,
                size: 64, color: Color(0xFF888888)),
            SizedBox(height: 16),
            Text('No transactions found',
                style: TextStyle(color: Color(0xFF888888), fontSize: 16)),
          ],
        ),
      );
    }

    final Map<String, List<Transaction>> grouped = {};
    for (final t in state.filteredTransactions) {
      final label = t.formattedDate.toUpperCase();
      grouped.putIfAbsent(label, () => []).add(t);
    }

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSearchBar(),
            const SizedBox(height: 12),
            _buildDateRangeRow(context, state),
            const SizedBox(height: 12),
            _buildFilterChips(
              filters: _filters,
              selectedIndex: _getFilterIndex(state.activeFilter),
              onFilterSelected: (index) {
                final category = _indexToCategory(index);
                context.read<TransactionBloc>().add(
                      TransactionFilterChanged(category),
                    );
              },
            ),
            const SizedBox(height: 16),
            ...grouped.entries.map((entry) => Column(
                  children: [
                    _buildTransactionGroup(
                      label: entry.key,
                      transactions: entry.value
                          .map((t) => {
                                'merchant': t.merchant ?? 'UPI Transaction',
                                'upiRef': t.upiRef ?? 'UPI Transaction',
                                'category': t.category.name,
                                'amount': t.amount,
                                'isDebit': t.isDebit,
                                'time':
                                    '${t.timestamp.hour.toString().padLeft(2, '0')}:${t.timestamp.minute.toString().padLeft(2, '0')}',
                              })
                          .toList(),
                    ),
                    const SizedBox(height: 16),
                  ],
                )),
          ],
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

  Widget _buildDateRangeRow(BuildContext context, TransactionLoaded state) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildDateChip(context, 'All time', null, null, state),
          const SizedBox(width: 8),
          _buildDateChip(
            context, 'This month',
            DateTime(DateTime.now().year, DateTime.now().month, 1),
            DateTime(DateTime.now().year, DateTime.now().month + 1, 1),
            state,
          ),
          const SizedBox(width: 8),
          _buildDateChip(
            context, 'Last month',
            DateTime(DateTime.now().year, DateTime.now().month - 1, 1),
            DateTime(DateTime.now().year, DateTime.now().month, 1),
            state,
          ),
          const SizedBox(width: 8),
          _buildDateChip(
            context, '3 months',
            DateTime(DateTime.now().year, DateTime.now().month - 3, 1),
            DateTime.now(),
            state,
          ),
          const SizedBox(width: 8),
          _buildDateChip(
            context, '6 months',
            DateTime(DateTime.now().year, DateTime.now().month - 6, 1),
            DateTime.now(),
            state,
          ),
          const SizedBox(width: 8),
          _buildDateChip(
            context, 'This year',
            DateTime(DateTime.now().year, 1, 1),
            DateTime.now(),
            state,
          ),
        ],
      ),
    );
  }

  Widget _buildDateChip(
    BuildContext context,
    String label,
    DateTime? start,
    DateTime? end,
    TransactionLoaded state,
  ) {
    final isSelected = state.dateRangeLabel == label;
    return GestureDetector(
      onTap: () {
        if (start == null || end == null) {
          // "All time" — reload all transactions
          context.read<TransactionBloc>().add(
            TransactionLoadRequested(
              year: DateTime.now().year,
              month: DateTime.now().month,
            ),
          );
        } else {
          context.read<TransactionBloc>().add(
            TransactionDateRangeChanged(
              start: start,
              end: end,
              label: label,
            ),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF7B61FF)
              : const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF7B61FF)
                : const Color(0xFF2A2A2A),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF888888),
            fontSize: 13,
          ),
        ),
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
    final amount = (transaction['amount'] as num).toStringAsFixed(0);
    final color = _getCategoryColor(category);
    final displayCategory = category.isEmpty
        ? category
        : '${category[0].toUpperCase()}${category.substring(1)}';

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
                  displayCategory,
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
      case 'food':
        return Icons.restaurant;
      case 'transport':
        return Icons.directions_car;
      case 'shopping':
        return Icons.shopping_bag;
      case 'bills':
        return Icons.receipt_long;
      case 'entertainment':
        return Icons.movie;
      case 'transfer':
        return Icons.swap_horiz;
      default:
        return Icons.category;
    }
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'food':
        return const Color(0xFF7B61FF);
      case 'transport':
        return const Color(0xFF4CAF50);
      case 'shopping':
        return const Color(0xFFFF9800);
      case 'bills':
        return const Color(0xFFE91E63);
      case 'entertainment':
        return const Color(0xFF00BCD4);
      case 'transfer':
        return const Color(0xFF2196F3);
      default:
        return const Color(0xFF888888);
    }
  }
}
