import 'package:flutter/material.dart';

class SettingsDrawer extends StatefulWidget {
  const SettingsDrawer({super.key});

  @override
  State<SettingsDrawer> createState() => _SettingsDrawerState();
}

class _SettingsDrawerState extends State<SettingsDrawer> {
  bool _parseUpi = true;
  bool _catchAlerts = true;
  bool _autoSync = false;
  bool _isDarkMode = true;
  int _selectedProvider = 0;
  final TextEditingController _apiKeyController = TextEditingController();

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

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
                activeThumbColor: const Color(0xFF7B61FF),
              ),
            ],
          ),
        ),
        if (showDivider) const Divider(color: Color(0xFF2A2A2A), height: 1),
      ],
    );
  }

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
            onChanged: (v) => setState(() => _parseUpi = v),
          ),
          _toggleRow(
            icon: Icons.notifications_outlined,
            label: 'Real-time UPI alerts',
            value: _catchAlerts,
            onChanged: (v) => setState(() => _catchAlerts = v),
          ),
          _toggleRow(
            icon: Icons.sync_outlined,
            label: 'Auto parse new SMS',
            value: _autoSync,
            onChanged: (v) => setState(() => _autoSync = v),
            showDivider: false,
          ),
        ],
      ),
    );
  }

  Widget _buildUpiAppsSection() {
    final apps = [
      {
        'name': 'GPay',
        'icon': Icons.g_mobiledata,
        'color': const Color(0xFF4285F4),
        'patterns': '3 patterns matched',
      },
      {
        'name': 'PhonePe',
        'icon': Icons.phone_android_outlined,
        'color': const Color(0xFF5F259F),
        'patterns': '2 patterns matched',
      },
      {
        'name': 'Paytm',
        'icon': Icons.account_balance_wallet_outlined,
        'color': const Color(0xFF00BAF2),
        'patterns': '1 pattern matched',
      },
      {
        'name': 'BHIM',
        'icon': Icons.account_balance_outlined,
        'color': const Color(0xFF007935),
        'patterns': '5 patterns matched',
      },
    ];

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: apps.asMap().entries.map((entry) {
          final i = entry.key;
          final app = entry.value;
          final color = app['color'] as Color;
          final isLast = i == apps.length - 1;

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 16,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        app['icon'] as IconData,
                        size: 18,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            app['name'] as String,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            app['patterns'] as String,
                            style: const TextStyle(
                              color: Color(0xFF888888),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Active',
                        style: TextStyle(
                          color: Color(0xFF4CAF50),
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (!isLast) const Divider(color: Color(0xFF2A2A2A), height: 1),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildAIProviderSection() {
    final providers = ['OpenAI', 'Gemini', 'Claude'];

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
            children: providers.asMap().entries.map((entry) {
              final i = entry.key;
              final label = entry.value;
              final selected = i == _selectedProvider;

              return Padding(
                padding: EdgeInsets.only(right: i < providers.length - 1 ? 8 : 0),
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
              onPressed: () {},
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

  Widget _buildAppearanceSection() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: _toggleRow(
        icon: Icons.dark_mode_outlined,
        label: 'Dark mode',
        value: _isDarkMode,
        onChanged: (v) => setState(() => _isDarkMode = v),
        showDivider: false,
      ),
    );
  }

  Widget _buildDataSection() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: () {},
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
            onTap: () {},
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
                  _buildSectionLabel('CONNECTED UPI APPS'),
                  _buildUpiAppsSection(),
                  const SizedBox(height: 24),
                  _buildSectionLabel('AI PROVIDER'),
                  _buildAIProviderSection(),
                  const SizedBox(height: 24),
                  _buildSectionLabel('APPEARANCE'),
                  _buildAppearanceSection(),
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
