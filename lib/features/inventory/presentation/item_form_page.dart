import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../core/utils/labels.dart';
import '../../../core/utils/sfx.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../ai/data/ai_repository.dart';
import '../../ai/presentation/ai_fill_sheet.dart';
import '../../auth/data/auth_repository.dart';
import '../../segment/data/bulk_draft.dart';
import '../../segment/data/segmentation_service.dart';
import '../data/item.dart';
import '../data/item_repository.dart';

class _Photo {
  final Uint8List bytes;
  const _Photo(this.bytes);
}

class ItemFormPage extends ConsumerStatefulWidget {
  final String? itemId;
  final bool startScan;
  const ItemFormPage({super.key, this.itemId, this.startScan = false});

  @override
  ConsumerState<ItemFormPage> createState() => _ItemFormPageState();
}

class _ItemFormPageState extends ConsumerState<ItemFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _brand = TextEditingController();
  final _material = TextEditingController();
  final _tagInput = TextEditingController();
  final List<_Photo> _photos = [];
  final List<String> _remotePhotos = [];
  List<String> _tags = [];
  String _category = 'lainnya';
  String? _condition;
  String _unit = 'satuan';
  int _quantity = 1;
  bool _saving = false;
  bool _loadingItem = false;
  bool _scanStarted = false;
  Item? _editing;

  bool get _isEdit => widget.itemId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) _loadItem();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.startScan && !_isEdit && !_scanStarted) {
        _scanStarted = true;
        _startScanFlow();
      }
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _brand.dispose();
    _material.dispose();
    _tagInput.dispose();
    super.dispose();
  }

  Future<void> _loadItem() async {
    setState(() => _loadingItem = true);
    final item = await ref
        .read(itemRepositoryProvider)
        .fetchItem(widget.itemId!);
    if (!mounted) return;
    if (item != null) {
      _editing = item;
      _name.text = item.name;
      _desc.text = item.description ?? '';
      _brand.text = item.brand ?? '';
      _material.text = item.material ?? '';
      _tags = [...item.tags];
      _category = item.category;
      _condition = item.condition;
      _unit = item.unit;
      _quantity = item.quantity;
      _remotePhotos.addAll(item.photoUrls);
    }
    setState(() => _loadingItem = false);
  }

  Future<Uint8List> _compress(Uint8List bytes, {int maxSide = 1280}) async {
    try {
      final out = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: maxSide,
        minHeight: maxSide,
        quality: 80,
        format: CompressFormat.jpeg,
      );
      return out.isEmpty ? bytes : out;
    } catch (_) {
      return bytes;
    }
  }

  Future<void> _pickPhotos(ImageSource source) async {
    final picker = ImagePicker();
    if (source == ImageSource.camera) {
      final file = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
      );
      if (file == null) return;
      Sfx.instance.shutter();
      final raw = await file.readAsBytes();
      final compressed = await _compress(raw);
      if (!mounted) return;
      setState(() {
        if (_photos.length < 5) _photos.add(_Photo(compressed));
      });
    } else {
      final files = await picker.pickMultiImage(maxWidth: 1920, limit: 5);
      if (files.isEmpty) return;
      for (final f in files) {
        if (_photos.length + _remotePhotos.length >= 5) break;
        final raw = await f.readAsBytes();
        final compressed = await _compress(raw);
        _photos.add(_Photo(compressed));
      }
      if (mounted) setState(() {});
    }
  }

  int get _totalPhotos => _photos.length + _remotePhotos.length;
  bool get _canSave => _totalPhotos >= 1 && !_saving;

  // ---------- SAM scan flow ----------
  Future<void> _startScanFlow() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 2000,
    );
    // If camera cancelled on web/desktop, fall back to gallery.
    final picked =
        file ??
        await picker.pickImage(source: ImageSource.gallery, maxWidth: 2000);
    if (picked == null) return;
    Sfx.instance.shutter();
    final raw = await picked.readAsBytes();
    final sourceBytes = await _compress(raw, maxSide: 1600);
    if (!mounted) return;
    await _runSegmentation(sourceBytes);
  }

  Future<void> _runSegmentation(Uint8List sourceBytes) async {
    final profile = ref.read(currentProfileProvider);
    if (profile == null) return;
    final batchId = const Uuid().v4();
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(child: Text('AI is separating your items…')),
          ],
        ),
      ),
    );
    try {
      final itemRepo = ref.read(itemRepositoryProvider);
      final aiRepo = ref.read(aiRepositoryProvider);
      final sourceUrl = await itemRepo.uploadDraftPhoto(
        profile.id,
        batchId,
        'source.jpg',
        sourceBytes,
      );

      List<String> prompts;
      bool usedFallback = false;
      Map<String, String> catByPrompt = {};
      Map<String, String> labelByPrompt = {};
      try {
        final suggestions = await aiRepo.suggestPrompts(sourceUrl);
        if (suggestions.isEmpty) throw Exception('empty');
        prompts = suggestions.map((s) => s.prompt).toSet().take(12).toList();
        for (final s in suggestions) {
          catByPrompt[s.prompt] = s.categoryGuess;
          labelByPrompt[s.prompt] = s.label;
        }
      } catch (_) {
        prompts = fallbackPrompts;
        usedFallback = true;
      }

      final instances = await aiRepo.segment(
        sourceUrl,
        prompts,
        batchId: batchId,
      );
      if (instances.isEmpty) throw Exception('No items were detected.');

      // Build cutouts (max 4 parallel isolates via chunked awaits).
      final segService = SegmentationService();
      final drafts = <BulkDraft>[];
      for (int i = 0; i < instances.length; i++) {
        final inst = instances[i];
        Uint8List? maskBytes;
        if (inst.maskUrl.isNotEmpty) maskBytes = await fetchBytes(inst.maskUrl);
        final result = await segService.makeCutout(
          sourceBytes: sourceBytes,
          maskBytes: maskBytes,
          x: inst.x,
          y: inst.y,
          w: inst.w,
          h: inst.h,
        );
        drafts.add(
          BulkDraft(
            localId: const Uuid().v4(),
            prompt: inst.prompt,
            label: inst.label.isNotEmpty
                ? inst.label
                : (labelByPrompt[inst.prompt] ?? inst.prompt),
            categoryGuess: catByPrompt[inst.prompt] ?? 'lainnya',
            confidence: inst.confidence,
            x: inst.x,
            y: inst.y,
            w: inst.w,
            h: inst.h,
            maskUrl: inst.maskUrl,
            cutoutBytes: result.pngBytes,
            cutoutOk: result.usedCutout,
            selected: inst.confidence >= 0.5,
            name: inst.label.isNotEmpty
                ? inst.label
                : (labelByPrompt[inst.prompt] ?? 'Used Item'),
            category: catByPrompt[inst.prompt] ?? 'lainnya',
            quantity: 1,
          ),
        );
      }

      ref
          .read(bulkDraftProvider.notifier)
          .setState(
            BulkDraftState(
              batchId: batchId,
              sourcePhotoUrl: sourceUrl,
              sourceBytes: sourceBytes,
              drafts: drafts,
              usedFallbackPrompts: usedFallback,
            ),
          );
      if (!mounted) return;
      Navigator.of(context).pop(); // close progress
      context.push('/items/bulk-review');
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      final goManual = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Automatic separation failed'),
          content: const Text(
            'Segmentation was not successful. You can fill in the item manually — your photo will be carried over.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Try Again'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Fill Manually'),
            ),
          ],
        ),
      );
      if (goManual == true && mounted) {
        setState(() {
          _photos.add(_Photo(sourceBytes));
        });
      } else if (goManual == false && mounted) {
        await _runSegmentation(sourceBytes);
      }
    }
  }

  // ---------- AI auto-fill (manual form) ----------
  Future<void> _aiFill() async {
    final profile = ref.read(currentProfileProvider);
    if (profile == null || _totalPhotos == 0) return;
    try {
      List<String> urls;
      if (_remotePhotos.isNotEmpty && _photos.isEmpty) {
        urls = List.of(_remotePhotos);
      } else {
        final draftId = const Uuid().v4();
        urls = [];
        for (int i = 0; i < _photos.length; i++) {
          final u = await ref
              .read(itemRepositoryProvider)
              .uploadDraftPhoto(
                profile.id,
                draftId,
                '$i.jpg',
                _photos[i].bytes,
              );
          if (u.isNotEmpty) urls.add(u);
        }
        if (urls.isEmpty && _remotePhotos.isNotEmpty) {
          urls = List.of(_remotePhotos);
        }
      }
      if (urls.isEmpty) throw Exception('Please add a photo first.');
      if (!mounted) return;
      final applied = await showAiFillSheet(
        context,
        future: ref.read(aiRepositoryProvider).analyzeItem(urls),
      );
      if (applied == null || !mounted) return;
      setState(() {
        _name.text = applied.name;
        _category = applied.category;
        _condition = applied.condition;
        _tags = [...applied.tags];
        if (applied.description != null) _desc.text = applied.description!;
        if (applied.brand != null) _brand.text = applied.brand!;
        if (applied.material != null) _material.text = applied.material!;
        _unit = applied.unitGuess;
        _quantity = applied.quantityGuess;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_totalPhotos < 1) return;
    final profile = ref.read(currentProfileProvider);
    if (profile == null) return;
    setState(() => _saving = true);
    final itemRepo = ref.read(itemRepositoryProvider);
    final uploadedUrls = <String>[];
    try {
      final itemId = _editing?.id ?? const Uuid().v4();
      final photoUrls = <String>[..._remotePhotos];
      for (int i = 0; i < _photos.length; i++) {
        final url = await itemRepo.uploadPhoto(
          profile.id,
          itemId,
          '${photoUrls.length}.jpg',
          _photos[i].bytes,
        );
        if (url.isNotEmpty) {
          photoUrls.add(url);
          uploadedUrls.add(url);
        }
      }
      if (photoUrls.isEmpty) {
        throw Exception('Photo upload failed. Please try again.');
      }

      final item = Item(
        id: itemId,
        ownerId: profile.id,
        name: _name.text.trim(),
        category: _category,
        tags: _tags,
        description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        condition: _condition,
        brand: _brand.text.trim().isEmpty ? null : _brand.text.trim(),
        material: _material.text.trim().isEmpty ? null : _material.text.trim(),
        unit: _unit,
        quantity: _quantity,
        photoUrls: photoUrls,
        originalPhotoUrl: _editing?.originalPhotoUrl,
        cutoutPhotoUrl: _editing?.cutoutPhotoUrl,
        segmentation: _editing?.segmentation,
        status: _editing?.status ?? 'tersedia',
        isPublished: _editing?.isPublished ?? false,
        createdAt: _editing?.createdAt,
      );
      if (_isEdit) {
        await itemRepo.updateItem(item);
      } else {
        await itemRepo.createItem(item);
      }
      Sfx.instance.success();
      ref.invalidate(myItemsProvider);
      if (!mounted) return;
      if (_isEdit) {
        context.pop();
      } else {
        context.go('/items/${item.id}');
      }
    } catch (e) {
      // No orphan rows: insert happens last; remove freshly uploaded files on failure.
      if (uploadedUrls.isNotEmpty) {
        await itemRepo.removeByUrls(uploadedUrls);
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _addTag(String raw) {
    final t = raw.trim().toLowerCase();
    if (t.isEmpty || _tags.contains(t) || _tags.length >= 8) return;
    setState(() => _tags = [..._tags, t]);
    _tagInput.clear();
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingItem) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit Item')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit Item' : 'Add Item')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            if (!_isEdit) ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _startScanFlow,
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Scan & Separate Automatically'),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'One photo with many items → AI separates them into individual catalog items.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 18),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'Or add one item manually',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
            ],
            Text(
              'Photos * (max 5)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (int i = 0; i < _remotePhotos.length; i++)
                  _Thumb(
                    url: _remotePhotos[i],
                    onRemove: () => setState(() => _remotePhotos.removeAt(i)),
                  ),
                for (int i = 0; i < _photos.length; i++)
                  _Thumb(
                    bytes: _photos[i].bytes,
                    onRemove: () => setState(() => _photos.removeAt(i)),
                  ),
                if (_totalPhotos < 5)
                  InkWell(
                    onTap: () => _pickPhotos(ImageSource.gallery),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).dividerColor,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate_outlined),
                          SizedBox(height: 4),
                          Text('Add', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickPhotos(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt_outlined, size: 18),
                    label: const Text('Camera'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickPhotos(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined, size: 18),
                    label: const Text('Gallery'),
                  ),
                ),
              ],
            ),
            if (_totalPhotos == 0)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Photo is required — an item without a photo cannot be saved.',
                  style: TextStyle(color: Colors.red, fontSize: 13),
                ),
              ),
            if (_totalPhotos >= 1) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _saving ? null : _aiFill,
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('Fill automatically with AI'),
              ),
            ],
            const SizedBox(height: 18),
            AppTextField(
              controller: _name,
              label: 'Name *',
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Name is required.' : null,
            ),
            const SizedBox(height: 14),
            Text('Category *', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in Labels.categories.entries)
                  TagChip(
                    label: e.value,
                    selected: _category == e.key,
                    onTap: () => setState(() => _category = e.key),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Tags (max 8, press Enter or comma)',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: [
                for (final t in _tags)
                  Chip(
                    label: Text(t),
                    onDeleted: () => setState(
                      () => _tags = _tags.where((x) => x != t).toList(),
                    ),
                  ),
              ],
            ),
            TextField(
              controller: _tagInput,
              decoration: const InputDecoration(hintText: 'Add a tag…'),
              onSubmitted: _addTag,
              onChanged: (v) {
                if (v.endsWith(',')) _addTag(v.substring(0, v.length - 1));
              },
            ),
            const SizedBox(height: 14),
            AppTextField(
              controller: _desc,
              label: 'Description (optional)',
              maxLines: 3,
            ),
            const SizedBox(height: 14),
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
                for (final e in Labels.conditions.entries)
                  TagChip(
                    label: e.value,
                    selected: _condition == e.key,
                    onTap: () => setState(() => _condition = e.key),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            AppTextField(controller: _brand, label: 'Brand (optional)'),
            const SizedBox(height: 14),
            AppTextField(
              controller: _material,
              label: 'Material (optional)',
              hint: 'e.g. PP plastic, iron, cotton',
            ),
            const SizedBox(height: 14),
            Text('Unit', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in Labels.units.entries)
                  TagChip(
                    label: e.value,
                    selected: _unit == e.key,
                    onTap: () => setState(() => _unit = e.key),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Text('Quantity', style: Theme.of(context).textTheme.labelLarge),
                const Spacer(),
                IconButton(
                  tooltip: 'Decrease quantity',
                  onPressed: _quantity > 1
                      ? () => setState(() => _quantity--)
                      : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text(
                  '$_quantity',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                IconButton(
                  tooltip: 'Increase quantity',
                  onPressed: () => setState(() => _quantity++),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            const SizedBox(height: 20),
            AppButton(
              label: _isEdit ? 'Save Changes' : 'Save Item',
              onPressed: _canSave ? _save : null,
              loading: _saving,
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final Uint8List? bytes;
  final String? url;
  final VoidCallback onRemove;
  const _Thumb({this.bytes, this.url, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: bytes != null
              ? Image.memory(bytes!, width: 96, height: 96, fit: BoxFit.cover)
              : Image.network(
                  url ?? '',
                  width: 96,
                  height: 96,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    width: 96,
                    height: 96,
                    color: const Color(0xFFE6F7EE),
                    child: const Icon(Icons.broken_image_outlined),
                  ),
                ),
        ),
        Positioned(
          top: 2,
          right: 2,
          child: IconButton(
            tooltip: 'Remove photo',
            style: IconButton.styleFrom(
              backgroundColor: Colors.black54,
              foregroundColor: Colors.white,
              padding: EdgeInsets.zero,
              minimumSize: const Size(28, 28),
            ),
            onPressed: onRemove,
            icon: const Icon(Icons.close, size: 16),
          ),
        ),
      ],
    );
  }
}
