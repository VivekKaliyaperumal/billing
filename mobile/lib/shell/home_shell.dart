import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../screens/customers/customers_screen.dart';
import '../screens/history/history_screen.dart';
import '../screens/products/products_screen.dart';
import '../screens/sales/sales_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../theme/app_theme.dart';
import '../utils/storage.dart';
import '../widgets/common.dart';
import '../widgets/toast.dart';

class _NavItem {
  const _NavItem(this.label, this.icon);
  final String label;
  final IconData icon;
}

// Same order as the web Header.tsx nav.
const _navItems = [
  _NavItem('Sales', LucideIcons.shoppingCart),
  _NavItem('Products', LucideIcons.package),
  _NavItem('History', LucideIcons.chartColumn),
  _NavItem('Customers', LucideIcons.users),
  _NavItem('Settings', LucideIcons.settings),
];

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    storageIssues.addListener(_showStorageIssue);
    // Issues found while loading data happen before this screen exists.
    if (storageIssues.value != null) WidgetsBinding.instance.addPostFrameCallback((_) => _showStorageIssue());
  }

  @override
  void dispose() {
    storageIssues.removeListener(_showStorageIssue);
    super.dispose();
  }

  void _showStorageIssue() {
    final message = storageIssues.value;
    if (message == null || !mounted) return;
    showToast(context, title: 'Data problem', description: message, destructive: true);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // Android back returns to Sales from other tabs before leaving the app.
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _index = 0);
      },
      child: Scaffold(
      appBar: const _TopBar(),
      body: BgPattern(
        child: IndexedStack(
          index: _index,
          children: const [
            SalesScreen(),
            ProductsScreen(),
            HistoryScreen(),
            CustomersScreen(),
            SettingsScreen(),
          ],
        ),
      ),
      bottomNavigationBar: _Glass(
        border: Border(top: BorderSide(color: p.border)),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 68,
            child: Row(
              children: [
                for (var i = 0; i < _navItems.length; i++)
                  Expanded(
                    child: _NavButton(
                      item: _navItems[i],
                      active: i == _index,
                      onTap: () {
                        FocusScope.of(context).unfocus();
                        setState(() => _index = i);
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.item, required this.active, required this.onTap});
  final _NavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fg = active ? Colors.white : p.mutedForeground;
    return PressScale(
      onTap: onTap,
      semanticLabel: '${item.label} tab${active ? ', selected' : ''}',
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            gradient: active ? p.gradientPrimary : null,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            boxShadow: active ? p.shadowMedium : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(item.icon, size: 18, color: fg),
              const SizedBox(height: 3),
              Text(item.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Frosted header: gradient Store logo, shop name, theme toggle.
class _TopBar extends StatelessWidget implements PreferredSizeWidget {
  const _TopBar();

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final settings = context.watch<SettingsProvider>();
    return _Glass(
      border: Border(bottom: BorderSide(color: p.border)),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 64,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                GradientIconBox(
                  icon: LucideIcons.store,
                  gradient: p.gradientPrimary,
                  size: 40,
                  iconSize: 20,
                  radius: AppRadius.xl,
                  shadow: p.shadowMedium,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    settings.settings.shopName,
                    overflow: TextOverflow.ellipsis,
                    style: display(20, weight: FontWeight.w700, color: p.foreground),
                  ),
                ),
                _ThemeToggle(mode: settings.themeMode, onChanged: settings.setThemeMode),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemeToggle extends StatelessWidget {
  const _ThemeToggle({required this.mode, required this.onChanged});
  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    PopupMenuItem<ThemeMode> item(ThemeMode m, IconData icon, String label) => PopupMenuItem(
          value: m,
          height: 36,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: mode == m ? p.accent : null,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              Icon(icon, size: 16, color: mode == m ? Colors.white : p.foreground),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(fontSize: 14, color: mode == m ? Colors.white : p.foreground)),
            ]),
          ),
        );
    return PopupMenuButton<ThemeMode>(
      tooltip: 'Toggle theme',
      position: PopupMenuPosition.under,
      onSelected: onChanged,
      itemBuilder: (_) => [
        item(ThemeMode.light, LucideIcons.sun, 'Light'),
        item(ThemeMode.dark, LucideIcons.moon, 'Dark'),
      ],
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: p.background,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: p.border),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (c, a) => RotationTransition(turns: Tween(begin: -0.25, end: 0.0).animate(a), child: ScaleTransition(scale: a, child: c)),
          child: Icon(
            mode == ThemeMode.dark ? LucideIcons.moon : LucideIcons.sun,
            key: ValueKey(mode),
            size: 19,
            color: p.foreground,
          ),
        ),
      ),
    );
  }
}

/// `.glass`: card colour at 80% with backdrop blur.
class _Glass extends StatelessWidget {
  const _Glass({required this.child, required this.border});
  final Widget child;
  final Border border;

  @override
  Widget build(BuildContext context) => ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            decoration: BoxDecoration(color: context.palette.card.withValues(alpha: 0.8), border: border),
            child: child,
          ),
        ),
      );
}
