import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_theme.dart';

/// Shrinks to 0.98 while pressed (web `active:scale-[0.98]`).
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, this.onTap, this.enabled = true});
  final Widget child;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled && widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: active ? (_) => setState(() => _down = true) : null,
      onTapUp: active ? (_) => setState(() => _down = false) : null,
      onTapCancel: active ? () => setState(() => _down = false) : null,
      onTap: active ? widget.onTap : null,
      child: AnimatedScale(
        scale: _down ? 0.98 : 1,
        duration: const Duration(milliseconds: 100),
        child: widget.child,
      ),
    );
  }
}

enum ButtonVariant { gradient, outline, destructive, ghost }

/// shadcn `Button` look-alike.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.variant = ButtonVariant.gradient,
    this.gradient,
    this.color,
    this.height = 40,
    this.expand = false,
    this.shadow,
    this.fontSize = 14,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final ButtonVariant variant;

  /// Gradient for [ButtonVariant.gradient]; defaults to gradient-primary.
  final Gradient? gradient;

  /// Border/text colour for [ButtonVariant.outline]; defaults to foreground.
  final Color? color;
  final double height;
  final bool expand;
  final List<BoxShadow>? shadow;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final disabled = onPressed == null;
    late final Color fg;
    BoxDecoration deco;
    switch (variant) {
      case ButtonVariant.gradient:
        fg = Colors.white;
        deco = BoxDecoration(gradient: gradient ?? p.gradientPrimary, boxShadow: shadow);
      case ButtonVariant.destructive:
        fg = Colors.white;
        deco = BoxDecoration(color: p.destructive);
      case ButtonVariant.outline:
        fg = color ?? p.foreground;
        deco = BoxDecoration(color: p.background, border: Border.all(color: color ?? p.border));
      case ButtonVariant.ghost:
        fg = color ?? p.foreground;
        deco = const BoxDecoration();
    }
    deco = deco.copyWith(borderRadius: BorderRadius.circular(AppRadius.md));
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[Icon(icon, size: height >= 44 ? 20 : 16, color: fg), const SizedBox(width: 8)],
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: fg, fontWeight: FontWeight.w500, fontSize: fontSize),
          ),
        ),
      ],
    );
    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: PressScale(
        onTap: onPressed,
        child: Container(
          height: height,
          width: expand ? double.infinity : null,
          padding: EdgeInsets.symmetric(horizontal: height >= 44 ? 24 : 16),
          decoration: deco,
          child: content,
        ),
      ),
    );
  }
}

/// Small square icon button (ghost / outline).
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.size = 36,
    this.iconSize = 16,
    this.color,
    this.outlined = false,
    this.background,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final Color? color;
  final bool outlined;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Opacity(
      opacity: onPressed == null ? 0.5 : 1,
      child: Material(
        color: background ?? (outlined ? p.background : Colors.transparent),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          side: outlined ? BorderSide(color: p.border) : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, size: iconSize, color: color ?? p.mutedForeground),
          ),
        ),
      ),
    );
  }
}

/// Coloured square with an icon (e.g. `h-12 w-12 rounded-2xl gradient-primary`).
class GradientIconBox extends StatelessWidget {
  const GradientIconBox({
    super.key,
    required this.icon,
    required this.gradient,
    this.size = 48,
    this.iconSize = 24,
    this.radius = AppRadius.lg,
    this.shadow,
    this.circle = false,
  });

  final IconData icon;
  final Gradient gradient;
  final double size;
  final double iconSize;
  final double radius;
  final List<BoxShadow>? shadow;
  final bool circle;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: gradient,
          shape: circle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: circle ? null : BorderRadius.circular(radius),
          boxShadow: shadow,
        ),
        child: Icon(icon, size: iconSize, color: Colors.white),
      );
}

/// Page title block: gradient icon + Space Grotesk title + muted subtitle,
/// with an optional action that wraps below on narrow screens.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.icon,
    required this.gradient,
    required this.title,
    required this.subtitle,
    this.shadow,
    this.action,
  });

  final IconData icon;
  final Gradient gradient;
  final String title;
  final String subtitle;
  final List<BoxShadow>? shadow;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final heading = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GradientIconBox(icon: icon, gradient: gradient, shadow: shadow ?? p.shadowMedium),
        const SizedBox(width: 12),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: display(28, weight: FontWeight.w700, color: p.foreground)),
              Text(subtitle, style: TextStyle(color: p.mutedForeground, fontSize: 15)),
            ],
          ),
        ),
      ],
    );
    if (action == null) return heading;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 16,
      spacing: 16,
      children: [heading, action!],
    );
  }
}

/// shadcn `Card` with optional 4px top stripe or accent left border.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.stripe,
    this.stripeColor,
    this.leftBorderColor,
    this.shadow,
    this.gradient,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Gradient? stripe;
  final Color? stripeColor;
  final Color? leftBorderColor;
  final List<BoxShadow>? shadow;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget inner = Padding(padding: padding, child: child);
    if (stripe != null || stripeColor != null) {
      inner = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 4, decoration: BoxDecoration(gradient: stripe, color: stripeColor)),
          inner,
        ],
      );
    }
    if (leftBorderColor != null) {
      inner = IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [Container(width: 4, color: leftBorderColor), Expanded(child: inner)],
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: gradient == null ? p.card : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: p.border),
        boxShadow: shadow ?? p.shadowMedium,
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(AppRadius.lg - 1), child: inner),
    );
  }
}

/// Dashed rounded box (`border-2 border-dashed`), used for empty states.
class DashedBox extends StatelessWidget {
  const DashedBox({super.key, required this.child, this.padding = const EdgeInsets.all(48)});
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return CustomPaint(
      painter: _DashedPainter(p.border),
      child: Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: p.card.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: child,
      ),
    );
  }
}

class _DashedPainter extends CustomPainter {
  _DashedPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(AppRadius.lg));
    final path = Path()..addRRect(rrect.deflate(1));
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, math.min(d + 6, metric.length)), paint);
        d += 12;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedPainter old) => old.color != color;
}

/// Search input with a leading search icon.
class AppSearchField extends StatelessWidget {
  const AppSearchField({
    super.key,
    required this.hint,
    required this.onChanged,
    this.large = true,
  });

  final String hint;
  final ValueChanged<String> onChanged;

  /// `h-14 text-lg rounded-2xl` (true) vs `h-12` (false).
  final bool large;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final radius = BorderRadius.circular(large ? AppRadius.lg : AppRadius.md);
    return Container(
      height: large ? 56 : 48,
      decoration: BoxDecoration(borderRadius: radius, boxShadow: large ? p.shadowSoft : null),
      child: TextField(
        onChanged: onChanged,
        textAlignVertical: TextAlignVertical.center,
        style: TextStyle(fontSize: large ? 18 : 14, color: p.foreground),
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 16, right: 12),
            child: Icon(LucideIcons.search, size: 20, color: p.mutedForeground),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 48),
          contentPadding: EdgeInsets.zero,
          border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: p.border)),
          enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: p.border)),
          focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: p.primary, width: 2)),
        ),
      ),
    );
  }
}

/// Labelled text input (shadcn `Label` + `Input` with `h-12`).
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    this.label,
    required this.controller,
    this.hint,
    this.error,
    this.keyboardType,
    this.enabled = true,
    this.autofocus = false,
  });

  final String? label;
  final TextEditingController controller;
  final String? hint;
  final String? error;
  final TextInputType? keyboardType;
  final bool enabled;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[FieldLabel(label!), const SizedBox(height: 8)],
        SizedBox(
          height: 48,
          child: Opacity(
            opacity: enabled ? 1 : 0.5,
            child: TextField(
              controller: controller,
              enabled: enabled,
              autofocus: autofocus,
              keyboardType: keyboardType,
              textAlignVertical: TextAlignVertical.center,
              style: TextStyle(fontSize: 14, color: p.foreground),
              decoration: InputDecoration(
                hintText: hint,
                enabledBorder: error != null
                    ? OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        borderSide: BorderSide(color: p.destructive),
                      )
                    : null,
              ),
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

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: context.palette.foreground));
}

class SelectOption<T> {
  const SelectOption(this.value, this.label, {this.child});
  final T value;
  final String label;

  /// Optional custom row in the open menu.
  final Widget? child;
}

/// shadcn `Select` look-alike: input-style trigger with a chevron, opens a menu.
class AppSelect<T> extends StatelessWidget {
  const AppSelect({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.placeholder = 'Select',
    this.height = 40,
    this.width,
    this.leading,
  });

  final T? value;
  final List<SelectOption<T>> options;
  final ValueChanged<T> onChanged;
  final String placeholder;
  final double height;
  final double? width;
  final IconData? leading;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    SelectOption<T>? selected;
    for (final o in options) {
      if (o.value == value) selected = o;
    }
    return LayoutBuilder(builder: (context, c) {
      final w = width ?? c.maxWidth;
      return PopupMenuButton<T>(
        onSelected: onChanged,
        position: PopupMenuPosition.under,
        constraints: BoxConstraints(minWidth: w, maxWidth: math.max(w, 260)),
        tooltip: '',
        itemBuilder: (_) => [
          for (final o in options)
            PopupMenuItem<T>(
              value: o.value,
              height: 40,
              child: Row(
                children: [
                  Expanded(child: o.child ?? Text(o.label, style: TextStyle(fontSize: 14, color: p.foreground))),
                  if (o.value == value) Icon(LucideIcons.check, size: 16, color: p.foreground),
                ],
              ),
            ),
        ],
        child: Container(
          height: height,
          width: w,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: p.background,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: p.border),
          ),
          child: Row(
            children: [
              if (leading != null) ...[Icon(leading, size: 16, color: p.foreground), const SizedBox(width: 8)],
              Expanded(
                child: selected?.child ??
                    Text(
                      selected?.label ?? placeholder,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: selected == null ? p.mutedForeground : p.foreground),
                    ),
              ),
              Icon(LucideIcons.chevronDown, size: 16, color: p.mutedForeground.withValues(alpha: 0.7)),
            ],
          ),
        ),
      );
    });
  }
}

/// Faint radial-gradient page background (`.bg-pattern`).
class BgPattern extends StatelessWidget {
  const BgPattern({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    RadialGradient blob(Alignment at, Color c, double a, double stop) => RadialGradient(
          center: at,
          radius: 1.2,
          colors: [c.withValues(alpha: a), c.withValues(alpha: 0)],
          stops: [0, stop],
        );
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: Stack(children: [
              Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: blob(const Alignment(-0.6, -0.6), hsl(262, 83, 58), 0.05, 0.5)))),
              Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: blob(const Alignment(0.6, 0.6), hsl(340, 82, 52), 0.05, 0.5)))),
              Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: blob(const Alignment(-0.2, 0.2), hsl(160, 84, 39), 0.03, 0.4)))),
            ]),
          ),
        ),
        child,
      ],
    );
  }
}

/// Fade + slide-up on first build (web `animate-fade-in`).
class FadeIn extends StatelessWidget {
  const FadeIn({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        builder: (_, t, c) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 8 * (1 - t)), child: c)),
        child: child,
      );
}
