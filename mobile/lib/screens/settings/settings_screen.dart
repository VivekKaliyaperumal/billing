import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/settings_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/toast.dart';

/// Port of `src/pages/SettingsPage.tsx`.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final _shopName = TextEditingController(text: context.read<SettingsProvider>().settings.shopName);
  late String _currency = context.read<SettingsProvider>().settings.currency;

  @override
  void dispose() {
    _shopName.dispose();
    super.dispose();
  }

  void _save() {
    context.read<SettingsProvider>().updateSettings(shopName: _shopName.text, currency: _currency);
    FocusScope.of(context).unfocus();
    showToast(context, title: 'Settings saved', description: 'Your preferences have been updated.');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final previewSymbol = currencies.firstWhere((c) => c.code == _currency).symbol;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 32),
      child: FadeIn(
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 672),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PageHeader(
                  icon: LucideIcons.settings,
                  gradient: p.gradientPrimary,
                  title: 'Settings',
                  subtitle: 'Manage your shop preferences',
                ),
                const SizedBox(height: 32),
                _SettingsCard(
                  icon: LucideIcons.store,
                  iconColor: p.primary,
                  title: 'Shop Information',
                  description: 'Basic details about your shop',
                  child: AppTextField(label: 'Shop Name', controller: _shopName, hint: 'Enter shop name'),
                ),
                const SizedBox(height: 24),
                _SettingsCard(
                  icon: LucideIcons.creditCard,
                  iconColor: p.accent,
                  title: 'Currency Settings',
                  description: 'Set your preferred currency for transactions',
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const FieldLabel('Currency Type'),
                    const SizedBox(height: 8),
                    AppSelect<String>(
                      value: _currency,
                      height: 48,
                      placeholder: 'Select currency',
                      options: [
                        for (final c in currencies)
                          SelectOption(
                            c.code,
                            c.name,
                            child: Row(children: [
                              Text(c.symbol, style: TextStyle(fontWeight: FontWeight.w700, color: p.foreground)),
                              const SizedBox(width: 8),
                              Text(c.name, style: TextStyle(color: p.foreground)),
                              const SizedBox(width: 8),
                              Text('(${c.code})', style: TextStyle(color: p.mutedForeground)),
                            ]),
                          ),
                      ],
                      onChanged: (v) => setState(() => _currency = v),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: p.secondary.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(AppRadius.xl),
                        border: Border.all(color: p.border),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Preview:', style: TextStyle(fontSize: 14, color: p.mutedForeground)),
                        const SizedBox(height: 4),
                        Text('${previewSymbol}1,234.56',
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: p.foreground)),
                      ]),
                    ),
                  ]),
                ),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerLeft,
                  child: AppButton(
                    label: 'Save Settings',
                    icon: LucideIcons.save,
                    height: 44,
                    shadow: p.shadowMedium,
                    onPressed: _save,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
    required this.child,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppCard(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(width: 8),
          Text(title, style: display(22, color: p.foreground)),
        ]),
        const SizedBox(height: 6),
        Text(description, style: TextStyle(fontSize: 14, color: p.mutedForeground)),
        const SizedBox(height: 24),
        child,
      ]),
    );
  }
}
