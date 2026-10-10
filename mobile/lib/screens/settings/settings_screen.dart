import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_info.dart';
import '../../data/app_database.dart';
import '../../models/models.dart';
import '../../providers/cart_provider.dart';
import '../../providers/customer_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/sales_history_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/backup_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../utils/storage.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/common.dart';
import '../../widgets/toast.dart';

/// Shop details, currency, backup/restore and app information.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final _shopName = TextEditingController(text: context.read<SettingsProvider>().settings.shopName);
  late String _currency = context.read<SettingsProvider>().settings.currency;
  bool _working = false;

  @override
  void dispose() {
    _shopName.dispose();
    super.dispose();
  }

  bool get _hasRecords =>
      context.read<SalesHistoryProvider>().sales.isNotEmpty || context.read<CustomerProvider>().customers.isNotEmpty;

  Future<void> _save() async {
    final settings = context.read<SettingsProvider>();
    final currencyChanged = _currency != settings.settings.currency;
    if (currencyChanged && _hasRecords && !await _confirmCurrencyChange()) return;
    if (!mounted) return;
    settings.updateSettings(shopName: _shopName.text, currency: _currency);
    _shopName.text = settings.settings.shopName;
    FocusScope.of(context).unfocus();
    showToast(context, title: 'Settings saved', description: 'Your preferences have been updated.');
  }

  Future<bool> _confirmCurrencyChange() async {
    final result = await showAppDialog<bool>(
      context,
      (ctx) => AppDialog(
        showClose: false,
        title: const Text('Change currency?'),
        description: const Text(
          'Existing prices, sales and customer balances keep their numbers and are shown with the new symbol. '
          'They are not converted.',
        ),
        child: Padding(
          padding: const EdgeInsets.only(top: 24),
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            AppButton(label: 'Cancel', variant: ButtonVariant.outline, onPressed: () => Navigator.of(ctx).pop(false)),
            const SizedBox(width: 8),
            AppButton(label: 'Change', onPressed: () => Navigator.of(ctx).pop(true)),
          ]),
        ),
      ),
    );
    return result ?? false;
  }

  Future<void> _backup() async {
    setState(() => _working = true);
    try {
      final data = ShopData(
        products: context.read<ProductProvider>().products,
        sales: context.read<SalesHistoryProvider>().sales,
        customers: context.read<CustomerProvider>().customers,
      );
      await BackupService.share(data, context.read<SettingsProvider>().settings);
    } catch (e) {
      if (mounted) showToast(context, title: 'Error', description: 'Could not create the backup.', destructive: true);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _restore() async {
    setState(() => _working = true);
    try {
      final text = await BackupService.pickFile();
      if (text == null || !mounted) return;
      final backup = BackupService.decode(text);
      if (!await _confirmRestore(backup) || !mounted) return;
      await context.read<AppDatabase>().replaceAll(backup.data);
      if (!mounted) return;
      context.read<ProductProvider>().replaceAll(backup.data.products);
      context.read<SalesHistoryProvider>().replaceAll(backup.data.sales);
      context.read<CustomerProvider>().replaceAll(backup.data.customers);
      context.read<CartProvider>().clear();
      final settings = context.read<SettingsProvider>()
        ..updateSettings(shopName: backup.settings.shopName, currency: backup.settings.currency);
      setState(() {
        _shopName.text = settings.settings.shopName;
        _currency = settings.settings.currency;
      });
      showToast(context, title: 'Backup restored', description: 'Your data has been replaced with the backup.');
    } on FormatException catch (e) {
      if (mounted) showToast(context, title: 'Cannot restore', description: e.message, destructive: true);
    } catch (e) {
      reportStorageIssue('Could not restore the backup. Your existing data was not changed.', e);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<bool> _confirmRestore(Backup backup) async {
    final d = backup.data;
    final result = await showAppDialog<bool>(
      context,
      (ctx) => AppDialog(
        showClose: false,
        title: const Text('Replace all data?'),
        description: Text(
          'Backup from ${dateTimeLocal.format(backup.exportedAt)}: ${d.products.length} products, '
          '${d.sales.length} sales, ${d.customers.length} customers.\n\n'
          'Everything currently in the app will be replaced. This cannot be undone, so take a backup first if unsure.',
        ),
        child: Padding(
          padding: const EdgeInsets.only(top: 24),
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            AppButton(label: 'Cancel', variant: ButtonVariant.outline, onPressed: () => Navigator.of(ctx).pop(false)),
            const SizedBox(width: 8),
            AppButton(label: 'Replace', variant: ButtonVariant.destructive, onPressed: () => Navigator.of(ctx).pop(true)),
          ]),
        ),
      ),
    );
    return result ?? false;
  }

  Future<void> _open(String url) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) showToast(context, title: 'Error', description: 'Could not open $url', destructive: true);
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
                  description: 'Shown in the header and on receipts',
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
                    height: 48,
                    shadow: p.shadowMedium,
                    onPressed: _save,
                  ),
                ),
                const SizedBox(height: 32),
                _SettingsCard(
                  icon: LucideIcons.databaseBackup,
                  iconColor: p.success,
                  title: 'Backup & Restore',
                  description: 'All data is kept only on this phone. Save a backup regularly, for example to Google Drive, '
                      'so nothing is lost if the phone is lost or reset. Backups include customer phone numbers: '
                      'store them somewhere private.',
                  child: Wrap(spacing: 12, runSpacing: 12, children: [
                    AppButton(
                      label: 'Save Backup',
                      icon: LucideIcons.download,
                      height: 48,
                      onPressed: _working ? null : _backup,
                    ),
                    AppButton(
                      label: 'Restore Backup',
                      icon: LucideIcons.upload,
                      variant: ButtonVariant.outline,
                      height: 48,
                      onPressed: _working ? null : _restore,
                    ),
                  ]),
                ),
                const SizedBox(height: 24),
                _SettingsCard(
                  icon: LucideIcons.info,
                  iconColor: p.primary,
                  title: 'About',
                  description: '$appName by $publisherName',
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    FutureBuilder<PackageInfo>(
                      future: PackageInfo.fromPlatform(),
                      builder: (_, snap) => Text(
                        snap.hasData ? 'Version ${snap.data!.version} (${snap.data!.buildNumber})' : 'Version',
                        style: TextStyle(fontSize: 14, color: p.mutedForeground),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(spacing: 12, runSpacing: 12, children: [
                      AppButton(
                        label: 'Privacy Policy',
                        icon: LucideIcons.shieldCheck,
                        variant: ButtonVariant.outline,
                        height: 48,
                        onPressed: () => _open(privacyPolicyUrl),
                      ),
                      AppButton(
                        label: 'thyantra.com',
                        icon: LucideIcons.globe,
                        variant: ButtonVariant.outline,
                        height: 48,
                        onPressed: () => _open(websiteUrl),
                      ),
                      AppButton(
                        label: 'Licences',
                        icon: LucideIcons.fileText,
                        variant: ButtonVariant.outline,
                        height: 48,
                        onPressed: () => showLicensePage(context: context, applicationName: appName),
                      ),
                    ]),
                  ]),
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
          Flexible(child: Text(title, style: display(22, color: p.foreground))),
        ]),
        const SizedBox(height: 6),
        Text(description, style: TextStyle(fontSize: 14, color: p.mutedForeground)),
        const SizedBox(height: 24),
        child,
      ]),
    );
  }
}
