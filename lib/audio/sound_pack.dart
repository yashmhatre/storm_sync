import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'thunder_player.dart';

/// Configuration of audio samples for the 3 thunder distances.
class SoundPack {
  const SoundPack({
    required this.id,
    required this.name,
    required this.description,
    this.closeAudioPath,
    this.midAudioPath,
    this.farAudioPath,
    this.isBuiltIn = false,
  });

  final String id;
  final String name;
  final String description;

  /// Absolute file path for close thunder sample. If null, bundled asset is used.
  final String? closeAudioPath;

  /// Absolute file path for mid thunder sample. If null, bundled asset is used.
  final String? midAudioPath;

  /// Absolute file path for far thunder sample. If null, bundled asset is used.
  final String? farAudioPath;

  final bool isBuiltIn;

  /// The active audio source path (asset or local file) for [distance].
  String audioPathFor(ThunderDistance distance) {
    switch (distance) {
      case ThunderDistance.close:
        return closeAudioPath?.isNotEmpty == true
            ? closeAudioPath!
            : distance.asset;
      case ThunderDistance.mid:
        return midAudioPath?.isNotEmpty == true
            ? midAudioPath!
            : distance.asset;
      case ThunderDistance.far:
        return farAudioPath?.isNotEmpty == true
            ? farAudioPath!
            : distance.asset;
    }
  }

  /// Whether the path for [distance] is a bundled asset (as opposed to a custom file).
  bool isAssetFor(ThunderDistance distance) {
    switch (distance) {
      case ThunderDistance.close:
        return closeAudioPath == null || closeAudioPath!.isEmpty;
      case ThunderDistance.mid:
        return midAudioPath == null || midAudioPath!.isEmpty;
      case ThunderDistance.far:
        return farAudioPath == null || farAudioPath!.isEmpty;
    }
  }

  SoundPack copyWith({
    String? id,
    String? name,
    String? description,
    String? closeAudioPath,
    String? midAudioPath,
    String? farAudioPath,
    bool? isBuiltIn,
  }) {
    return SoundPack(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      closeAudioPath: closeAudioPath ?? this.closeAudioPath,
      midAudioPath: midAudioPath ?? this.midAudioPath,
      farAudioPath: farAudioPath ?? this.farAudioPath,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'closeAudioPath': closeAudioPath,
        'midAudioPath': midAudioPath,
        'farAudioPath': farAudioPath,
        'isBuiltIn': isBuiltIn,
      };

  factory SoundPack.fromJson(Map<String, dynamic> json) => SoundPack(
        id: json['id'] as String,
        name: json['name'] as String,
        description: (json['description'] as String?) ?? '',
        closeAudioPath: json['closeAudioPath'] as String?,
        midAudioPath: json['midAudioPath'] as String?,
        farAudioPath: json['farAudioPath'] as String?,
        isBuiltIn: (json['isBuiltIn'] as bool?) ?? false,
      );

  /// Default bundled sound pack pointing to assets/audio/*.mp3.
  static const SoundPack defaultPack = SoundPack(
    id: 'default_pack',
    name: 'Default Thunder (Bundled)',
    description: 'Standard close, mid, and far acoustic recordings.',
    isBuiltIn: true,
  );
}

/// Manages sound pack collection, file importing, and persistent storage.
class SoundPackManager extends ChangeNotifier {
  SoundPackManager(this._prefs) {
    _loadCustomPacks();
  }

  static const String _storageKey = 'strom_sync_custom_sound_packs';
  static const String _activePackKey = 'strom_sync_active_sound_pack_id';

  final SharedPreferences _prefs;
  final List<SoundPack> _customPacks = [];
  String _activePackId = SoundPack.defaultPack.id;

  static Future<SoundPackManager> load() async {
    final prefs = await SharedPreferences.getInstance();
    return SoundPackManager(prefs);
  }

  List<SoundPack> get packs => [
        SoundPack.defaultPack,
        ..._customPacks,
      ];

  String get activePackId => _activePackId;

  SoundPack get activePack {
    return packs.firstWhere(
      (p) => p.id == _activePackId,
      orElse: () => SoundPack.defaultPack,
    );
  }

  void _loadCustomPacks() {
    _activePackId =
        _prefs.getString(_activePackKey) ?? SoundPack.defaultPack.id;
    final raw = _prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        _customPacks.clear();
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            _customPacks.add(SoundPack.fromJson(item));
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to load custom sound packs: $e');
    }
  }

  Future<void> _saveCustomPacks() async {
    final encoded = jsonEncode(_customPacks.map((p) => p.toJson()).toList());
    await _prefs.setString(_storageKey, encoded);
  }

  Future<void> setActivePack(String id) async {
    _activePackId = id;
    await _prefs.setString(_activePackKey, id);
    notifyListeners();
  }

  Future<SoundPack> createPack({
    required String name,
    required String description,
    String? closePath,
    String? midPath,
    String? farPath,
  }) async {
    final id = 'pack_${DateTime.now().millisecondsSinceEpoch}';
    final pack = SoundPack(
      id: id,
      name: name.trim(),
      description: description.trim(),
      closeAudioPath: closePath,
      midAudioPath: midPath,
      farAudioPath: farPath,
      isBuiltIn: false,
    );

    _customPacks.add(pack);
    _activePackId = id;
    await _prefs.setString(_activePackKey, id);
    await _saveCustomPacks();
    notifyListeners();
    return pack;
  }

  Future<void> updatePack(SoundPack updated) async {
    final index = _customPacks.indexWhere((p) => p.id == updated.id);
    if (index != -1) {
      _customPacks[index] = updated;
      await _saveCustomPacks();
      notifyListeners();
    }
  }

  Future<void> deletePack(String id) async {
    _customPacks.removeWhere((p) => p.id == id && !p.isBuiltIn);
    if (_activePackId == id) {
      _activePackId = SoundPack.defaultPack.id;
      await _prefs.setString(_activePackKey, _activePackId);
    }
    await _saveCustomPacks();
    notifyListeners();
  }

  /// Opens the system file picker to select a custom audio file, copies it to app storage,
  /// and returns the persistent file path.
  Future<String?> pickAndImportAudioFile(ThunderDistance distance) async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'wav', 'ogg', 'm4a', 'aac', 'flac'],
      );

      if (files.isEmpty) return null;
      final sourcePath = files.first.path;
      if (sourcePath == null) return null;

      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) return null;

      // Copy to persistent documents directory
      final docsDir = await getApplicationDocumentsDirectory();
      final soundDir = Directory('${docsDir.path}/sound_packs');
      if (!await soundDir.exists()) {
        await soundDir.create(recursive: true);
      }

      final ext = sourcePath.contains('.') ? sourcePath.split('.').last : 'mp3';
      final fileName = 'thunder_${distance.name}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final targetFile = File('${soundDir.path}/$fileName');

      await sourceFile.copy(targetFile.path);
      return targetFile.path;
    } catch (e) {
      debugPrint('Failed to pick and import audio file: $e');
      return null;
    }
  }
}
