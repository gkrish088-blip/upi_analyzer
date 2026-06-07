import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import '../models/transaction_models.dart';

class SmsService {

  // flutter_sms_inbox query — the bridge to Android SMS
  final SmsQuery _smsQuery = SmsQuery();

  // ─── Permission ───────────────────────────────────────────────────────────

  // request SMS permission from the user
  // returns true if granted, false if denied
  Future<bool> requestSmsPermission() async {
    // Request both READ_SMS and RECEIVE_SMS together
    // Some Android versions require both to actually read inbox
    final statuses = await [
      Permission.sms,
      Permission.phone,
    ].request();

    final smsGranted = statuses[Permission.sms]?.isGranted ?? false;
    return smsGranted;
  }

  // check if permission is already granted (no popup)
  Future<bool> hasSmsPermission() async {
    final status = await Permission.sms.status;
    return status.isGranted;
  }

  // ─── Reading SMS ──────────────────────────────────────────────────────────

  // reads all SMS, filters UPI ones, parses into Transaction objects
  Future<List<Transaction>> fetchUpiTransactions() async {
    // 1. Never query the SMS provider without permission — on Android this
    // throws a PlatformException (SecurityException) rather than returning
    // an empty result, so we guard explicitly and fail soft instead.
    final granted = await hasSmsPermission();
    if (!granted) return [];

    // 2. Pull the raw inbox. SmsQuery reads directly from the Android SMS
    // ContentProvider — same concept as telephony's getInboxSms, but with
    // an API that works on modern Android Gradle Plugin.
    // No `filter` is applied at the query level: bank/UPI sender IDs vary too
    // widely (and differ per telco/region) to express as a single SQL-style
    // `where`, so we pull everything and filter in Dart with `_isUpiSmsFromInbox`.
    final messages = await _smsQuery.querySms(
      kinds: [SmsQueryKind.inbox],
    );

    final transactions = <Transaction>[];

    for (final sms in messages) {
      // 3. Cheap keyword/sender check before the expensive regex parsing —
      // most inbox messages are not bank SMS at all (OTPs, promos, etc.).
      if (!_isUpiSmsFromInbox(sms)) continue;

      try {
        // 4. Transaction.fromSms runs a battery of regexes (amount, type,
        // merchant, UPI ref, balance...). Real-world bank SMS formats are
        // inconsistent, so any one of these can fail to match — fromSms
        // throws (e.g. `amount!` on a null) when a *required* field like
        // amount can't be extracted. We treat that single message as
        // unparseable and move on rather than aborting the whole sync.
        final body = sms.body ?? '';
        final source = _extractSourceFromInbox(sms);
        transactions.add(Transaction.fromSms(body, source));
      } catch (_) {
        // Skip silently: a malformed/unsupported SMS format shouldn't
        // crash the whole import — just leave it out of the results.
        continue;
      }
    }

    // 5. Return everything that parsed cleanly. Sorting/deduping/persistence
    // is left to the caller (e.g. a repository/bloc layer) so this service
    // stays a thin "device → domain model" adapter.

    return transactions;
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  // adapts a flutter_sms_inbox SmsMessage to the raw gate logic below
  bool _isUpiSmsFromInbox(SmsMessage sms) {
    return _isUpiSmsRaw(sms.body ?? '', sms.address ?? '');
  }

  // adapts a flutter_sms_inbox SmsMessage to the raw source-extraction logic
  String _extractSourceFromInbox(SmsMessage sms) {
    return _extractSourceRaw(sms.address ?? '');
  }

  // returns true if an SMS is a UPI transaction message
  bool _isUpiSmsRaw(String rawBody, String rawAddress) {
    // Lower-case once and reuse — bank SMS casing is inconsistent
    // ("Debited" vs "debited" vs "DEBITED") and regex `caseSensitive: false`
    // would re-do this normalisation on every keyword check.
    final body = rawBody.toLowerCase();
    final address = rawAddress.toLowerCase();

    // GATE 0 — Block promotional sender IDs
    // In India's DLT SMS system, sender IDs follow a format where
    // the 2-letter prefix indicates the message type:
    // TX- or TM- = Transactional (bank/service confirmations)
    // AD- = Advertised (service updates)
    // AP- = Promotional (marketing, offers) ← ALWAYS block these
    // We check the rawAddress prefix to reject promotional SMS
    // before any expensive body parsing.
    final upperAddress = rawAddress.toUpperCase();
    const blockedPrefixes = ['AP-', 'CP-', 'DP-', 'EP-', 'FP-'];
    if (blockedPrefixes.any((p) => upperAddress.startsWith(p))) {
      return false;
    }

    // We run this as a *gate sequence* rather than a single OR/AND
    // expression: each gate answers a different question ("is money even
    // mentioned?", "did it actually move?", "is the sender legit?", "is this
    // secretly an OTP/promo?"). Short-circuiting on the first failed gate
    // also means we skip the more expensive checks for messages that are
    // obviously not transactional (e.g. no currency marker at all).

    // GATE 1 — Currency marker OR bank debit/credit pattern
    // Most bank SMS include ₹/Rs./INR but SBI and some others
    // use plain "debited by AMOUNT" with no currency symbol.
    // We accept either a currency marker OR a plain amount
    // pattern that appears with debit/credit keywords.
    const currencyMarkers = ['₹', 'rs.', 'rs ', 'inr', 'rupee', 'rupees'];
    final hasCurrencyMarker = currencyMarkers.any((k) => body.contains(k));

    // Plain amount pattern: "debited by 10.00" or "credited by 500"
    // Matches: debited/credited + by/of/with + number
    final plainAmountPattern = RegExp(
      r'(?:debited|credited)\s+(?:by|of|with)\s+[\d,]+(?:\.\d+)?',
      caseSensitive: false,
    );
    final hasPlainAmount = plainAmountPattern.hasMatch(body);

    if (!hasCurrencyMarker && !hasPlainAmount) return false;

    // GATE 2 — Transaction action word (mandatory):
    // Mentioning money isn't enough — the message must describe money
    // actually *moving* (debited/credited/sent/...), not just referencing a
    // balance, limit, or due amount. This is what separates a transaction
    // SMS from a "minimum balance" or "EMI due" alert that also quotes ₹.
    const actionWords = [
      'debited', 'credited', 'debit', 'credit',
      'transferred', 'sent', 'received',
      'paid', 'payment of', 'withdrawn',
      'trf to', 'trf from',
      'upi/dr', 'upi/cr',
      'money sent', 'money received',
      'amount debited', 'amount credited',
    ];
    if (!actionWords.any((k) => body.contains(k))) return false;

    // GATE 3 — Bank/UPI sender OR transaction reference (at least one):
    // Confirms the message actually originates from (or documents) a real
    // banking rail — either the sender ID is a known bank/UPI short code,
    // or the body itself carries a transaction/UPI reference number. This
    // is what stops a friend's text like "paid you ₹500, sent via phonepe"
    // from passing as a bank-issued transaction record.
    const bankSenderCodes = [
      'sbi', 'hdfc', 'icici', 'axis', 'kotak', 'pnb', 'bob',
      'boi', 'canara', 'union', 'indian', 'central', 'uco',
      'idbi', 'idfc', 'rbl', 'indusind', 'federal', 'yes',
      'aubank', 'equitas', 'ujjivan', 'jana', 'fino',
      'paytm', 'gpay', 'phonepe', 'bhim', 'amazon', 'airtel',
      'jio', 'upi',
    ];
    const referenceMarkers = [
      'upi ref', 'upi/', 'refno', 'txn id', 'transaction id',
      'ref no', 'ref:', 'neft', 'rtgs', 'imps',
    ];
    final hasBankSender = bankSenderCodes.any((k) => address.contains(k));
    final hasReference = referenceMarkers.any((k) => body.contains(k));
    if (!hasBankSender && !hasReference) return false;

    // GATE 4 — Blocklist for known non-transaction patterns:
    // Even messages that clear gates 1-3 can still be OTPs ("₹ debited if you
    // share this OTP" style phishing-aware copy), balance/EMI reminders, or
    // promos that borrow transactional language to look legitimate. Reject
    // outright if any of these tell-tale phrases are present.
    const blocklist = [
      'otp', 'one time password', 'otp is',
      'your otp', 'do not share',
      'minimum balance', 'low balance alert',
      'emi due', 'loan due', 'due date',
      'kyc', 'update your',
      'click here', 'download', 'install',
      'limited time', 'expires',
      'missed call', 'please call',
      'recharge',
      'prepaid pack',
      'data pack',
      'talktime',
      'validity extended',
      'your airtel',
      'your jio',
      'your bsnl',
      'your vi ',
      'your vodafone',
      'mb data',
      'gb data',
      'topped up',
      'recharge of',
      'recharge for',
      'recharge is successful',
      'successfully recharged',
      'credited to your airtel',
      'credited to your jio',
      'credited to your vi',
      'credited to your vodafone',
      'credited to your bsnl',
      'credited to your mobile',
      'your prepaid',
      'prepaid recharge',
      'postpaid bill',
      'bill payment successful',
      'talk time',
      'talktime of',
      'data balance',
      'your plan',
    ];
    if (blocklist.any((k) => body.contains(k))) return false;

    // All gates cleared — this reads as a genuine UPI/bank transaction SMS.
    return true;
  }

  // extracts the source app/bank from a raw SMS sender address
  String _extractSourceRaw(String rawAddress) {
    // Sender IDs are DLT-registered alphanumeric codes (e.g. "AD-SBIUPI",
    // "VK-HDFCBK", "JD-ICICIB") — the bank/app name is embedded as a
    // substring, not a fixed position, so `contains` checks are the most
    // robust way to identify the source without a brittle exact match.
    final address = rawAddress.toUpperCase();

    if (address.contains('SBI')) return 'SBI';
    if (address.contains('HDFC')) return 'HDFC';
    if (address.contains('ICICI')) return 'ICICI';
    if (address.contains('AXIS')) return 'Axis';
    if (address.contains('KOTAK')) return 'Kotak';
    if (address.contains('PAYTM')) return 'Paytm';
    if (address.contains('GPAY') || address.contains('GOOGLEPAY')) return 'GPay';
    if (address.contains('PHONEPE')) return 'PhonePe';
    if (address.contains('BHIM')) return 'BHIM';

    // Fall back to the raw address rather than a generic "Unknown" — it
    // still gives the user something to recognise in the UI, and keeps
    // `source` non-null for downstream grouping/filtering.
    return rawAddress.isNotEmpty ? rawAddress : 'Unknown';
  }
}
