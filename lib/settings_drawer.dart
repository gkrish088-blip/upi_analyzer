import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bloc/transaction_bloc.dart';
import 'bloc/transaction_event.dart';
import 'bloc/transaction_state.dart';

// ════════════════════════════════════════════════════════════
// SETTINGS DRAWER
// ════════════════════════════════════════════════════════════
// This is a Flutter Drawer widget — it slides in from the left
// when the hamburger menu icon is tapped on the home screen.
//
// DATA STORAGE MAP:
// All settings are persisted using SharedPreferences — Android's
// key-value storage backed by an XML file at:
// /data/data/com.yourname.upi_analyzer/shared_prefs/
// FlutterSharedPreferences.xml
//
// Keys stored here:
//   'ai_api_key'    → user's AI provider API key (String)
//   'ai_provider'   → selected provider name (String: OpenAI/Gemini/Claude)
//   'auto_sync'     → whether new SMS are parsed automatically (bool)
//
// HOW API KEY FLOWS THROUGH THE APP:
// Settings drawer → SharedPreferences.setString('ai_api_key', key)
//   ↓
// ChatBloc._onInitialized() → SharedPreferences.getString('ai_api_key')
//   ↓
// ChatBloc._getAiResponse() → sent as Authorization header to AI API
//   ↓
// AI API (OpenAI/Gemini/Claude) → returns response
//   ↓
// ChatBloc emits new ChatReady state with AI message
//   ↓
// AskAIScreen rebuilds and shows the response bubble
//
// HOW PERMISSIONS FLOW:
// Toggle switched ON → permission_handler requests Android permission
//   ↓
// Android OS shows system dialog to user
//   ↓
// User grants → permission_handler returns PermissionStatus.granted
//   ↓
// SmsService.hasSmsPermission() returns true
//   ↓
// TransactionRepository.syncTransactions() proceeds with SMS reading
// ════════════════════════════════════════════════════════════

class SettingsDrawer extends StatefulWidget {
  const SettingsDrawer({super.key});

  @override
  State<SettingsDrawer> createState() => _SettingsDrawerState();
}

class _SettingsDrawerState extends State<SettingsDrawer> {
  static const _providerNames = ['OpenAI', 'Gemini', 'Claude'];

  bool _parseUpi = true;
  bool _catchAlerts = true;
  bool _autoSync = false;
  int _selectedProvider = 0;
  final TextEditingController _apiKeyController = TextEditingController();

  // initState runs once when the drawer is first created (mounted into the
  // widget tree). We kick off loading the persisted settings here so the
  // drawer shows the user's real saved values instead of the hard-coded
  // defaults declared above.
  @override
  void initState() {
    super.initState();
    _loadSavedSettings();
  }

  // Reads everything this screen needs to display from disk:
  //  - SharedPreferences (key/value storage, see file header comment for
  //    the full list of keys and where the underlying XML file lives)
  //  - permission_handler (for the live OS permission status of SMS and
  //    notifications, since those aren't something *we* store — Android
  //    is the source of truth for whether a permission is granted)
  //
  // This keeps the toggles in sync with reality: e.g. if the user revoked
  // SMS access from Android's app settings screen, the "Parse UPI messages"
  // switch will show as off the next time this drawer opens.
  Future<void> _loadSavedSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedApiKey = prefs.getString('ai_api_key');
    final savedProvider = prefs.getString('ai_provider');
    final savedAutoSync = prefs.getBool('auto_sync') ?? false;

    final smsStatus = await Permission.sms.status;
    final notificationStatus = await Permission.notification.status;

    if (!mounted) return;

    setState(() {
      if (savedApiKey != null) _apiKeyController.text = savedApiKey;
      if (savedProvider != null) {
        final index = _providerNames.indexOf(savedProvider);
        if (index != -1) _selectedProvider = index;
      }
      _parseUpi = smsStatus.isGranted;
      _catchAlerts = notificationStatus.isGranted;
      _autoSync = savedAutoSync;
    });
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  // Purely decorative header shown at the top of the drawer (an avatar
  // placeholder + "Your Profile" / "Tap to add details" labels). It does
  // not read or write any data — it's just a visual identity block above
  // the settings list, matching the look of the rest of the drawer.
  Widget _buildDrawerHeader() {
    return Column(
      children: [
        Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFF7B61FF).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.person_outline,
                color: Color(0xFF7B61FF),
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your Profile',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  'Tap to add details',
                  style: TextStyle(color: Color(0xFF888888), fontSize: 12),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Divider(color: Color(0xFF2A2A2A), height: 1),
      ],
    );
  }

  // Small grey, letter-spaced caption used above each group of settings
  // (e.g. "PERMISSIONS", "AI PROVIDER"). Just a styling helper so every
  // section heading looks identical — no state or storage involved.
  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF888888),
          fontSize: 11,
          letterSpacing: 1.4,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  // Reusable "icon + label + on/off Switch" row, used by the Permissions
  // section's three toggles. Keeping this in one place means every toggle
  // in that card looks and behaves the same; `onChanged` is supplied by the
  // caller so each toggle can decide what actually happens when the user
  // flips it (request an Android permission, save a preference, etc).
  //
  // All Switch color properties below are set explicitly (rather than left
  // to default) so the switch always renders with our purple/dark palette
  // regardless of the ambient Material theme — this app never actually
  // switches to a light ThemeData, but explicit colors protect us from any
  // theme-related rebuild making the switch fall back to default colors
  // that would be invisible against our near-black backgrounds.
  Widget _toggleRow({
    required IconData icon,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool showDivider = true,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF7B61FF).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: const Color(0xFF7B61FF)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
              Switch(
                value: value,
                onChanged: onChanged,
                // Explicit colors for every state — on/off, thumb/track —
                // so this switch never inherits a default that could clash
                // with (or vanish into) our dark backgrounds.
                activeThumbColor: const Color(0xFF7B61FF),
                activeTrackColor: const Color(0xFF7B61FF).withValues(alpha: 0.3),
                inactiveThumbColor: const Color(0xFF888888),
                inactiveTrackColor: const Color(0xFF2A2A2A),
              ),
            ],
          ),
        ),
        if (showDivider) const Divider(color: Color(0xFF2A2A2A), height: 1),
      ],
    );
  }

  // Card containing the three Android-permission-related toggles. These are
  // the switches that gate whether the rest of the app (specifically
  // SmsService and TransactionRepository, see the file header diagram) is
  // allowed to read SMS / show notifications / run automatically.
  //
  // Important: these toggles don't store their own "on/off" preference —
  // the *real* source of truth is the Android OS permission status, which
  // is why _loadSavedSettings() re-reads `Permission.sms.status` etc. each
  // time the drawer opens, instead of trusting a cached bool.
  Widget _buildPermissionsSection() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          _toggleRow(
            icon: Icons.message_outlined,
            label: 'Parse UPI messages',
            value: _parseUpi,
            // Turning this ON asks Android for SMS read access — this is
            // the permission that SmsService relies on to scan incoming
            // bank/UPI messages and turn them into transactions.
            // Turning it OFF can't silently revoke an OS permission, so we
            // send the user to the system App Settings screen instead,
            // where they can revoke it manually.
            onChanged: (value) async {
              if (value) {
                final granted = await Permission.sms.request();
                setState(() => _parseUpi = granted.isGranted);
                if (!granted.isGranted && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('SMS permission denied'),
                      backgroundColor: Color(0xFFFF5252),
                    ),
                  );
                }
              } else {
                setState(() => _parseUpi = false);
                await openAppSettings();
              }
            },
          ),
          _toggleRow(
            icon: Icons.notifications_outlined,
            label: 'Real-time UPI alerts',
            value: _catchAlerts,
            // Same pattern as above, but for the notification permission —
            // this lets the app pop a system notification the moment a new
            // UPI SMS arrives, instead of the user having to open the app
            // to see it.
            onChanged: (value) async {
              if (value) {
                final granted = await Permission.notification.request();
                setState(() => _catchAlerts = granted.isGranted);
                if (!granted.isGranted && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Notification permission denied'),
                      backgroundColor: Color(0xFFFF5252),
                    ),
                  );
                }
              } else {
                setState(() => _catchAlerts = false);
                await openAppSettings();
              }
            },
          ),
          _toggleRow(
            icon: Icons.sync_outlined,
            label: 'Auto parse new SMS',
            value: _autoSync,
            // Unlike the two toggles above, this one is *our* preference,
            // not an OS permission — so we persist it directly.
            // Storage key: 'auto_sync' (bool) in SharedPreferences.
            // TransactionRepository reads this flag to decide whether new
            // SMS should be parsed automatically in the background, or only
            // when the user manually triggers a sync.
            onChanged: (value) async {
              setState(() => _autoSync = value);
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('auto_sync', value);
            },
            showDivider: false,
          ),
        ],
      ),
    );
  }

  // NOTE: A "Connected UPI Apps" section used to live here. It was removed
  // because it was purely static/decorative UI (hard-coded app names and
  // fake "N patterns matched" counts) with no real functionality behind it.
  // The *actual* UPI app detection already happens automatically inside
  // SmsService, which matches incoming SMS sender addresses against known
  // UPI app patterns — there's nothing for the user to configure here.
  // Card that lets the user pick which AI provider (OpenAI / Gemini /
  // Claude) powers the "Ask AI" chat feature, and paste in their API key
  // for that provider.
  //
  // Storage keys written here:
  //   'ai_api_key'  (String) — the raw key the user pasted in
  //   'ai_provider' (String) — one of _providerNames ("OpenAI"/"Gemini"/"Claude")
  //
  // See the file header diagram for the full journey this key takes:
  // it's later read by ChatBloc and sent as an Authorization header to
  // whichever provider's API the user selected.
  Widget _buildAIProviderSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: _providerNames.asMap().entries.map((entry) {
              final i = entry.key;
              final label = entry.value;
              final selected = i == _selectedProvider;

              return Padding(
                padding: EdgeInsets.only(right: i < _providerNames.length - 1 ? 8 : 0),
                child: GestureDetector(
                  onTap: () => setState(() => _selectedProvider = i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFF7B61FF)
                          : const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: selected ? Colors.white : const Color(0xFF888888),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          // _selectedProvider is just an in-memory index into _providerNames
          // while the user is choosing — it only gets written to disk (as
          // the 'ai_provider' string) when they actually press "Save API Key"
          // below, alongside the key itself.
          const SizedBox(height: 14),
          const Text(
            'API Key',
            style: TextStyle(fontSize: 12, color: Color(0xFF888888)),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _apiKeyController,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Paste your API key here...',
              hintStyle: const TextStyle(color: Color(0xFF888888)),
              filled: true,
              fillColor: const Color(0xFF2A2A2A),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              // Validates the typed key, then writes both the key and the
              // chosen provider name to SharedPreferences so ChatBloc can
              // pick them up the next time it needs to call the AI API.
              onPressed: () async {
                final key = _apiKeyController.text.trim();

                if (key.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter an API key'),
                      backgroundColor: Color(0xFFFF5252),
                    ),
                  );
                  return;
                }

                if (key.length < 20) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('API key seems too short — please check it'),
                      backgroundColor: Color(0xFFFF9800),
                    ),
                  );
                  return;
                }

                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('ai_api_key', key);
                await prefs.setString('ai_provider', _providerNames[_selectedProvider]);

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '${_providerNames[_selectedProvider]} API key saved ✓',
                      ),
                      backgroundColor: const Color(0xFF4CAF50),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7B61FF),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text(
                'Save API Key',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Builds a CSV file of every transaction currently held by TransactionBloc
  // and writes it to the device's public Downloads folder, so the user can
  // open it later from any file manager or share it from there.
  //
  // Data source: TransactionBloc's current state (state.allTransactions) —
  // this is the same in-memory list the rest of the app (charts, lists,
  // chat) reads from, so the export always matches what's on screen.
  Future<void> _exportCsv() async {
    final state = context.read<TransactionBloc>().state;
    if (state is! TransactionLoaded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No data to export'),
          backgroundColor: Color(0xFF888888),
        ),
      );
      return;
    }

    final buffer = StringBuffer();

    buffer.writeln(
      'Date,Time,Merchant,Category,Amount,Type,UPI Ref,Bank Account',
    );

    for (final t in state.allTransactions) {
      final date = '${t.timestamp.day}/${t.timestamp.month}/${t.timestamp.year}';
      final time =
          '${t.timestamp.hour.toString().padLeft(2, '0')}:${t.timestamp.minute.toString().padLeft(2, '0')}';
      final merchant = (t.merchant ?? 'Unknown').replaceAll(',', ' ');
      final category = t.category.name;
      final amount = t.amount.toStringAsFixed(2);
      final type = t.isDebit ? 'Debit' : 'Credit';
      final upiRef = t.upiRef ?? '';
      final account = t.bankAccount ?? '';
      buffer.writeln('$date,$time,$merchant,$category,$amount,$type,$upiRef,$account');
    }

    final csvContent = buffer.toString();

    // On Android 11+ (API 30+), writing to shared storage like the public
    // Downloads folder requires the "All files access" permission
    // (MANAGE_EXTERNAL_STORAGE). permission_handler exposes this as
    // Permission.manageExternalStorage. On Android 10 and below, scoped
    // storage rules are looser and this may already be granted/unneeded —
    // we still ask so the file write below has the best chance of working.
    final storagePermission = await Permission.manageExternalStorage.request();
    // On Android 10+ (API 29+) scoped storage means WRITE_EXTERNAL_STORAGE
    // is not needed for Downloads folder — but we still check on older devices
    if (!storagePermission.isGranted) {
      // Try without permission on Android 10+ — it may still work
      // due to scoped storage rules
    }

    try {
      // Save to the public Downloads folder so the user can find it
      // in any file manager app.
      // Environment.getExternalStoragePublicDirectory(DIRECTORY_DOWNLOADS)
      // in Android Java maps to /storage/emulated/0/Download/ in Dart via:
      // getExternalStorageDirectory() goes to app-private storage — wrong
      // getDownloadsDirectory() from path_provider gives public Downloads
      final directory = Directory('/storage/emulated/0/Download');
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${directory.path}/upi_transactions_$timestamp.csv');
      await file.writeAsString(csvContent);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to Downloads/upi_transactions_$timestamp.csv'),
            backgroundColor: const Color(0xFF4CAF50),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: const Color(0xFFFF5252),
          ),
        );
      }
    }
  }

  // Shows a confirmation dialog before wiping data — destructive actions
  // should always have a "are you sure?" step. If the user confirms, it
  // dispatches TransactionAllDeleteRequested to TransactionBloc, which is
  // the same Bloc that powers the home screen's transaction list — so the
  // list updates immediately once the delete completes.
  Future<void> _confirmClearAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Clear all data?',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: const Text(
          'This will permanently delete every transaction stored in the app. This action cannot be undone.',
          style: TextStyle(color: Color(0xFF888888), fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF888888)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Color(0xFFFF5252)),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      context.read<TransactionBloc>().add(const TransactionAllDeleteRequested());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All data cleared'),
          backgroundColor: Color(0xFF4CAF50),
        ),
      );
    }
  }

  // Card with two tappable rows: "Export CSV" (writes a snapshot of all
  // transactions to disk, see _exportCsv) and "Clear all data" (wipes the
  // transaction database via TransactionBloc, see _confirmClearAllData).
  // Both are simple GestureDetector + Row combos styled to look like list
  // items, with a chevron hinting that tapping does something.
  Widget _buildDataSection() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: _exportCsv,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              child: Row(
                children: [
                  Icon(
                    Icons.download_outlined,
                    color: Color(0xFF7B61FF),
                    size: 20,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Export CSV',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: Color(0xFF888888),
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
          const Divider(color: Color(0xFF2A2A2A), height: 1),
          GestureDetector(
            onTap: _confirmClearAllData,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              child: Row(
                children: [
                  Icon(
                    Icons.delete_outline,
                    color: Color(0xFFFF5252),
                    size: 20,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Clear all data',
                      style: TextStyle(color: Color(0xFFFF5252), fontSize: 14),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: Color(0xFF888888),
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Assembles the whole drawer: a dark full-height Container so the drawer
  // matches the app's dark theme regardless of the system theme, wrapped in
  // SafeArea (keeps content clear of notches/status bars) and a scroll view
  // (so the settings list doesn't overflow on smaller screens).
  //
  // The body is just the section builders above, stacked in a Column with
  // a label above each card. This is also where you'd add a brand-new
  // section: add a `_buildSectionLabel('NAME')` + `_buildXSection()` pair
  // to the children list below.
  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Container(
        color: const Color(0xFF0F0F0F),
        height: double.infinity,
        child: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDrawerHeader(),
                  const SizedBox(height: 24),
                  _buildSectionLabel('PERMISSIONS'),
                  _buildPermissionsSection(),
                  const SizedBox(height: 24),
                  _buildSectionLabel('AI PROVIDER'),
                  _buildAIProviderSection(),
                  const SizedBox(height: 24),
                  _buildSectionLabel('DATA'),
                  _buildDataSection(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
