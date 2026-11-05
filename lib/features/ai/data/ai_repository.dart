import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/api/api_client.dart';
import '../../../core/config/env.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../inventory/data/item.dart';

class AiSuggestionResult {
  final AiItemSuggestion suggestion;
  const AiSuggestionResult(this.suggestion);
}

class SegmentObjectSuggestion {
  final String label;
  final String prompt;
  final String categoryGuess;
  const SegmentObjectSuggestion({
    required this.label,
    required this.prompt,
    required this.categoryGuess,
  });
  factory SegmentObjectSuggestion.fromJson(Map<String, dynamic> j) =>
      SegmentObjectSuggestion(
        label: (j['label'] ?? '').toString(),
        prompt: (j['prompt'] ?? '').toString(),
        categoryGuess: (j['categoryGuess'] ?? 'lainnya').toString(),
      );
}

class SegmentInstance {
  final String prompt;
  final String label;
  final double confidence;
  final double x, y, w, h;
  final String maskUrl;
  const SegmentInstance({
    required this.prompt,
    required this.label,
    required this.confidence,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.maskUrl,
  });
  factory SegmentInstance.fromJson(Map<String, dynamic> j) {
    final bbox = j['bbox'] is Map
        ? Map<String, dynamic>.from(j['bbox'] as Map)
        : <String, dynamic>{};
    double d(dynamic v) => (v as num?)?.toDouble() ?? 0;
    return SegmentInstance(
      prompt: (j['prompt'] ?? '').toString(),
      label: (j['label'] ?? '').toString(),
      confidence: d(j['confidence']),
      x: d(bbox['x']),
      y: d(bbox['y']),
      w: d(bbox['w']),
      h: d(bbox['h']),
      maskUrl: (j['maskUrl'] ?? '').toString(),
    );
  }
}

class FuseIdea {
  final String title;
  final String description;
  final List<String> steps;
  final String difficulty;
  final int? estimatedMinutes;
  final List<Map<String, dynamic>> usedItems;
  final List<Map<String, dynamic>> missingItems;
  final String imagePrompt;
  const FuseIdea({
    required this.title,
    required this.description,
    required this.steps,
    required this.difficulty,
    this.estimatedMinutes,
    required this.usedItems,
    required this.missingItems,
    required this.imagePrompt,
  });
  factory FuseIdea.fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> maps(dynamic v) => v is List
        ? v
              .whereType<Map>()
              .map((e) => e.map((k, val) => MapEntry(k.toString(), val)))
              .toList()
        : <Map<String, dynamic>>[];
    List<String> strs(dynamic v) =>
        v is List ? v.map((e) => e.toString()).toList() : <String>[];
    return FuseIdea(
      title: (j['title'] ?? '').toString(),
      description: (j['description'] ?? '').toString(),
      steps: strs(j['steps']),
      difficulty: (j['difficulty'] ?? 'mudah').toString(),
      estimatedMinutes: (j['estimatedMinutes'] as num?)?.toInt(),
      usedItems: maps(j['usedItems']),
      missingItems: maps(j['missingItems']),
      imagePrompt: (j['imagePrompt'] ?? '').toString(),
    );
  }
}

String _functionError(Object e) {
  if (e is FunctionException) {
    try {
      final details = e.details;
      if (details is String && details.isNotEmpty) {
        final decoded = jsonDecode(details);
        if (decoded is Map && decoded['error'] != null) {
          return decoded['error'].toString();
        }
      }
      if (details is Map && details['error'] != null) {
        return details['error'].toString();
      }
    } catch (_) {}
    if (e.status == 401) return 'Session expired. Please sign in again.';
    return 'AI service is temporarily unavailable.';
  }
  return 'AI service is temporarily unavailable.';
}

class AiRepository {
  bool get _demo => Env.demoMode;
  bool get _backend => Env.useBackend;

  Future<AiItemSuggestion> analyzeItem(List<String> imageUrls) async {
    if (_backend) {
      try {
        final data = await apiClient.postJson('/v1/ai/analyze-item', {
          'imageUrls': imageUrls,
          'locale': 'en',
        });
        return AiItemSuggestion.fromJson(asJsonMap(data));
      } on ApiException catch (e) {
        throw Exception(e.message);
      } catch (_) {
        throw Exception('AI service is temporarily unavailable.');
      }
    }
    if (_demo) {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      return const AiItemSuggestion(
        name: 'Plastic Bottle',
        category: 'plastik',
        tags: ['bottle', 'plastic', 'pet'],
        description:
            'A used plastic bottle in fairly good condition, suitable for recycling or upcycling.',
        condition: 'baik',
        material: 'PET plastic',
        unitGuess: 'satuan',
        quantityGuess: 1,
        confidence: 0.92,
      );
    }
    try {
      final res = await supabase.functions.invoke(
        'ai-analyze-item',
        body: {'imageUrls': imageUrls, 'locale': 'en'},
      );
      final data = res.data;
      if (data is Map<String, dynamic>) return AiItemSuggestion.fromJson(data);
      if (data is Map) {
        return AiItemSuggestion.fromJson(
          data.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
      throw Exception('AI service is temporarily unavailable.');
    } catch (e) {
      throw Exception(_functionError(e));
    }
  }

  Future<List<SegmentObjectSuggestion>> suggestPrompts(String imageUrl) async {
    if (_backend) {
      try {
        final data = await apiClient.postJson('/v1/ai/suggest-prompts', {
          'imageUrl': imageUrl,
        });
        final list = data is Map
            ? (data['objects'] as List? ?? const [])
            : const [];
        return list
            .whereType<Map>()
            .map(
              (e) => SegmentObjectSuggestion.fromJson(
                e.map((k, v) => MapEntry(k.toString(), v)),
              ),
            )
            .toList();
      } on ApiException catch (e) {
        throw Exception(e.message);
      } catch (_) {
        throw Exception('AI service is temporarily unavailable.');
      }
    }
    if (_demo) {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      return const [
        SegmentObjectSuggestion(
          label: 'Plastic Bottle',
          prompt: 'plastic bottle',
          categoryGuess: 'plastik',
        ),
        SegmentObjectSuggestion(
          label: 'Cardboard Box',
          prompt: 'cardboard box',
          categoryGuess: 'kertas_kardus',
        ),
        SegmentObjectSuggestion(
          label: 'Tin Can',
          prompt: 'tin can',
          categoryGuess: 'logam',
        ),
      ];
    }
    try {
      final res = await supabase.functions.invoke(
        'ai-suggest-prompts',
        body: {'imageUrl': imageUrl},
      );
      final data = res.data;
      final list = data is Map
          ? (data['objects'] as List? ?? const [])
          : const [];
      return list
          .whereType<Map>()
          .map(
            (e) => SegmentObjectSuggestion.fromJson(
              e.map((k, v) => MapEntry(k.toString(), v)),
            ),
          )
          .toList();
    } catch (e) {
      throw Exception(_functionError(e));
    }
  }

  Future<List<SegmentInstance>> segment(
    String imageUrl,
    List<String> prompts, {
    String? batchId,
  }) async {
    if (_backend) {
      try {
        final data = await apiClient.postJson('/v1/ai/segment', {
          'imageUrl': imageUrl,
          'prompts': prompts,
          'batchId': ?batchId,
        });
        final list = data is Map
            ? (data['instances'] as List? ?? const [])
            : const [];
        return list
            .whereType<Map>()
            .map(
              (e) => SegmentInstance.fromJson(
                e.map((k, v) => MapEntry(k.toString(), v)),
              ),
            )
            .toList();
      } on ApiException catch (e) {
        throw Exception(e.message);
      } catch (_) {
        throw Exception('AI service is temporarily unavailable.');
      }
    }
    if (_demo) {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      return const [
        SegmentInstance(
          prompt: 'plastic bottle',
          label: 'Plastic Bottle',
          confidence: 0.94,
          x: 0.08,
          y: 0.15,
          w: 0.25,
          h: 0.6,
          maskUrl: '',
        ),
        SegmentInstance(
          prompt: 'plastic bottle',
          label: 'Plastic Bottle',
          confidence: 0.89,
          x: 0.36,
          y: 0.18,
          w: 0.22,
          h: 0.55,
          maskUrl: '',
        ),
        SegmentInstance(
          prompt: 'cardboard box',
          label: 'Cardboard Box',
          confidence: 0.91,
          x: 0.62,
          y: 0.25,
          w: 0.3,
          h: 0.5,
          maskUrl: '',
        ),
        SegmentInstance(
          prompt: 'tin can',
          label: 'Tin Can',
          confidence: 0.42,
          x: 0.45,
          y: 0.6,
          w: 0.14,
          h: 0.22,
          maskUrl: '',
        ),
      ];
    }
    try {
      final res = await supabase.functions.invoke(
        'ai-segment',
        body: {'imageUrl': imageUrl, 'prompts': prompts, 'batchId': ?batchId},
      );
      final data = res.data;
      final list = data is Map
          ? (data['instances'] as List? ?? const [])
          : const [];
      return list
          .whereType<Map>()
          .map(
            (e) => SegmentInstance.fromJson(
              e.map((k, v) => MapEntry(k.toString(), v)),
            ),
          )
          .toList();
    } catch (e) {
      throw Exception(_functionError(e));
    }
  }

  Future<List<FuseIdea>> fuse(List<Item> items) async {
    if (_backend) {
      try {
        final data = await apiClient.postJson('/v1/ai/fuse', {
          'items': items
              .map(
                (i) => {
                  'id': i.id,
                  'name': i.name,
                  'category': i.category,
                  'material': i.material,
                  'condition': i.condition,
                  'quantity': i.quantity,
                  'unit': i.unit,
                },
              )
              .toList(),
        });
        final list = data is Map
            ? (data['ideas'] as List? ?? const [])
            : const [];
        return list
            .whereType<Map>()
            .map(
              (e) =>
                  FuseIdea.fromJson(e.map((k, v) => MapEntry(k.toString(), v))),
            )
            .toList();
      } on ApiException catch (e) {
        throw Exception(e.message);
      } catch (_) {
        throw Exception('AI service is temporarily unavailable.');
      }
    }
    if (_demo) {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      return [
        FuseIdea(
          title: 'Self-Watering Bottle Planter',
          description:
              'Turn plastic bottles into a self-watering planter for herbs. The cardboard becomes a sturdy stand and labels.',
          steps: const [
            'Cut the bottle in half.',
            'Make drainage holes.',
            'Assemble the reservoir.',
            'Fill with soil and plant herbs.',
            'Mount on the cardboard stand.',
          ],
          difficulty: 'mudah',
          estimatedMinutes: 45,
          usedItems: items
              .map(
                (i) => {
                  'itemId': i.id,
                  'name': i.name,
                  'role': 'Main material',
                },
              )
              .toList(),
          missingItems: const [
            {
              'name': 'Herb Seeds',
              'category': 'organik',
              'suggestion': 'Buy at a plant shop or find in Community.',
            },
          ],
          imagePrompt:
              'Photorealistic product photo of a self-watering planter made from a cut plastic bottle with green herbs, clean bright background',
        ),
        FuseIdea(
          title: 'Cardboard Desk Organizer',
          description:
              'Build a multi-compartment desk organizer from cardboard, decorated with fabric scraps.',
          steps: const [
            'Measure and cut cardboard panels.',
            'Glue compartments together.',
            'Wrap with fabric scraps.',
            'Let dry and decorate.',
          ],
          difficulty: 'mudah',
          estimatedMinutes: 60,
          usedItems: items
              .map(
                (i) => {
                  'itemId': i.id,
                  'name': i.name,
                  'role': 'Structure and decoration',
                },
              )
              .toList(),
          missingItems: const [
            {
              'name': 'Craft Glue',
              'category': 'lainnya',
              'suggestion': 'Any craft glue or hot glue works.',
            },
          ],
          imagePrompt:
              'Photorealistic desk organizer made from cardboard wrapped in colorful fabric, stationery inside, clean background',
        ),
        FuseIdea(
          title: 'Bottle-Cap Mosaic Wall Art',
          description:
              'Create colorful mosaic wall art using collected bottle caps mounted on a board.',
          steps: const [
            'Collect and wash caps.',
            'Sketch the design.',
            'Glue caps row by row.',
            'Seal and hang.',
          ],
          difficulty: 'sedang',
          estimatedMinutes: 120,
          usedItems: items
              .map(
                (i) => {
                  'itemId': i.id,
                  'name': i.name,
                  'role': 'Mosaic material',
                },
              )
              .toList(),
          missingItems: const [],
          imagePrompt:
              'Photorealistic colorful mosaic wall art made of plastic bottle caps on a wooden board, clean background',
        ),
      ];
    }
    try {
      final res = await supabase.functions.invoke(
        'ai-fuse',
        body: {
          'items': items
              .map(
                (i) => {
                  'id': i.id,
                  'name': i.name,
                  'category': i.category,
                  'material': i.material,
                  'condition': i.condition,
                  'quantity': i.quantity,
                  'unit': i.unit,
                },
              )
              .toList(),
        },
      );
      final data = res.data;
      final list = data is Map
          ? (data['ideas'] as List? ?? const [])
          : const [];
      return list
          .whereType<Map>()
          .map(
            (e) =>
                FuseIdea.fromJson(e.map((k, v) => MapEntry(k.toString(), v))),
          )
          .toList();
    } catch (e) {
      throw Exception(_functionError(e));
    }
  }

  Future<String> fuseImage(
    String recipeId,
    String prompt, {
    String? referenceImageUrl,
  }) async {
    if (_backend) {
      try {
        final data = await apiClient.postJson('/v1/ai/fuse-image', {
          'recipeId': recipeId,
          'prompt': prompt,
          'referenceImageUrl': ?referenceImageUrl,
        }, timeout: const Duration(seconds: 150));
        if (data is Map && data['imageUrl'] != null) {
          return data['imageUrl'].toString();
        }
        throw Exception('AI service is temporarily unavailable.');
      } on ApiException catch (e) {
        throw Exception(e.message);
      } catch (_) {
        throw Exception('AI service is temporarily unavailable.');
      }
    }
    if (_demo) {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      return '';
    }
    try {
      final res = await supabase.functions.invoke(
        'ai-fuse-image',
        body: {
          'recipeId': recipeId,
          'prompt': prompt,
          'referenceImageUrl': ?referenceImageUrl,
        },
      );
      final data = res.data;
      if (data is Map && data['imageUrl'] != null) {
        return data['imageUrl'].toString();
      }
      throw Exception('AI service is temporarily unavailable.');
    } catch (e) {
      throw Exception(_functionError(e));
    }
  }
}

final aiRepositoryProvider = Provider<AiRepository>((_) => AiRepository());
