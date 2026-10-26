import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/api_client.dart';
import '../../services/sync_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/common.dart';
import '../../widgets/toast.dart';

/// "Account & sync" in Settings: sign in or create a shop, see sync status,
/// sync now, sign out. Signed out, the app keeps working on this phone only.
class AccountPanel extends StatefulWidget {
  const AccountPanel({super.key});

  @override
  State<AccountPanel> createState() => _AccountPanelState();
}

class _AccountPanelState extends State<AccountPanel> {
  bool _busy = false;

  Future<void> _signIn({required bool createShop}) async {
    final ok = await showAppDialog<bool>(
      context,
      (_) => createShop ? const _CreateShopDialog() : const _SignInDialog(),
      dismissible: false,
    );
    if (ok == true && mounted) await _connect();
  }

  /// First sync after signing in: decide what happens to this phone's data.
  Future<void> _connect() async {
    final sync = context.read<SyncService>();
    setState(() => _busy = true);
    try {
      final plan = await sync.planFirstSync();
      if (plan == FirstSyncPlan.confirmReplace && !await _confirmReplace()) {
        await sync.signOut();
        if (mounted) {
          showToast(context, title: 'Signed out', description: 'Nothing on this phone was changed.');
        }
        return;
      }
      await sync.begin(plan);
      if (!mounted) return;
      showToast(
        context,
        title: 'Signed in',
        description: plan == FirstSyncPlan.upload
            ? "This phone's data is now your shop's data."
            : 'This phone is now in step with your shop.',
      );
    } on ApiException catch (e) {
      await sync.signOut();
      if (mounted) showToast(context, title: 'Could not connect', description: e.message, destructive: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmReplace() async {
    final result = await showAppDialog<bool>(
      context,
      (ctx) => AppDialog(
        showClose: false,
        title: const Text("Replace this phone's data?"),
        description: const Text(
          "The shop already has products, sales or customers. This phone's own records will be replaced "
          "with the shop's. Save a backup first if you want to keep a copy.",
        ),
        child: _DialogActions(
          confirmLabel: 'Replace',
          destructive: true,
          onCancel: () => Navigator.of(ctx).pop(false),
          onConfirm: () => Navigator.of(ctx).pop(true),
        ),
      ),
    );
    return result ?? false;
  }

  Future<void> _syncNow() async {
    final sync = context.read<SyncService>();
    await sync.syncNow();
    if (!mounted) return;
    if (sync.lastError == null) {
      showToast(context, title: 'Synced', description: 'This phone is up to date with your shop.');
    } else {
      showToast(context, title: 'Not synced', description: sync.lastError, destructive: true);
    }
  }

  Future<void> _signOut() async {
    final sync = context.read<SyncService>();
    setState(() => _busy = true);
    // Send what we can first.
    await sync.syncNow();
    if (!mounted) return;
    setState(() => _busy = false);
    final pending = sync.pendingCount;
    final result = await showAppDialog<bool>(
      context,
      (ctx) => AppDialog(
        showClose: false,
        title: const Text('Sign out?'),
        description: Text(
          'Your data stays on this phone and the app keeps working offline.'
          '${pending > 0 ? '\n\n${plural(pending, 'change')} could not be sent to the shop yet and will not be sent.' : ''}',
        ),
        child: _DialogActions(
          confirmLabel: 'Sign Out',
          destructive: pending > 0,
          onCancel: () => Navigator.of(ctx).pop(false),
          onConfirm: () => Navigator.of(ctx).pop(true),
        ),
      ),
    );
    if (result != true || !mounted) return;
    await sync.signOut();
    if (mounted) showToast(context, title: 'Signed out', description: 'This phone now works on its own.');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final auth = context.watch<AuthProvider>();
    final sync = context.watch<SyncService>();
    final muted = TextStyle(fontSize: 14, color: p.mutedForeground);

    if (!auth.isSignedIn) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            auth.sessionExpired
                ? 'You were signed out. Sign in again to send the changes made on this phone.'
                : 'Without an account, everything stays on this phone only.',
            style: muted,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              AppButton(
                label: 'Sign In',
                icon: LucideIcons.logIn,
                height: 48,
                onPressed: _busy ? null : () => _signIn(createShop: false),
              ),
              AppButton(
                label: 'Create Shop',
                icon: LucideIcons.store,
                variant: ButtonVariant.outline,
                height: 48,
                onPressed: _busy ? null : () => _signIn(createShop: true),
              ),
            ],
          ),
        ],
      );
    }

    final user = auth.user!;
    final last = sync.lastSyncedAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${user.name} · ${user.role == 'owner' ? 'Owner' : 'Cashier'}',
          style: TextStyle(fontWeight: FontWeight.w600, color: p.foreground),
        ),
        const SizedBox(height: 2),
        Text(user.email, style: muted),
        if (auth.shop != null) Text('Shop: ${auth.shop!.name}', style: muted),
        const SizedBox(height: 12),
        Text(
          sync.isSyncing || _busy
              ? 'Syncing…'
              : last == null
              ? 'Not synced yet'
              : 'Last synced ${dateTimeLocal.format(last)}',
          style: muted,
        ),
        if (sync.pendingCount > 0)
          Text(
            '${plural(sync.pendingCount, 'change')} waiting to be sent',
            style: TextStyle(fontSize: 14, color: p.warning),
          ),
        if (sync.lastError != null && !sync.isSyncing) Text(sync.lastError!, style: muted),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            AppButton(
              label: 'Sync Now',
              icon: LucideIcons.refreshCw,
              height: 48,
              onPressed: sync.isSyncing || _busy ? null : _syncNow,
            ),
            AppButton(
              label: 'Sign Out',
              icon: LucideIcons.logOut,
              variant: ButtonVariant.outline,
              height: 48,
              onPressed: _busy ? null : _signOut,
            ),
          ],
        ),
      ],
    );
  }
}

class _SignInDialog extends StatefulWidget {
  const _SignInDialog();

  @override
  State<_SignInDialog> createState() => _SignInDialogState();
}

class _SignInDialogState extends State<_SignInDialog> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Please enter your email and password');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthProvider>().signIn(email: _email.text, password: _password.text);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: const Text('Sign In'),
      description: const Text("Use the account you or your shop's owner created."),
      child: Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(label: 'Email', controller: _email, keyboardType: TextInputType.emailAddress, autofocus: true),
            const SizedBox(height: 16),
            _PasswordField(label: 'Password', controller: _password, error: _error),
            const SizedBox(height: 24),
            AppButton(
              label: _busy ? 'Signing in…' : 'Sign In',
              height: 48,
              expand: true,
              onPressed: _busy ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateShopDialog extends StatefulWidget {
  const _CreateShopDialog();

  @override
  State<_CreateShopDialog> createState() => _CreateShopDialogState();
}

class _CreateShopDialogState extends State<_CreateShopDialog> {
  late final _shopName = TextEditingController(text: context.read<SettingsProvider>().settings.shopName);
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _shopName.dispose();
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    String? error;
    if (_shopName.text.trim().isEmpty || _name.text.trim().isEmpty || _email.text.trim().isEmpty) {
      error = 'Please fill in every field';
    } else if (_password.text.length < 8) {
      error = 'Password must be at least 8 characters';
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthProvider>().signUp(
        shopName: _shopName.text,
        name: _name.text,
        email: _email.text,
        password: _password.text,
        currency: context.read<SettingsProvider>().settings.currency,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: const Text('Create Shop'),
      description: const Text('You become the owner. Add staff later from the website.'),
      child: Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(label: 'Shop Name', controller: _shopName),
            const SizedBox(height: 16),
            AppTextField(label: 'Your Name', controller: _name),
            const SizedBox(height: 16),
            AppTextField(label: 'Email', controller: _email, keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 16),
            _PasswordField(label: 'Password (8+ characters)', controller: _password, error: _error),
            const SizedBox(height: 24),
            AppButton(
              label: _busy ? 'Creating…' : 'Create Shop',
              height: 48,
              expand: true,
              onPressed: _busy ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

/// [AppTextField] with the text hidden.
class _PasswordField extends StatelessWidget {
  const _PasswordField({required this.label, required this.controller, this.error});
  final String label;
  final TextEditingController controller;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(label),
        const SizedBox(height: 8),
        SizedBox(
          height: 48,
          child: TextField(
            controller: controller,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            textAlignVertical: TextAlignVertical.center,
            style: TextStyle(fontSize: 14, color: p.foreground),
            decoration: InputDecoration(
              enabledBorder: error != null
                  ? OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: BorderSide(color: p.destructive),
                    )
                  : null,
            ),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 6),
          Text(error!, style: TextStyle(fontSize: 12, color: p.destructive)),
        ],
      ],
    );
  }
}

class _DialogActions extends StatelessWidget {
  const _DialogActions({
    required this.confirmLabel,
    required this.onCancel,
    required this.onConfirm,
    this.destructive = false,
  });
  final String confirmLabel;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;
  final bool destructive;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        AppButton(label: 'Cancel', variant: ButtonVariant.outline, onPressed: onCancel),
        const SizedBox(width: 8),
        AppButton(
          label: confirmLabel,
          variant: destructive ? ButtonVariant.destructive : ButtonVariant.gradient,
          onPressed: onConfirm,
        ),
      ],
    ),
  );
}
