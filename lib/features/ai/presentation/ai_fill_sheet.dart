import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../inventory/data/item.dart';

/// Preview sheet for an AI suggestion. All fields editable before applying.
/// Used by the manual form ("Fill automatically with AI") and by Bulk Review
/// ("Enrich with AI" per card).
Future<AiItemSuggestion?> showAiFillSheet(
  BuildContext context, {
  required Future<AiItemSuggestion> future,
  String title = 'AI Suggestion',
}) async {
  return showModalBottomSheet<AiItemSuggestion>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _AiFillSheet(future: future, title: title),
  );
}

class _AiFillSheet extends StatefulWidget {
  final Future<AiItemSuggestion> future;
  final String title;
  const _AiFillSheet({required this.future, required this.title});

  @override
  State<_AiFillSheet> createState() => _AiFillSheetState();
}

class _AiFillSheetState extends State<_AiFillSheet> {
  AiItemSuggestion? _suggestion;
  String? _error;
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _brand = TextEditingController();
  final _material = TextEditingController();
  final _tags = TextEditingController();
  String _category = 'lainnya';
  String? _condition;
  DateTime _start = DateTime.now();

  @override
  void initState() {
    super.initState();
    _start = DateTime.now();
    widget.future
        .then((s) async {
          // Minimum 600ms skeleton to avoid flicker.
          final elapsed = DateTime.now().difference(_start).inMilliseconds;
          if (elapsed < 600) {
            await Future<void>.delayed(Duration(milliseconds: 600 - elapsed));
          }
          if (!mounted) return;
          setState(() {
            _suggestion = s;
            _name.text = s.name;
            _desc.text = s.description ?? '';
            _brand.text = s.brand ?? '';
            _material.text = s.material ?? '';
            _tags.text = s.tags.join(', ');
            _category = s.category;
            _condition = s.condition;
          });
        })
        .catchError((Object e) {
          if (!mounted) return;
          setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
        });
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _brand.dispose();
    _material.dispose();
    _tags.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        if (_error != null) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 44,
                  color: AppColors.error,
                ),
                const SizedBox(height: 12),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                AppButton(
                  label: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          );
        }
        if (_suggestion == null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 130,
                  height: 130,
                  child: Lottie.asset(
                    'assets/lottie/ai_thinking.json',
                    errorBuilder: (_, _, _) =>
                        const CircularProgressIndicator(),
                  ),
                ),
                const SizedBox(height: 8),
                const Text('AI is looking at your photo…'),
              ],
            ),
          );
        }
        final s = _suggestion!;
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const AiBadge(),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            if (s.confidence < 0.5)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.secondary.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Please double-check — AI is not confident about this photo.',
                ),
              ),
            const SizedBox(height: 12),
            AppTextField(controller: _name, label: 'Name'),
            const SizedBox(height: 12),
            Text('Category', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final code in const [
                  'plastik',
                  'kertas_kardus',
                  'logam',
                  'kaca',
                  'kain_tekstil',
                  'kayu',
                  'elektronik',
                  'organik',
                  'lainnya',
                ])
                  TagChip(
                    label: _catLabel(code),
                    selected: _category == code,
                    onTap: () => setState(() => _category = code),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Condition', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                TagChip(
                  label: 'Not set',
                  selected: _condition == null,
                  onTap: () => setState(() => _condition = null),
                ),
                for (final code in const [
                  'baru',
                  'baik',
                  'cukup',
                  'rusak_ringan',
                  'rusak_berat',
                ])
                  TagChip(
                    label: _condLabel(code),
                    selected: _condition == code,
                    onTap: () => setState(() => _condition = code),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            AppTextField(controller: _tags, label: 'Tags (comma separated)'),
            const SizedBox(height: 12),
            AppTextField(controller: _desc, label: 'Description', maxLines: 3),
            const SizedBox(height: 12),
            AppTextField(controller: _brand, label: 'Brand (optional)'),
            const SizedBox(height: 12),
            AppTextField(controller: _material, label: 'Material (optional)'),
            const SizedBox(height: 20),
            AppButton(
              label: 'Apply',
              onPressed: () {
                String? clean(TextEditingController c) =>
                    c.text.trim().isEmpty ? null : c.text.trim();
                Navigator.of(context).pop(
                  AiItemSuggestion(
                    name: _name.text.trim().isEmpty
                        ? s.name
                        : _name.text.trim(),
                    category: _category,
                    tags: _tags.text
                        .split(',')
                        .map((t) => t.trim().toLowerCase())
                        .where((t) => t.isNotEmpty)
                        .take(6)
                        .toList(),
                    description: clean(_desc),
                    condition: _condition,
                    brand: clean(_brand),
                    material: clean(_material),
                    unitGuess: s.unitGuess,
                    quantityGuess: s.quantityGuess,
                    confidence: s.confidence,
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  String _catLabel(String code) {
    const m = {
      'plastik': 'Plastic',
      'kertas_kardus': 'Paper/Cardboard',
      'logam': 'Metal',
      'kaca': 'Glass',
      'kain_tekstil': 'Fabric/Textile',
      'kayu': 'Wood',
      'elektronik': 'Electronics',
      'organik': 'Organic',
      'lainnya': 'Other',
    };
    return m[code] ?? code;
  }

  String _condLabel(String code) {
    const m = {
      'baru': 'New',
      'baik': 'Good',
      'cukup': 'Fair',
      'rusak_ringan': 'Lightly Damaged',
      'rusak_berat': 'Heavily Damaged',
    };
    return m[code] ?? code;
  }
}
