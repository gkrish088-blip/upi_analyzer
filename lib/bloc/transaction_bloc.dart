// ─────────────────────────────────────────────────────────────────────────────
// WHAT IS BLoC?
// ─────────────────────────────────────────────────────────────────────────────
//
// BLoC stands for "Business Logic Component". It's a pattern for keeping all
// the "thinking" of your app (talking to databases/APIs, deciding what the
// screen should show) completely separate from the widgets that draw pixels
// on screen. The flow looks like this:
//
//   UI fires an Event  ──▶  BLoC receives the Event
//                              │
//                              ▼
//                     does async work (DB reads, API calls, ...)
//                              │
//                              ▼
//                       BLoC emits a new State
//                              │
//                              ▼
//                  UI rebuilds to match the new State
//
// If you've used Redux, this will feel very familiar:
//
//   Action  →  Reducer  →  State          (Redux)
//   Event   →  BLoC      →  State          (this file)
//
// The key vocabulary to internalize:
//   • Events are things that HAPPEN — "the user tapped refresh", "the app
//     just started". They describe what occurred, not what to draw.
//   • States are snapshots of "what the UI should look like right now" —
//     "we're loading", "here's the data", "something broke".
//
// The BLoC's whole job is to sit in the middle: listen for events, run the
// actual business logic (usually by calling into a repository), and emit the
// state that results from that logic. Widgets never call the repository
// directly — they just dispatch events and listen for states. That separation
// is what makes BLoC code easy to test (no widgets needed to test logic) and
// easy to reuse (the same BLoC can back multiple screens).
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter_bloc/flutter_bloc.dart';

import '../repository/transaction_repository.dart';
import 'transaction_event.dart';
import 'transaction_state.dart';

class TransactionBloc extends Bloc<TransactionEvent, TransactionState> {
  // The repository is the BLoC's only window into the outside world — it
  // never talks to the database or SMS service directly. This keeps the BLoC
  // testable (swap in a fake repository in tests) and keeps persistence
  // details out of the business-logic layer entirely.
  final TransactionRepository _repository;

  TransactionBloc({required TransactionRepository repository})
      : _repository = repository,
        super(const TransactionInitial()) {
    // Wiring up event handlers: this tells the BLoC "whenever an event of
    // this exact type comes in, run this method to handle it". It's the BLoC
    // equivalent of `app.post('/sync', handler)` in Express — you're mapping
    // an incoming "request" (event) to the function that knows how to deal
    // with it.
    on<TransactionSyncRequested>(_onSyncRequested);
    on<TransactionLoadRequested>(_onLoadRequested);
    on<TransactionDeleteRequested>(_onDeleteRequested);
    on<TransactionAllDeleteRequested>(_onAllDeleteRequested);
    on<TransactionFilterChanged>(_onFilterChanged);
    on<TransactionDateRangeChanged>(_onDateRangeChanged);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Handler: TransactionSyncRequested
  // ───────────────────────────────────────────────────────────────────────────
  //
  // Triggered by: the user opening the app, or pulling down to refresh the
  // transactions list.
  //
  // What it does, step by step:
  //   1. Immediately tell the UI we're working — emit TransactionLoading so
  //      a spinner appears.
  //   2. Ask the repository to run the full sync pipeline (read SMS, parse,
  //      categorize, dedupe, save to DB).
  //   3. Inspect the SyncResult that comes back:
  //        - no SMS permission?      → emit TransactionPermissionDenied and
  //                                     stop (nothing else can succeed without
  //                                     permission).
  //        - sync failed for another
  //          reason?                 → emit TransactionError with the
  //                                     repository's message and stop.
  //        - sync succeeded?         → reload the freshly-synced data from
  //                                     the DB via _loadAndEmit so the UI
  //                                     shows the latest numbers.
  //
  // Edge cases handled: permission-denied and generic-failure are both
  // surfaced as distinct states so the UI can show the right prompt (a
  // "grant access" button vs. a generic error/retry banner).
  Future<void> _onSyncRequested(
    TransactionSyncRequested event,
    Emitter<TransactionState> emit,
  ) async {
    emit(const TransactionLoading());

    final result = await _repository.syncTransactions();

    if (result.permissionDenied) {
      emit(const TransactionPermissionDenied());
      return;
    }

    if (!result.success) {
      emit(TransactionError(result.errorMessage ?? 'Failed to sync transactions'));
      return;
    }

    await _loadAndEmit(emit, newTransactionCount: result.newTransactionsCount);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Handler: TransactionLoadRequested
  // ───────────────────────────────────────────────────────────────────────────
  //
  // Triggered by: a screen first appearing (e.g. the user opens the
  // Transactions tab), or the user switching to a different month.
  //
  // What it does, step by step:
  //   1. Emit TransactionLoading so the UI shows a spinner while we fetch.
  //   2. Delegate to _loadAndEmit, passing along the year/month the caller
  //      asked for — that helper does the actual DB read + aggregation +
  //      emitting of TransactionLoaded (or TransactionError on failure).
  //
  // This handler stays intentionally thin — _loadAndEmit is shared with the
  // sync and delete handlers so the "fetch + compute + emit" logic lives in
  // exactly one place.
  Future<void> _onLoadRequested(
    TransactionLoadRequested event,
    Emitter<TransactionState> emit,
  ) async {
    emit(const TransactionLoading());
    await _loadAndEmit(emit, year: event.year, month: event.month);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Handler: TransactionDeleteRequested
  // ───────────────────────────────────────────────────────────────────────────
  //
  // Triggered by: the user deleting a single transaction (e.g. swipe-to-
  // delete on the Transactions screen).
  //
  // What it does, step by step:
  //   1. Ask the repository to remove that transaction from the database.
  //   2. If we currently have data loaded (state is TransactionLoaded),
  //      reload using the same year/month that was already on screen, so
  //      the list and all the totals/charts reflect the deletion.
  //   3. If we're not currently in a loaded state (e.g. still loading, or
  //      showing an error), there's nothing meaningful to refresh — we just
  //      let the delete happen silently.
  //
  // Edge cases handled: the whole operation is wrapped in try/catch so a
  // database failure surfaces as TransactionError instead of crashing the
  // app or leaving the BLoC in a stuck state.
  Future<void> _onDeleteRequested(
    TransactionDeleteRequested event,
    Emitter<TransactionState> emit,
  ) async {
    try {
      await _repository.deleteTransaction(event.transactionId);

      final currentState = state;
      if (currentState is TransactionLoaded) {
        await _loadAndEmit(
          emit,
          year: currentState.selectedYear,
          month: currentState.selectedMonth,
        );
      }
    } catch (e) {
      emit(TransactionError(e.toString()));
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Handler: TransactionAllDeleteRequested
  // ───────────────────────────────────────────────────────────────────────────
  //
  // Triggered by: the user tapping "Clear all data" in the settings screen —
  // a destructive, app-wide wipe.
  //
  // What it does, step by step:
  //   1. Emit TransactionLoading so the UI shows a spinner during the wipe.
  //   2. Ask the repository to delete every transaction from the database.
  //   3. Emit a fresh TransactionLoaded with every list empty and every
  //      number zeroed out — there's no need to hit the DB again, we already
  //      know the answer ("nothing").
  //
  // Edge cases handled: wrapped in try/catch so a failed wipe surfaces as
  // TransactionError rather than leaving the UI stuck on the spinner.
  Future<void> _onAllDeleteRequested(
    TransactionAllDeleteRequested event,
    Emitter<TransactionState> emit,
  ) async {
    emit(const TransactionLoading());

    try {
      await _repository.deleteAllTransactions();

      final now = DateTime.now();
      emit(TransactionLoaded(
        allTransactions: const [],
        filteredTransactions: const [],
        recentTransactions: const [],
        totalSpent: 0,
        totalIncome: 0,
        savingsRate: 0,
        spendingByCategory: const {},
        spendingByDayOfWeek: const {},
        selectedYear: now.year,
        selectedMonth: now.month,
        activeFilter: null,
        newTransactionCount: 0,
      ));
    } catch (e) {
      emit(TransactionError(e.toString()));
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Handler: TransactionFilterChanged
  // ───────────────────────────────────────────────────────────────────────────
  //
  // Triggered by: the user tapping a category filter chip on the
  // Transactions screen (e.g. "Food", "Bills", or "All").
  //
  // What it does, step by step:
  //   1. Only makes sense if we already have data loaded — if we're still
  //      loading or showing an error, there's nothing to filter, so we do
  //      nothing.
  //   2. Re-derive `filteredTransactions` from the full `allTransactions`
  //      list already sitting in memory:
  //        - category == null  → no filter, show everything
  //        - category != null  → keep only transactions matching it
  //   3. Emit a copy of the current state with `activeFilter` and
  //      `filteredTransactions` updated.
  //
  // NOTE: this is purely an in-memory operation — filtering doesn't change
  // what's in the database, so there's no repository call and no need to
  // emit TransactionLoading first. The UI updates instantly.
  void _onFilterChanged(
    TransactionFilterChanged event,
    Emitter<TransactionState> emit,
  ) {
    final currentState = state;
    if (currentState is! TransactionLoaded) return;

    final category = event.category;
    final filtered = category == null
        ? currentState.allTransactions
        : currentState.allTransactions
            .where((t) => t.category == category)
            .toList();

    emit(currentState.copyWith(
      activeFilter: category,
      filteredTransactions: filtered,
    ));
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Handler: TransactionDateRangeChanged
  // ───────────────────────────────────────────────────────────────────────────
  //
  // Triggered by: the user picking a date-range chip (e.g. "Last month",
  // "3 months", "This year") on the Transactions screen.
  //
  // What it does, step by step:
  //   1. Only makes sense if we already have data loaded — if we're still
  //      loading or showing an error, there's nothing to refine.
  //   2. Fetch transactions for the selected [start, end) range directly
  //      from the repository (a fresh DB read, not an in-memory filter,
  //      since the range can span well beyond what's already loaded).
  //   3. Recompute every aggregation over that filtered set so the totals/
  //      charts reflect the selected range, not the whole dataset.
  //   4. Emit a copy of the current state with the range-scoped data and
  //      the new [filterStart]/[filterEnd]/[dateRangeLabel], clearing any
  //      active category filter.
  Future<void> _onDateRangeChanged(
    TransactionDateRangeChanged event,
    Emitter<TransactionState> emit,
  ) async {
    // Only works if current state is TransactionLoaded
    if (state is! TransactionLoaded) return;
    final current = state as TransactionLoaded;

    try {
      // Fetch transactions for the selected date range
      final transactions = await _repository.getTransactionsByDateRange(
        event.start,
        event.end,
      );

      // Recompute all aggregations on the filtered set
      final totalSpent = _repository.getTotalSpent(transactions);
      final totalIncome = _repository.getTotalIncome(transactions);
      final savingsRate = totalIncome == 0
          ? 0.0
          : ((totalIncome - totalSpent) / totalIncome * 100)
              .clamp(0.0, 100.0)
              .toDouble();

      emit(current.copyWith(
        allTransactions: transactions,
        filteredTransactions: transactions,
        recentTransactions: _repository.getRecentTransactions(transactions),
        totalSpent: totalSpent,
        totalIncome: totalIncome,
        savingsRate: savingsRate,
        spendingByCategory: _repository.getSpendingByCategory(transactions),
        spendingByDayOfWeek: _repository.getSpendingByDayOfWeek(transactions),
        activeFilter: null,
        filterStart: event.start,
        filterEnd: event.end,
        dateRangeLabel: event.label,
      ));
    } catch (e) {
      emit(TransactionError(e.toString()));
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Helper: _loadAndEmit
  // ───────────────────────────────────────────────────────────────────────────
  //
  // Shared by the sync, load, and delete handlers — they all ultimately need
  // to do the same thing: "fetch this month's transactions, crunch the
  // numbers, and emit a TransactionLoaded with the results". Centralizing it
  // here means that logic exists in exactly one place.
  //
  // Step by step:
  //   a. Work out which year/month to load:
  //        - explicit [year]/[month] passed in?      → use those
  //        - otherwise, are we already showing data?  → keep using whatever
  //                                                      month was on screen
  //        - otherwise (very first load)              → default to "now"
  //   b. Fetch that month's transactions from the repository (which reads
  //      from the database).
  //   c. Run every aggregation the repository exposes over that list:
  //      total spent, total income, savings rate, spending-by-category,
  //      spending-by-day-of-week, and the 5 most recent transactions.
  //      Savings rate is `((income - spent) / income) * 100`, guarded
  //      against divide-by-zero (no income this month → 0%) and clamped to
  //      the 0–100 range so e.g. a month where you spent more than you
  //      earned still shows a sensible percentage rather than a negative one.
  //   d. Re-apply whatever category filter was already active (if any), so
  //      switching months or syncing doesn't silently reset the user's
  //      filter choice.
  //   e. Emit a single TransactionLoaded carrying all of the above.
  //
  // Edge cases handled: the entire method runs inside a try/catch — any DB
  // or computation failure surfaces as TransactionError instead of crashing.
  Future<void> _loadAndEmit(
    Emitter<TransactionState> emit, {
    int? year,
    int? month,
    int newTransactionCount = 0,
  }) async {
    try {
      final currentState = state;

      final int targetYear;
      final int targetMonth;
      if (year != null && month != null) {
        targetYear = year;
        targetMonth = month;
      } else if (currentState is TransactionLoaded) {
        targetYear = currentState.selectedYear;
        targetMonth = currentState.selectedMonth;
      } else {
        final now = DateTime.now();
        targetYear = now.year;
        targetMonth = now.month;
      }

      // Load all transactions — UI will handle date filtering
      final transactions = await _repository.getAllTransactions();

      final totalSpent = _repository.getTotalSpent(transactions);
      final totalIncome = _repository.getTotalIncome(transactions);

      final savingsRate = totalIncome == 0
          ? 0.0
          : (((totalIncome - totalSpent) / totalIncome) * 100).clamp(0.0, 100.0);

      final spendingByCategory = _repository.getSpendingByCategory(transactions);
      final spendingByDayOfWeek =
          _repository.getSpendingByDayOfWeek(transactions);
      final recentTransactions =
          _repository.getRecentTransactions(transactions, limit: 5);

      // Carry the active filter forward across reloads (e.g. syncing or
      // switching months shouldn't silently reset what the user picked).
      final activeFilter =
          currentState is TransactionLoaded ? currentState.activeFilter : null;
      final filteredTransactions = activeFilter == null
          ? transactions
          : transactions.where((t) => t.category == activeFilter).toList();

      emit(TransactionLoaded(
        allTransactions: transactions,
        filteredTransactions: filteredTransactions,
        recentTransactions: recentTransactions,
        totalSpent: totalSpent,
        totalIncome: totalIncome,
        savingsRate: savingsRate.toDouble(),
        spendingByCategory: spendingByCategory,
        spendingByDayOfWeek: spendingByDayOfWeek,
        selectedYear: targetYear,
        selectedMonth: targetMonth,
        activeFilter: activeFilter,
        newTransactionCount: newTransactionCount,
      ));
    } catch (e) {
      emit(TransactionError(e.toString()));
    }
  }
}
