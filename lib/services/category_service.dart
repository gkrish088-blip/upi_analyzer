import '../models/transaction_models.dart';

class CategoryService {

  // ─── Keyword maps ─────────────────────────────────────────────────────────

  // merchant/keyword → category mapping
  // you will expand this list over time
  static const Map<String, TransactionCategory> _merchantKeywords = {
    // food
    'swiggy'    : TransactionCategory.food,
    'zomato'    : TransactionCategory.food,
    'blinkit'   : TransactionCategory.food,
    'dominos'   : TransactionCategory.food,
    'mcdonalds' : TransactionCategory.food,
    // transport
    'uber'      : TransactionCategory.transport,
    'ola'       : TransactionCategory.transport,
    'rapido'    : TransactionCategory.transport,
    'irctc'     : TransactionCategory.transport,
    // shopping
    'amazon'    : TransactionCategory.shopping,
    'flipkart'  : TransactionCategory.shopping,
    'myntra'    : TransactionCategory.shopping,
    'meesho'    : TransactionCategory.shopping,
    // bills
    'electricity': TransactionCategory.bills,
    'bescom'    : TransactionCategory.bills,
    'airtel'    : TransactionCategory.bills,
    'jio'       : TransactionCategory.bills,
    'bsnl'      : TransactionCategory.bills,
    // entertainment
    'netflix'   : TransactionCategory.entertainment,
    'spotify'   : TransactionCategory.entertainment,
    'youtube'   : TransactionCategory.entertainment,
    'bookmyshow': TransactionCategory.entertainment,
    // food
    'dunzo'     : TransactionCategory.food,
    'zepto'     : TransactionCategory.food,
    'bigbasket' : TransactionCategory.food,
    'instamart' : TransactionCategory.food,
    'kfc'       : TransactionCategory.food,
    'burger king': TransactionCategory.food,
    'pizza hut' : TransactionCategory.food,

    // transport
    'redbus'    : TransactionCategory.transport,
    'makemytrip': TransactionCategory.transport,
    'goibibo'   : TransactionCategory.transport,
    'ixigo'     : TransactionCategory.transport,
    'yulu'      : TransactionCategory.transport,

    // shopping
    'nykaa'     : TransactionCategory.shopping,
    'ajio'      : TransactionCategory.shopping,
    'tata cliq' : TransactionCategory.shopping,
    'snapdeal'  : TransactionCategory.shopping,
    'decathlon' : TransactionCategory.shopping,
    'ikea'      : TransactionCategory.shopping,

    // bills
    'tata power': TransactionCategory.bills,
    'adani'     : TransactionCategory.bills,
    'mahanagar' : TransactionCategory.bills,
    'bwssb'     : TransactionCategory.bills,
    'bbmp'      : TransactionCategory.bills,
    'vi '       : TransactionCategory.bills,
    'vodafone'  : TransactionCategory.bills,

    // entertainment
    'hotstar'   : TransactionCategory.entertainment,
    'disney'    : TransactionCategory.entertainment,
    'amazon prime': TransactionCategory.entertainment,
    'zee5'      : TransactionCategory.entertainment,
    'sonyliv'   : TransactionCategory.entertainment,
    'jiosaavn'  : TransactionCategory.entertainment,
    'gaana'     : TransactionCategory.entertainment,
    'pvr'       : TransactionCategory.entertainment,
    'inox'      : TransactionCategory.entertainment,
  };

  // ─── Main categorization method ───────────────────────────────────────────

  // Entry point: call this on every parsed transaction before saving to DB.
  // Returns a new Transaction (immutable copyWith) with the category field set.
  // Never mutates the original — safe to call multiple times.
  Transaction categorize(Transaction transaction) {
    // Step 1: Credits are always money coming IN (someone paying you / refund).
    // There's no meaningful spend category for these, so tag them as transfer.
    if (transaction.type == TransactionType.credit) {
      return transaction.copyWith(category: TransactionCategory.transfer);
    }

    // Step 2: Try the merchant name first — it's already a clean extracted string
    // (e.g. "Swiggy", "UBER INDIA") so keyword matching is more reliable here
    // than scanning the full noisy SMS body.
    if (transaction.merchant != null && transaction.merchant!.isNotEmpty) {
      final category = _matchKeywords(transaction.merchant!);
      // Only accept the result if something actually matched; if _matchKeywords
      // returned 'other' it means no keyword hit, so fall through to SMS scan.
      if (category != TransactionCategory.other) {
        return transaction.copyWith(category: category);
      }
    }

    // Step 3: Merchant was null/empty OR didn't match — scan the raw SMS body.
    // This catches cases where the merchant wasn't extracted but the SMS still
    // contains a recognisable keyword (e.g. "paid to Netflix via UPI").
    // _matchKeywords returns 'other' if nothing matches, so this is always safe.
    final smsCategory = _matchKeywords(transaction.rawSms);
    return transaction.copyWith(category: smsCategory);
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  // Scans [text] for any keyword in _merchantKeywords (case-insensitive).
  // Returns the first matching category, or TransactionCategory.other if none.
  // Used for both merchant name checks and full SMS body scans.
  TransactionCategory _matchKeywords(String text) {
    final lower = text.toLowerCase(); // lowercase once, reuse for every check
    for (final entry in _merchantKeywords.entries) {
      if (lower.contains(entry.key)) return entry.value;
    }
    return TransactionCategory.other;
  }
}