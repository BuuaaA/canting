import 'package:canting/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';

abstract final class PixelPalette {
  static const forest = AppTheme.forest;
  static const forestDark = AppTheme.forestDark;
  static const leaf = AppTheme.leaf;
  static const sky = AppTheme.sky;
  static const skyDeep = AppTheme.skyDeep;
  static const paper = AppTheme.paper;
  static const paperShade = AppTheme.paperShade;
  static const sun = AppTheme.sun;
  static const tomato = AppTheme.tomato;
  static const wood = AppTheme.wood;
  static const woodDark = AppTheme.woodDark;
  static const ink = AppTheme.ink;
}

class PixelBackdrop extends StatelessWidget {
  const PixelBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surface,
      child: CustomPaint(
        painter: _PixelBackdropPainter(
          tileColor: theme.colorScheme.outlineVariant.withValues(
            alpha: theme.brightness == Brightness.dark ? 0.10 : 0.16,
          ),
        ),
        child: child,
      ),
    );
  }
}

class PixelContentWidth extends StatelessWidget {
  const PixelContentWidth({
    super.key,
    required this.child,
    this.maxWidth = 680,
    this.expandHeight = false,
  });

  final Widget child;
  final double maxWidth;
  final bool expandHeight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : maxWidth;
        final contentWidth = availableWidth > maxWidth
            ? maxWidth
            : availableWidth;
        final contentHeight = expandHeight && constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : null;
        return Align(
          alignment: Alignment.topCenter,
          heightFactor: expandHeight ? null : 1,
          child: SizedBox(
            width: contentWidth,
            height: contentHeight,
            child: child,
          ),
        );
      },
    );
  }
}

class PixelAppBar extends StatelessWidget implements PreferredSizeWidget {
  const PixelAppBar({
    super.key,
    required this.title,
    this.leading,
    this.actions = const [],
  });

  final String title;
  final Widget? leading;
  final List<Widget> actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: false,
      titleSpacing: 0,
      title: SizedBox(
        width: double.infinity,
        child: PixelContentWidth(
          child: Padding(
            padding: EdgeInsets.only(left: leading == null ? 16 : 4, right: 8),
            child: Row(
              children: [
                if (leading != null) ...[
                  SizedBox.square(dimension: 48, child: leading),
                  const SizedBox(width: 4),
                ],
                Expanded(child: Text(title)),
                ...actions,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PixelPanel extends StatelessWidget {
  const PixelPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.borderColor,
    this.shadowColor,
    this.onTap,
    this.semanticLabel,
    this.highlighted = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final Color? shadowColor;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final outline = borderColor ?? scheme.outline;
    final radius = BorderRadius.circular(3);
    final content = Container(
      margin: const EdgeInsets.only(right: 3, bottom: 3),
      decoration: BoxDecoration(
        color: color ?? scheme.surfaceContainerLowest,
        borderRadius: radius,
        border: Border.all(
          color: highlighted ? scheme.primary : outline,
          width: highlighted ? 3 : 2,
        ),
        boxShadow: [
          BoxShadow(
            color: shadowColor ?? outline.withValues(alpha: 0.72),
            offset: const Offset(3, 3),
            blurRadius: 0,
          ),
        ],
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(1),
          border: Border(
            top: BorderSide(
              color: Colors.white.withValues(
                alpha: Theme.of(context).brightness == Brightness.dark
                    ? 0.08
                    : 0.52,
              ),
            ),
            left: BorderSide(
              color: Colors.white.withValues(
                alpha: Theme.of(context).brightness == Brightness.dark
                    ? 0.08
                    : 0.52,
              ),
            ),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: radius),
          clipBehavior: Clip.antiAlias,
          child: onTap == null
              ? Padding(padding: padding, child: child)
              : InkWell(
                  onTap: onTap,
                  child: Padding(padding: padding, child: child),
                ),
        ),
      ),
    );

    if (semanticLabel == null) return content;
    return Semantics(
      label: semanticLabel,
      button: onTap != null,
      child: content,
    );
  }
}

class PixelSectionHeader extends StatelessWidget {
  const PixelSectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.icon,
  });

  final String title;
  final String? trailing;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        Container(
          width: 8,
          height: 20,
          decoration: BoxDecoration(
            color: scheme.primary,
            border: Border.all(color: scheme.outline, width: 1),
            boxShadow: [
              BoxShadow(
                color: scheme.outline,
                offset: const Offset(2, 0),
                blurRadius: 0,
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        if (icon != null) ...[
          Icon(icon, size: 19, color: scheme.primary),
          const SizedBox(width: 6),
        ],
        Expanded(child: Text(title, style: theme.textTheme.titleLarge)),
        if (trailing != null)
          Text(
            trailing!,
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

class PixelIconTile extends StatelessWidget {
  const PixelIconTile({
    super.key,
    required this.icon,
    this.color,
    this.foregroundColor,
    this.size = 42,
  });

  final IconData icon;
  final Color? color;
  final Color? foregroundColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color ?? scheme.secondaryContainer,
        border: Border.all(color: scheme.outline, width: 2),
        boxShadow: [
          BoxShadow(
            color: scheme.outline.withValues(alpha: 0.65),
            offset: const Offset(2, 2),
            blurRadius: 0,
          ),
        ],
      ),
      child: Icon(
        icon,
        size: size * 0.50,
        color: foregroundColor ?? scheme.onSecondaryContainer,
      ),
    );
  }
}

class PixelBadge extends StatelessWidget {
  const PixelBadge({
    super.key,
    required this.label,
    this.icon,
    this.backgroundColor,
    this.foregroundColor,
    this.pixelText = false,
  });

  final String label;
  final IconData? icon;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final bool pixelText;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = foregroundColor ?? scheme.onSecondaryContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: backgroundColor ?? scheme.secondaryContainer,
        border: Border.all(color: scheme.outline),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: pixelText
                ? AppTheme.pixelText(context, fontSize: 8, color: foreground)
                : Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w800,
                  ),
          ),
        ],
      ),
    );
  }
}

class PixelProgressBar extends StatelessWidget {
  const PixelProgressBar({
    super.key,
    required this.value,
    this.segments = 10,
    this.color,
    this.height = 12,
    this.semanticLabel,
  }) : assert(segments > 0);

  final double value;
  final int segments;
  final Color? color;
  final double height;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = value.clamp(0.0, 1.0);
    final filled = (progress * segments).ceil();
    final bar = Row(
      children: [
        for (var index = 0; index < segments; index++) ...[
          Expanded(
            child: Container(
              height: height,
              decoration: BoxDecoration(
                color: index < filled
                    ? color ?? scheme.primary
                    : scheme.surfaceContainerHighest,
                border: Border.all(
                  color: index < filled
                      ? scheme.outline.withValues(alpha: 0.72)
                      : scheme.outlineVariant,
                ),
              ),
            ),
          ),
          if (index != segments - 1) const SizedBox(width: 2),
        ],
      ],
    );
    return Semantics(
      label: semanticLabel ?? '完成 ${(value * 100).round()}%',
      value: '${(value * 100).round()}%',
      child: ExcludeSemantics(child: bar),
    );
  }
}

class PixelMetric extends StatelessWidget {
  const PixelMetric({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = color ?? scheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: accent),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: AppTheme.pixelText(
                context,
                fontSize: 10,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ],
    );
  }
}

class PixelDivider extends StatelessWidget {
  const PixelDivider({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(
        18,
        (index) => Expanded(
          child: Container(
            height: 2,
            color: index.isEven
                ? color ?? Theme.of(context).colorScheme.outlineVariant
                : Colors.transparent,
          ),
        ),
      ),
    );
  }
}

class _PixelBackdropPainter extends CustomPainter {
  const _PixelBackdropPainter({required this.tileColor});

  final Color tileColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = tileColor
      ..isAntiAlias = false;
    const step = 28.0;
    for (var y = 12.0; y < size.height; y += step) {
      final row = (y / step).round();
      final offset = row.isEven ? 12.0 : 26.0;
      for (var x = offset; x < size.width; x += step) {
        canvas.drawRect(Rect.fromLTWH(x, y, 2, 2), paint);
        if ((x / step).round().isEven) {
          canvas.drawRect(Rect.fromLTWH(x + 3, y + 3, 1, 1), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PixelBackdropPainter oldDelegate) {
    return oldDelegate.tileColor != tileColor;
  }
}
