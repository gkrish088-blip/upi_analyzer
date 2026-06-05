import 'package:flutter/material.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  int _selectedRangeIndex = 0;
  int _selectedBarIndex = 3;

  static const List<String> _timeRanges = ['This month', 'Last month', '3 months'];

  static const List<Map<String, dynamic>> _dailyData = [
    {'day': 'Mon', 'amount': 800.0},
    {'day': 'Tue', 'amount': 1200.0},
    {'day': 'Wed', 'amount': 950.0},
    {'day': 'Thu', 'amount': 3200.0},
    {'day': 'Fri', 'amount': 1800.0},
    {'day': 'Sat', 'amount': 2100.0},
    {'day': 'Sun', 'amount': 1500.0},
  ];

  static const String _insightText =
      'You spent ₹18,420 this month — 13% more than last month.\n'
      'Your food spend is the highest category at ₹5,800.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTimeRangeSelector(
                  ranges: _timeRanges,
                  selectedIndex: _selectedRangeIndex,
                  onRangeSelected: (index) {
                    setState(() {
                      _selectedRangeIndex = index;
                    });
                  },
                ),
                const SizedBox(height: 20),
                _buildHistogram(
                  dailyData: _dailyData,
                  selectedBarIndex: _selectedBarIndex,
                  onBarSelected: (index) {
                    setState(() {
                      _selectedBarIndex = index;
                    });
                  },
                ),
                const SizedBox(height: 20),
                _buildAIInsightsCard(insightText: _insightText),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTimeRangeSelector({
    required List<String> ranges,
    required int selectedIndex,
    required Function(int) onRangeSelected,
  }) {
    return Row(
      children: List.generate(ranges.length, (index) {
        final isSelected = index == selectedIndex;
        return Padding(
          padding: EdgeInsets.only(right: index < ranges.length - 1 ? 24 : 0),
          child: GestureDetector(
            onTap: () => onRangeSelected(index),
            behavior: HitTestBehavior.opaque,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  ranges[index],
                  style: TextStyle(
                    color: isSelected ? Colors.white : const Color(0xFF888888),
                    fontSize: 14,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 2,
                  width: _textWidth(ranges[index], isSelected),
                  color: isSelected
                      ? const Color(0xFF7B61FF)
                      : Colors.transparent,
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  // Returns an approximate fixed width for the underline so it sits snugly
  // under the label without measuring the rendered text at build time.
  double _textWidth(String label, bool isSelected) {
    final base = label.length * 7.5;
    return isSelected ? base : 0;
  }

  Widget _buildHistogram({
    required List<Map<String, dynamic>> dailyData,
    required int selectedBarIndex,
    required Function(int) onBarSelected,
  }) {
    const double maxHeight = 200;
    final double maxAmount = dailyData
        .map((e) => e['amount'] as double)
        .reduce((a, b) => a > b ? a : b);

    return Container(
      height: maxHeight + 28, // extra room for labels
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(dailyData.length, (index) {
          final item = dailyData[index];
          final amount = item['amount'] as double;
          final barHeight = (amount / maxAmount) * maxHeight;
          final isSelected = index == selectedBarIndex;

          return GestureDetector(
            onTap: () => onBarSelected(index),
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: 38,
              height: maxHeight + 28,
              child: Column(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        width: 38,
                        height: barHeight,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF7B61FF)
                              : const Color(0xFF7B61FF).withValues(alpha: 0.3),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(6),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item['day'] as String,
                    style: const TextStyle(
                      color: Color(0xFF888888),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildAIInsightsCard({required String insightText}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF7B61FF).withValues(alpha: 0.3),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome, size: 16, color: Color(0xFF7B61FF)),
              SizedBox(width: 8),
              Text(
                'AI summary',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            insightText,
            style: const TextStyle(
              color: Color(0xFF888888),
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
