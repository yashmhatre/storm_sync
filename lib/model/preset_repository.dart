import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ble/storm_service.dart';
import 'app_settings.dart';
import 'preset.dart';

/// Manages built-in and user-saved presets, persistent local storage, and BLE synchronization.
class PresetRepository extends ChangeNotifier {
  PresetRepository(this._prefs) {
    _loadCustomPresets();
  }

  static const String _storageKey = 'strom_sync_custom_presets';
  static const String _activePresetKey = 'strom_sync_active_preset_id';

  final SharedPreferences _prefs;
  final List<Preset> _customPresets = [];
  String? _activePresetId;

  static Future<PresetRepository> load() async {
    final prefs = await SharedPreferences.getInstance();
    return PresetRepository(prefs);
  }

  /// All available presets: built-in presets followed by user custom presets.
  List<Preset> get presets => [
        ...Preset.builtInPresets,
        ..._customPresets,
      ];

  String? get activePresetId => _activePresetId;

  Preset? get activePreset {
    if (_activePresetId == null) return null;
    return presets.cast<Preset?>().firstWhere(
          (p) => p?.id == _activePresetId,
          orElse: () => null,
        );
  }

  void _loadCustomPresets() {
    _activePresetId = _prefs.getString(_activePresetKey);
    final raw = _prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        _customPresets.clear();
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            _customPresets.add(Preset.fromJson(item));
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to load custom presets: $e');
    }
  }

  Future<void> _saveCustomPresets() async {
    final encoded = jsonEncode(_customPresets.map((p) => p.toJson()).toList());
    await _prefs.setString(_storageKey, encoded);
  }

  /// Saves the current hardware and app settings as a new custom preset.
  Future<Preset> saveCurrentState({
    required String name,
    required String description,
    required StormService stormService,
    required AppSettings appSettings,
  }) async {
    final id = 'preset_${DateTime.now().millisecondsSinceEpoch}';
    final preset = Preset(
      id: id,
      name: name.trim(),
      description: description.trim(),
      parameters: Map<String, int>.from(stormService.parameters),
      boltColor: RgbColor.fromList(stormService.boltColor),
      cloudTint: RgbColor.fromList(stormService.tintColor),
      speakerLatencyMs: appSettings.speakerLatencyMs,
      isBuiltIn: false,
    );

    _customPresets.add(preset);
    _activePresetId = id;
    await _prefs.setString(_activePresetKey, id);
    await _saveCustomPresets();
    notifyListeners();
    return preset;
  }

  /// Deletes a custom preset. Built-in presets cannot be deleted.
  Future<void> deletePreset(String id) async {
    _customPresets.removeWhere((p) => p.id == id && !p.isBuiltIn);
    if (_activePresetId == id) {
      _activePresetId = null;
      await _prefs.remove(_activePresetKey);
    }
    await _saveCustomPresets();
    notifyListeners();
  }

  /// Applies the preset: syncs parameters to the ESP32 light, updates colours and audio latency.
  Future<void> applyPreset(
    Preset preset,
    StormService stormService,
    AppSettings appSettings,
  ) async {
    _activePresetId = preset.id;
    await _prefs.setString(_activePresetKey, preset.id);

    // Apply parameters to firmware
    for (final entry in preset.parameters.entries) {
      stormService.setParameter(entry.key, entry.value, finalValue: true);
    }

    // Apply colours
    stormService.setColor(
      preset.boltColor.r,
      preset.boltColor.g,
      preset.boltColor.b,
      finalValue: true,
    );
    stormService.setTint(
      preset.cloudTint.r,
      preset.cloudTint.g,
      preset.cloudTint.b,
      finalValue: true,
    );

    // Apply speaker latency
    appSettings.speakerLatencyMs = preset.speakerLatencyMs;

    notifyListeners();
  }
}

