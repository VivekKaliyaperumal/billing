import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_theme.dart';

/// shadcn `toast()` look-alike. Drawn on the root overlay so it shows above
/// open dialogs, like the web toaster.
void showToast(BuildContext context, {required String title, String? description, bool destructive = false}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => _Toast(
      title: title,
      description: description,
      destructive: destructive,
      onDismiss: () {
        if (entry.mounted) entry.remove();
      },
    ),
  );
  _current?.call();
  _current = () {
    if (entry.mounted) entry.remove();
  };
  overlay.insert(entry);
}

VoidCallback? _current;

class _Toast extends StatefulWidget {
  const _Toast({required this.title, this.description, required this.destructive, required this.onDismiss});
  final String title;
  final String? description;
  final bool destructive;
  final VoidCallback onDismiss;

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 250))..forward();

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 3), _close);
  }

  Future<void> _close() async {
    if (!mounted) return;
    await _c.reverse();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bg = widget.destructive ? p.destructive : p.card;
    final fg = widget.destructive ? Colors.white : p.foreground;
    final anim = CurvedAnimation(parent: _c, curve: Curves.easeOut);
    return Positioned(
      left: 16,
      right: 16,
      top: MediaQuery.of(context).padding.top + 12,
      child: FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, -0.4), end: Offset.zero).animate(anim),
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 16),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: widget.destructive ? p.destructive : p.border),
                boxShadow: p.shadowElevated,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(widget.title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: fg)),
                        if (widget.description != null) ...[
                          const SizedBox(height: 2),
                          Text(widget.description!, style: TextStyle(fontSize: 14, color: fg.withValues(alpha: 0.9))),
                        ],
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: _close,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(LucideIcons.x, size: 16, color: fg.withValues(alpha: 0.6)),
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
