import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_theme.dart';

/// Opens a shadcn-style dialog with the fade + scale-in (0.95 → 1) animation.
Future<T?> showAppDialog<T>(BuildContext context, WidgetBuilder builder) => showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.black.withValues(alpha: 0.8),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, _, _) => builder(ctx),
      transitionBuilder: (ctx, anim, _, child) {
        final a = CurvedAnimation(parent: anim, curve: Curves.easeOut);
        return FadeTransition(
          opacity: a,
          child: ScaleTransition(scale: Tween(begin: 0.95, end: 1.0).animate(a), child: child),
        );
      },
    );

/// Dialog body: card background, border, 16px radius, 24px padding, close ✕.
class AppDialog extends StatelessWidget {
  const AppDialog({super.key, required this.title, required this.child, this.showClose = true, this.description});

  final Widget title;
  final Widget? description;
  final Widget child;
  final bool showClose;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SafeArea(
      child: Center(
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 448),
            child: Material(
              color: p.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                side: BorderSide(color: p.border),
              ),
              elevation: 0,
              child: Stack(
                children: [
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: EdgeInsets.only(right: showClose ? 24 : 0),
                          child: DefaultTextStyle(
                            style: display(18, color: p.foreground),
                            child: title,
                          ),
                        ),
                        if (description != null) ...[
                          const SizedBox(height: 8),
                          DefaultTextStyle(
                            style: TextStyle(fontSize: 14, color: p.mutedForeground),
                            child: description!,
                          ),
                        ],
                        child,
                      ],
                    ),
                  ),
                  if (showClose)
                    Positioned(
                      right: 12,
                      top: 12,
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(LucideIcons.x, size: 16, color: p.foreground.withValues(alpha: 0.7)),
                        onPressed: () => Navigator.of(context).pop(),
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
