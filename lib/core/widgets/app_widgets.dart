import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../theme/app_theme.dart';
import '../utils/sfx.dart';

class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool ghost;
  final IconData? icon;

  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.ghost = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final child = loading
        ? const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: Colors.white,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 19),
                const SizedBox(width: 8),
              ],
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
            ],
          );
    final handler = loading
        ? null
        : (onPressed == null
              ? null
              : () {
                  Sfx.instance.tap();
                  onPressed!();
                });
    if (ghost) {
      return OutlinedButton(onPressed: handler, child: child);
    }
    return FilledButton(onPressed: handler, child: child);
  }
}

class AppTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String label;
  final String? hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final int maxLines;
  final String? Function(String?)? validator;
  final Widget? suffixIcon;
  final ValueChanged<String>? onChanged;

  const AppTextField({
    super.key,
    this.controller,
    required this.label,
    this.hint,
    this.obscure = false,
    this.keyboardType,
    this.maxLines = 1,
    this.validator,
    this.suffixIcon,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: suffixIcon,
      ),
    );
  }
}

/// Subtle checkerboard on mint — makes transparent cutout PNGs read as cutouts.
class CutoutBackground extends StatelessWidget {
  final Widget child;
  const CutoutBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _CheckerPainter(
        base: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1B2E22)
            : AppColors.accentMint,
        alt: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF20382A)
            : const Color(0xFFD9F0E2),
      ),
      child: child,
    );
  }
}

class _CheckerPainter extends CustomPainter {
  final Color base;
  final Color alt;
  _CheckerPainter({required this.base, required this.alt});

  @override
  void paint(Canvas canvas, Size size) {
    const cell = 14.0;
    canvas.drawRect(Offset.zero & size, Paint()..color = base);
    final paint = Paint()..color = alt;
    for (double y = 0; y < size.height; y += cell) {
      for (double x = 0; x < size.width; x += cell) {
        if (((x / cell).floor() + (y / cell).floor()) % 2 == 0) {
          canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CheckerPainter old) =>
      old.base != base || old.alt != alt;
}

class CutoutImage extends StatelessWidget {
  final String? cutoutUrl;
  final List<String> photoUrls;
  final String? originalUrl;
  final double? width;
  final double? height;
  final BoxFit fit;

  const CutoutImage({
    super.key,
    this.cutoutUrl,
    this.photoUrls = const [],
    this.originalUrl,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
  });

  String? get _url {
    if (cutoutUrl != null && cutoutUrl!.isNotEmpty) return cutoutUrl;
    if (photoUrls.isNotEmpty) return photoUrls.first;
    return originalUrl;
  }

  @override
  Widget build(BuildContext context) {
    final url = _url;
    return CutoutBackground(
      child: SizedBox(
        width: width,
        height: height,
        child: url == null
            ? Image.asset(
                'assets/images/placeholder_item.png',
                fit: fit,
                errorBuilder: (_, _, _) => const Center(
                  child: Icon(
                    Icons.image_not_supported_outlined,
                    color: AppColors.muted,
                  ),
                ),
              )
            : CachedNetworkImage(
                imageUrl: url,
                fit: fit,
                memCacheWidth: 600,
                placeholder: (_, _) =>
                    Image.asset('assets/images/placeholder_item.png', fit: fit),
                errorWidget: (_, _, _) => Image.asset(
                  'assets/images/placeholder_item.png',
                  fit: fit,
                  errorBuilder: (_, _, _) => const Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: AppColors.muted,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class TagChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Color? color;

  const TagChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: onTap == null ? null : (_) => onTap!(),
      selectedColor: c.withValues(alpha: 0.16),
      checkmarkColor: c,
      side: BorderSide(color: selected ? c : Theme.of(context).dividerColor),
    );
  }
}

class PriceTag extends StatelessWidget {
  final String text;
  const PriceTag(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.secondary.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF8A5A00),
          fontWeight: FontWeight.w800,
          fontSize: 13,
        ),
      ),
    );
  }
}

class AiBadge extends StatelessWidget {
  const AiBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, Color(0xFF0FA3A3)],
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome, size: 12, color: Colors.white),
          SizedBox(width: 4),
          Text(
            'AI',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final String lottieAsset;
  final String title;
  final String subtitle;
  final String? ctaLabel;
  final VoidCallback? onCta;

  const EmptyState({
    super.key,
    required this.lottieAsset,
    required this.title,
    required this.subtitle,
    this.ctaLabel,
    this.onCta,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          SizedBox(
            width: 160,
            height: 160,
            child: Lottie.asset(
              lottieAsset,
              errorBuilder: (_, _, _) => const Icon(
                Icons.recycling,
                size: 90,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          if (ctaLabel != null && onCta != null) ...[
            const SizedBox(height: 16),
            AppButton(label: ctaLabel!, onPressed: onCta),
          ],
        ],
      ),
    );
  }
}

class ShimmerCard extends StatelessWidget {
  const ShimmerCard({super.key});

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF20382A)
        : const Color(0xFFE2EEE6);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 4 / 3,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: base,
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Container(height: 12, width: 110, color: base),
            const SizedBox(height: 6),
            Container(height: 10, width: 70, color: base),
          ],
        ),
      ),
    );
  }
}

class ItemCard extends StatelessWidget {
  final String name;
  final String categoryLabel;
  final String? conditionLabel;
  final String? cutoutUrl;
  final List<String> photoUrls;
  final String? priceText;
  final String? badgeText;
  final VoidCallback? onTap;
  final Widget? trailing;

  const ItemCard({
    super.key,
    required this.name,
    required this.categoryLabel,
    this.conditionLabel,
    this.cutoutUrl,
    this.photoUrls = const [],
    this.priceText,
    this.badgeText,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 4 / 3,
              child: CutoutImage(cutoutUrl: cutoutUrl, photoUrls: photoUrls),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(
                            context,
                          ).textTheme.titleMedium?.copyWith(fontSize: 14.5),
                        ),
                      ),
                      ?trailing,
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      Chip(
                        label: Text(
                          categoryLabel,
                          style: const TextStyle(fontSize: 11),
                        ),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      if (conditionLabel != null)
                        Chip(
                          label: Text(
                            conditionLabel!,
                            style: const TextStyle(fontSize: 11),
                          ),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      if (badgeText != null)
                        Chip(
                          label: Text(
                            badgeText!,
                            style: const TextStyle(fontSize: 11),
                          ),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          backgroundColor: AppColors.secondary.withValues(
                            alpha: 0.2,
                          ),
                        ),
                    ],
                  ),
                  if (priceText != null) ...[
                    const SizedBox(height: 8),
                    PriceTag(priceText!),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
