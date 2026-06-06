import '../database/database_helper.dart';
import '../models/transaction_models.dart';
import '../services/category_service.dart';
import '../services/sms_service.dart';

class TransactionRepository {

  // ─── Dependencies ─────────────────────────────────────────────────────────
  
  final DatabaseHelper _db;
  final SmsService _smsService;
  final CategoryService _categoryService;

  // constructor — dependencies injected from outside
  // this is called Dependency Injection — same pattern as Express where
  // you pass db/services into a controller rather than importing directly
  TransactionRepository({
    DatabaseHelper? db,
    SmsService? smsService,
    CategoryService? categoryService,
  })  : _db = db ?? DatabaseHelper(),
        _smsService = smsService ?? SmsService(),
        _categoryService = categoryService ?? CategoryService();

  // ─── Permission ───────────────────────────────────────────────────────────

  Future<bool> requestSmsPermission() async => _smsService.requestSmsPermission();

  Future<bool> hasSmsPermission() async => _smsService.hasSmsPermission();

  // ─── Main sync method ─────────────────────────────────────────────────────

  // This is the most important method.
  // Full pipeline: SMS → filter → parse → categorize → deduplicate → save
  //
  // Dedup strategy: `upiRef` is the bank-assigned reference number for a UPI
  // transaction, so it's the natural unique key — re-running this sync (e.g.
  // pull-to-refresh) must not produce duplicate rows for SMS we've already
  // ingested. We compare against a Set rather than querying the DB per-row
  // because that would be O(n) round trips; building the Set once up front
  // makes the membership check O(1) per candidate.
  Future<SyncResult> syncTransactions() async {
    // Bail early if we don't have SMS read access — nothing else in this
    // pipeline can run without it, and we don't want to surface a generic
    // error when the real issue is a permission the user can grant.
    // First check if already granted
    bool hasPermission = await hasSmsPermission();

    // If not granted, actively request it
    if (!hasPermission) {
      print('🔐 Permission not granted, requesting...');
      hasPermission = await requestSmsPermission();
    }

    // If still not granted after request, give up
    if (!hasPermission) {
      print('🔐 Permission denied after request');
      return SyncResult.permissionDenied();
    }

    print('🔐 Permission granted, proceeding with sync...');

    try {
      // SmsService already parses raw SMS strings into Transaction objects
      // (via Transaction.fromSms) and filters out non-UPI messages, so what
      // comes back here is "candidate" transactions, not yet persisted.
      final rawTransactions = await _smsService.fetchUpiTransactions();

      // Snapshot what's already in the DB so we can recognize transactions
      // we've imported before. upiRef can be null for malformed SMS that
      // slipped through parsing — those fall back to fingerprint matching
      // below instead of being left out of dedup entirely.
      final existing = await _db.getAllTransactions();

      // Set 1: upiRefs for transactions that HAVE a upiRef — the
      // authoritative unique key when present.
      final existingRefs = existing
          .map((t) => t.upiRef)
          .whereType<String>()
          .toSet();

      // Set 2: fingerprints ONLY for transactions that have NO upiRef.
      // We don't fingerprint transactions that have a upiRef because
      // upiRef is already the authoritative unique key for those —
      // fingerprinting them too would add unnecessary complexity.
      final existingFingerprints = existing
          .where((t) => t.upiRef == null)
          .map((t) => _buildFingerprint(t))
          .toSet();

      final newTransactions = <Transaction>[];
      for (final raw in rawTransactions) {
        final upiRef = raw.upiRef;

        // Case 1: has a upiRef → use it as the unique key. Already synced
        // in a previous run — skip to keep the import idempotent.
        if (upiRef != null && existingRefs.contains(upiRef)) {
          continue;
        }

        // Case 2: no upiRef → fall back to fingerprint matching so these
        // rows are still deduplicated across repeated syncs.
        if (upiRef == null &&
            existingFingerprints.contains(_buildFingerprint(raw))) {
          continue;
        }

        // Categorization happens before persistence so the stored row
        // already carries its category — downstream aggregation (the "Quant
        // Engine" methods below) can then work purely off DB reads without
        // re-running classification on every screen load.
        final categorized = _categoryService.categorize(raw);
        newTransactions.add(categorized);

        // Also add to the in-memory sets so that if the SAME transaction
        // appears twice in this batch (some banks send a confirmation SMS
        // AND a balance-update SMS for the same transaction), the second
        // occurrence is caught as a duplicate within this run too.
        if (upiRef != null) {
          existingRefs.add(upiRef);
        } else {
          existingFingerprints.add(_buildFingerprint(raw));
        }
      }

      for (final transaction in newTransactions) {
        await _db.insertTransaction(transaction);
      }

      return SyncResult.success(newCount: newTransactions.length);
    } catch (e) {
      // Surface parsing/DB failures as a typed result instead of letting the
      // exception bubble — the BLoC layer expects a SyncResult either way and
      // shouldn't have to wrap this call in its own try/catch.
      return SyncResult.error(e.toString());
    }
  }

  // ─── Read methods ─────────────────────────────────────────────────────────
  // Thin pass-throughs to the DB layer. They exist so the BLoC depends only
  // on the repository (not DatabaseHelper directly) — keeps persistence
  // swappable and gives us a single seam to add caching later if needed.

  Future<List<Transaction>> getAllTransactions() => _db.getAllTransactions();

  Future<List<Transaction>> getTransactionsByMonth(int year, int month) =>
      _db.getTransactionsByMonth(year, month);

  Future<List<Transaction>> getTransactionsByDateRange(
    DateTime start,
    DateTime end,
  ) => _db.getTransactionsByDateRange(start, end);

  // ─── Delete methods ───────────────────────────────────────────────────────

  Future<void> deleteTransaction(String id) => _db.deleteTransaction(id);

  Future<void> deleteAllTransactions() => _db.deleteAllTransactions();

  // ─── Aggregation methods (your Quant Engine starts here) ──────────────────
  // These methods compute the numbers shown on the home screen.
  // Pure Dart math — no DB queries, works on a list passed in.

  // total spent this month (sum of all debits)
  //
  // Only `isDebit` rows count toward "spent" — credits (refunds, salary,
  // money received) are deliberately excluded so this number reflects actual
  // outflow, matching what a user expects from a "total spent" tile.
  double getTotalSpent(List<Transaction> transactions) {
    return transactions
        .where((t) => t.isDebit)
        .fold(0.0, (sum, t) => sum + t.amount);
  }

  // total income this month (sum of all credits)
  double getTotalIncome(List<Transaction> transactions) {
    return transactions
        .where((t) => !t.isDebit)
        .fold(0.0, (sum, t) => sum + t.amount);
  }

  // spending by category → used for donut chart
  // returns a Map like: { TransactionCategory.food: 5800.0, ... }
  //
  // Credits are excluded here too — a "salary" credit miscategorized as
  // "transfer" would otherwise inflate a spending breakdown with money that
  // never left the account.
  Map<TransactionCategory, double> getSpendingByCategory(
    List<Transaction> transactions,
  ) {
    final Map<TransactionCategory, double> result = {};
    for (final t in transactions.where((t) => t.isDebit)) {
      result[t.category] = (result[t.category] ?? 0) + t.amount;
    }
    return result;
  }

  // spending by day of week → used for histogram
  // returns a Map like: { 'Mon': 1200.0, 'Tue': 340.0, ... }
  //
  // The map is seeded with all seven days (in Mon→Sun order) up front so the
  // histogram always renders a consistent set of bars — including zero-value
  // days — rather than only the days that happen to have transactions.
  Map<String, double> getSpendingByDayOfWeek(List<Transaction> transactions) {
    const dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final Map<String, double> result = {for (final d in dayLabels) d: 0.0};

    for (final t in transactions.where((t) => t.isDebit)) {
      // DateTime.weekday is 1 (Monday) .. 7 (Sunday), so it maps directly
      // onto dayLabels with a -1 offset.
      final label = dayLabels[t.timestamp.weekday - 1];
      result[label] = (result[label] ?? 0) + t.amount;
    }
    return result;
  }

  // recent transactions — last N transactions sorted by date
  //
  // Relies on DatabaseHelper already returning rows ordered by timestamp DESC
  // (newest first) — this method doesn't re-sort, it just truncates, so the
  // ordering guarantee lives in one place (the SQL query) rather than being
  // duplicated/re-asserted here.
  List<Transaction> getRecentTransactions(
    List<Transaction> transactions, {
    int limit = 5,
  }) {
    return transactions.take(limit).toList();
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  // A fingerprint uniquely identifies a transaction when upiRef is absent.
  // We combine amount + timestamp milliseconds + bankAccount because
  // the chance of two genuinely different transactions having the exact
  // same amount, time, and account is negligibly small.
  // bankAccount can be null — we use ?? 'unknown' to keep it a pure
  // String so the fingerprint is always a valid Set key.
  String _buildFingerprint(Transaction t) {
    // Round timestamp to nearest minute to handle slight variations
    // in DateTime.now() calls for the same SMS parsed at different times.
    // Two transactions are the same if amount + account + minute match.
    final roundedTime = DateTime(
      t.timestamp.year,
      t.timestamp.month,
      t.timestamp.day,
      t.timestamp.hour,
      t.timestamp.minute,
    ).millisecondsSinceEpoch;
    return '${t.amount}_${roundedTime}_${t.bankAccount ?? 'unknown'}';
  }
}

// ─── SyncResult ───────────────────────────────────────────────────────────────
// A result object returned by syncTransactions()
// Tells the BLoC what happened — success, no permission, or error
// This is like an Express response object but for internal use

class SyncResult {
  final bool success;
  final bool permissionDenied;
  final int newTransactionsCount;
  final String? errorMessage;

  const SyncResult._({
    required this.success,
    required this.permissionDenied,
    required this.newTransactionsCount,
    this.errorMessage,
  });

  // named constructors for clean usage at call sites:
  // SyncResult.success(newCount: 5)
  // SyncResult.permissionDenied()
  // SyncResult.error('something went wrong')

  factory SyncResult.success({required int newCount}) => SyncResult._(
        success: true,
        permissionDenied: false,
        newTransactionsCount: newCount,
      );

  factory SyncResult.permissionDenied() => SyncResult._(
        success: false,
        permissionDenied: true,
        newTransactionsCount: 0,
      );

  factory SyncResult.error(String message) => SyncResult._(
        success: false,
        permissionDenied: false,
        newTransactionsCount: 0,
        errorMessage: message,
      );
}