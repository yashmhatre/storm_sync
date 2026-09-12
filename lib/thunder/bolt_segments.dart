import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'strip_calibration.dart';

/// One physical bolt shape on the strip.
///
/// The strip is a single continuous run, but it is bent into separate zigzag
/// bolts with plain connecting runs between them. Only the bolts are worth
/// lighting, so a strike targets one of these rather than an arbitrary point
/// along the strip.
///
/// [startPixel] and [endPixel] are LED indices measured along the strip in the
/// direction the controller's sweep travels.
@immutable
class BoltSegment {
  const BoltSegment({
    required this.id,
    required this.name,
    required this.startPixel,
    required this.endPixel,
  });

  final String id;
  final String name;
  final int startPixel;
  final int endPixel;

  int get length => (endPixel - startPixel).abs().clamp(1, 150);

  /// The sweep is cut when its leading edge reaches the far end of the bolt,
  /// which is the moment the whole shape is lit.
  int get leadingPixel => startPixel > endPixel ? startPixel : endPixel;

  /// Where this bolt sits as a fraction of the whole strip.
  double positionIn(StripCalibration calibration) {
    if (calibration.pixelCount <= 0) return 0;
    return (leadingPixel / calibration.pixelCount).clamp(0.0, 1.0);
  }

  BoltSegment copyWith({String? name, int? startPixel, int? endPixel}) {
    return BoltSegment(
      id: id,
      name: name ?? this.name,
      startPixel: startPixel ?? this.startPixel,
      endPixel: endPixel ?? this.endPixel,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'startPixel': startPixel,
        'endPixel': endPixel,
      };

  static BoltSegment fromJson(Map<String, dynamic> json) {
    return BoltSegment(
      id: json['id'] as String? ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      name: json['name'] as String? ?? 'Bolt',
      startPixel: (json['startPixel'] as num?)?.toInt() ?? 0,
      endPixel: (json['endPixel'] as num?)?.toInt() ?? 48,
    );
  }

  /// A starting guess for a strip bent into four evenly spaced bolts. These are
  /// meant to be replaced by real measurements from the bolt editor — no two
  /// hand-built strips have the same pixel ranges.
  static List<BoltSegment> defaults({int pixelCount = 288}) {
    const count = 4;
    final span = pixelCount ~/ count;
    // Each bolt occupies most of its span; the rest is the connecting run.
    final boltLength = (span * 0.6).round().clamp(8, 150);

    return [
      for (var i = 0; i < count; i++)
        BoltSegment(
          id: 'bolt-${i + 1}',
          name: 'Bolt ${i + 1}',
          startPixel: i * span,
          endPixel: i * span + boltLength,
        ),
    ];
  }
}

/// Holds the bolt shapes the strip is bent into.
class BoltSegmentStore extends ChangeNotifier {
  BoltSegmentStore(this._segments);

  static const String _key = 'bolt_segments_v1';

  List<BoltSegment> _segments;
  List<BoltSegment> get segments => List.unmodifiable(_segments);

  static Future<BoltSegmentStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);

    if (raw == null) return BoltSegmentStore(BoltSegment.defaults());

    try {
      final decoded = jsonDecode(raw) as List;
      final parsed = decoded
          .map((e) => BoltSegment.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
      if (parsed.isEmpty) return BoltSegmentStore(BoltSegment.defaults());
      return BoltSegmentStore(parsed);
    } catch (_) {
      return BoltSegmentStore(BoltSegment.defaults());
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(_segments.map((s) => s.toJson()).toList()),
    );
  }

  BoltSegment? byId(String? id) {
    if (id == null) return null;
    for (final segment in _segments) {
      if (segment.id == id) return segment;
    }
    return null;
  }

  Future<void> upsert(BoltSegment segment) async {
    final index = _segments.indexWhere((s) => s.id == segment.id);
    if (index >= 0) {
      _segments[index] = segment;
    } else {
      _segments.add(segment);
    }
    _segments.sort((a, b) => a.leadingPixel.compareTo(b.leadingPixel));
    notifyListeners();
    await _persist();
  }

  Future<void> add({int pixelCount = 288}) async {
    final next = _segments.length + 1;
    await upsert(
      BoltSegment(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: 'Bolt $next',
        startPixel: 0,
        endPixel: (pixelCount * 0.15).round().clamp(8, 150),
      ),
    );
  }

  Future<void> remove(String id) async {
    _segments.removeWhere((s) => s.id == id);
    notifyListeners();
    await _persist();
  }

  Future<void> restoreDefaults({int pixelCount = 288}) async {
    _segments = BoltSegment.defaults(pixelCount: pixelCount);
    notifyListeners();
    await _persist();
  }
}
