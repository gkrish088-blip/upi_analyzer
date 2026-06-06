import 'package:equatable/equatable.dart';

import '../models/transaction_models.dart';

// ─── States ───────────────────────────────────────────────────────────────────
//
// A State is a snapshot of "what the UI should show right now". Every time
// the BLoC emits a new state, every widget listening to it rebuilds to match.
// This is the same idea as a Redux store's state tree — the UI is always just
// a function of the current state, never something it mutates directly.
//
// Like events, every state extends Equatable so the BLoC can skip emitting
// (and the UI can skip rebuilding) when the "new" state is identical to the
// old one — e.g. emitting TransactionLoading twice in a row only rebuilds
// the spinner once.

abstract class TransactionState extends Equatable {
  const TransactionState();

  @override
  List<Object?> get props => [];
}

/// The very first state, before the BLoC has done anything.
///
/// Like the blank screen you see for a split second before the app finishes
/// booting up — there's no data yet, and no request is in flight either.
class TransactionInitial extends TransactionState {
  const TransactionInitial();

  @override
  List<Object?> get props => [];
}

/// Data is currently being fetched from the database or synced from SMS.
///
/// The UI should show a loading spinner / shimmer while this state is active.
class TransactionLoading extends TransactionState {
  const TransactionLoading();

  @override
  List<Object?> get props => [];
}

/// Data has been fetched and is ready to display.
///
/// This is the "everything is fine, here's what to draw" state — most of the
/// app's screens (home, transactions list, charts) read from this state.
class TransactionLoaded extends TransactionState {
  /// All transactions for the currently selected month, completely
  /// unfiltered. This is the "source of truth" list that aggregations
  /// (totals, charts) and filtering are derived from.
  final List<Transaction> allTransactions;

  /// The same month's transactions, but narrowed down by [activeFilter].
  /// This is what the Transactions screen actually renders in its list —
  /// when no filter is active it's identical to [allTransactions].
  final List<Transaction> filteredTransactions;

  /// The most recent transactions (newest first, capped at a small limit).
  /// Shown in the "Recent activity" section of the Home screen.
  final List<Transaction> recentTransactions;

  /// Sum of all debit (money-out) transactions for the month.
  /// Shown as the "Total spent" tile on the Home screen.
  final double totalSpent;

  /// Sum of all credit (money-in) transactions for the month.
  /// Shown as the "Total income" tile on the Home screen.
  final double totalIncome;

  /// How much of the month's income was *not* spent, as a percentage
  /// (0–100). Shown as the "Savings rate" tile / progress ring on the
  /// Home screen. Calculated as ((income - spent) / income * 100), clamped
  /// to the 0–100 range so e.g. overspending doesn't show a negative rate.
  final double savingsRate;

  /// Total amount spent per category this month — feeds the donut/pie
  /// chart on the analytics/Home screen (e.g. "Food: ₹5800").
  final Map<TransactionCategory, double> spendingByCategory;

  /// Total amount spent per day-of-week this month — feeds the bar-chart
  /// histogram on the analytics screen (e.g. "Mon: ₹1200").
  final Map<String, double> spendingByDayOfWeek;

  /// The year currently selected for viewing (e.g. 2026). Drives the
  /// month picker / header on the transactions screen and tells the BLoC
  /// which month to reload when the user navigates or refreshes.
  final int selectedYear;

  /// The month currently selected for viewing (1 = January .. 12 = December).
  /// Same role as [selectedYear] — together they identify "which month
  /// am I looking at".
  final int selectedMonth;

  /// The category the user has chosen to filter by on the Transactions
  /// screen. `null` means "no filter" — i.e. show every category. Drives
  /// which filter chip appears highlighted/selected.
  final TransactionCategory? activeFilter;

  /// How many brand-new transactions the most recent sync discovered.
  /// Used to show a "✨ 3 new transactions found" banner/snackbar after
  /// a sync completes. Resets to 0 on a plain reload (no sync involved).
  final int newTransactionCount;

  /// Start of the currently active date-range filter, or `null` when no
  /// date filter is applied (i.e. "All time").
  final DateTime? filterStart;

  /// End of the currently active date-range filter, or `null` when no
  /// date filter is applied (i.e. "All time").
  final DateTime? filterEnd;

  /// Human-readable label for the active date range (e.g. "Jun 2026",
  /// "All time", "Last 3 months"). Drives which date-range chip appears
  /// highlighted/selected on the Transactions screen.
  final String dateRangeLabel;

  const TransactionLoaded({
    required this.allTransactions,
    required this.filteredTransactions,
    required this.recentTransactions,
    required this.totalSpent,
    required this.totalIncome,
    required this.savingsRate,
    required this.spendingByCategory,
    required this.spendingByDayOfWeek,
    required this.selectedYear,
    required this.selectedMonth,
    required this.activeFilter,
    required this.newTransactionCount,
    this.filterStart,
    this.filterEnd,
    this.dateRangeLabel = 'This month',
  });

  // Returns a copy of this state with some fields replaced.
  //
  // Same pattern as Transaction.copyWith: every parameter is nullable, and
  // `??` falls back to the existing value when a field isn't passed in. This
  // lets callers change just one or two fields (e.g. only `activeFilter` and
  // `filteredTransactions` when the user taps a filter chip) without having
  // to re-specify the entire state.
  TransactionLoaded copyWith({
    List<Transaction>? allTransactions,
    List<Transaction>? filteredTransactions,
    List<Transaction>? recentTransactions,
    double? totalSpent,
    double? totalIncome,
    double? savingsRate,
    Map<TransactionCategory, double>? spendingByCategory,
    Map<String, double>? spendingByDayOfWeek,
    int? selectedYear,
    int? selectedMonth,
    TransactionCategory? activeFilter,
    int? newTransactionCount,
    DateTime? filterStart,
    DateTime? filterEnd,
    String? dateRangeLabel,
  }) {
    return TransactionLoaded(
      allTransactions: allTransactions ?? this.allTransactions,
      filteredTransactions: filteredTransactions ?? this.filteredTransactions,
      recentTransactions: recentTransactions ?? this.recentTransactions,
      totalSpent: totalSpent ?? this.totalSpent,
      totalIncome: totalIncome ?? this.totalIncome,
      savingsRate: savingsRate ?? this.savingsRate,
      spendingByCategory: spendingByCategory ?? this.spendingByCategory,
      spendingByDayOfWeek: spendingByDayOfWeek ?? this.spendingByDayOfWeek,
      selectedYear: selectedYear ?? this.selectedYear,
      selectedMonth: selectedMonth ?? this.selectedMonth,
      activeFilter: activeFilter ?? this.activeFilter,
      newTransactionCount: newTransactionCount ?? this.newTransactionCount,
      filterStart: filterStart ?? this.filterStart,
      filterEnd: filterEnd ?? this.filterEnd,
      dateRangeLabel: dateRangeLabel ?? this.dateRangeLabel,
    );
  }

  @override
  List<Object?> get props => [
        allTransactions,
        filteredTransactions,
        recentTransactions,
        totalSpent,
        totalIncome,
        savingsRate,
        spendingByCategory,
        spendingByDayOfWeek,
        selectedYear,
        selectedMonth,
        activeFilter,
        newTransactionCount,
        filterStart,
        filterEnd,
        dateRangeLabel,
      ];
}

/// Something went wrong while syncing, loading, or deleting transactions
/// (e.g. a database error, or an exception thrown while parsing SMS).
///
/// The UI should show an error message / retry button while this is active.
class TransactionError extends TransactionState {
  /// A human-readable description of what went wrong, suitable for showing
  /// directly in an error banner or snackbar.
  final String message;

  const TransactionError(this.message);

  @override
  List<Object?> get props => [message];
}

/// The user hasn't granted SMS read permission, so we can't sync at all.
///
/// The UI should show a friendly "we need SMS access to read your UPI
/// transactions" prompt with a button that asks for the permission again.
class TransactionPermissionDenied extends TransactionState {
  const TransactionPermissionDenied();

  @override
  List<Object?> get props => [];
}
