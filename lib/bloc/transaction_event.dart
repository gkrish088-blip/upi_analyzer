import 'package:equatable/equatable.dart';

import '../models/transaction_models.dart';

// ─── Equatable ────────────────────────────────────────────────────────────────
//
// Equatable makes == comparison work on objects by comparing their fields
// instead of their identity. Without it, two TransactionEvent instances
// would never be equal even if they have the exact same data — Dart compares
// objects by reference by default (the same way `{} == {}` is false in JS
// unless you do a deep comparison). The BLoC package uses == under the hood
// to decide whether an incoming event is a duplicate, so every event needs
// to declare its fields in `props` for that comparison to be meaningful.

// ─── Base class ───────────────────────────────────────────────────────────────
//
// Every event in this app "is a" TransactionEvent. The BLoC only knows how
// to react to TransactionEvent — this is the shared contract, similar to how
// every Redux action has a `type` field, or every Express middleware receives
// a `req`.
abstract class TransactionEvent extends Equatable {
  const TransactionEvent();

  @override
  List<Object?> get props => [];
}

// ─── Events ───────────────────────────────────────────────────────────────────
//
// Events are things that HAPPEN — not things the UI wants to render. Think of
// them as "user did X" or "app did Y", the same way a Redux action describes
// an occurrence ("ADD_TODO") rather than the resulting screen.

/// Fired when: the user opens the app for the first time, or pulls down to
/// refresh the transactions list.
///
/// Carries: nothing — it's just a signal "go fetch fresh SMS and sync them".
class TransactionSyncRequested extends TransactionEvent {
  const TransactionSyncRequested();

  @override
  List<Object?> get props => [];
}

/// Fired when: a screen that shows transactions first loads, or the user
/// switches the selected month (e.g. via a month picker).
///
/// Carries: the year and month to load transactions for, so the BLoC knows
/// exactly which slice of data to fetch from the database.
class TransactionLoadRequested extends TransactionEvent {
  final int year;
  final int month;

  const TransactionLoadRequested({required this.year, required this.month});

  @override
  List<Object?> get props => [year, month];
}

/// Fired when: the user swipes/taps to delete a single transaction from
/// the list.
///
/// Carries: the id of the transaction to remove, so the BLoC can tell the
/// repository exactly which row to delete.
class TransactionDeleteRequested extends TransactionEvent {
  final String transactionId;

  const TransactionDeleteRequested(this.transactionId);

  @override
  List<Object?> get props => [transactionId];
}

/// Fired when: the user taps "Clear all data" in the settings screen.
///
/// Carries: nothing — it's a blanket "wipe everything" signal.
class TransactionAllDeleteRequested extends TransactionEvent {
  const TransactionAllDeleteRequested();

  @override
  List<Object?> get props => [];
}

/// Fired when: the user taps a category filter chip on the transactions
/// screen (e.g. "Food", "Bills", or "All").
///
/// Carries: the category to filter by. `null` means "show all categories" —
/// i.e. the user tapped the "All" chip / cleared the filter.
class TransactionFilterChanged extends TransactionEvent {
  final TransactionCategory? category;

  const TransactionFilterChanged(this.category);

  @override
  List<Object?> get props => [category];
}

/// Fired when: the user selects a custom date range, or picks a specific
/// month/year or quick-range chip (e.g. "Last 3 months") on the
/// Transactions screen.
///
/// Carries: the inclusive/exclusive bounds to filter by, plus a
/// human-readable [label] (e.g. "Feb 2026", "All time", "Last 3 months")
/// so the UI can show which range is currently active.
class TransactionDateRangeChanged extends TransactionEvent {
  final DateTime start;
  final DateTime end;
  final String label;

  const TransactionDateRangeChanged({
    required this.start,
    required this.end,
    required this.label,
  });

  @override
  List<Object?> get props => [start, end, label];
}
