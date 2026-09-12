enum Sp621eConnectionState {
  disconnected,
  scanning,
  connecting,
  connected,
}

class Sp621eControllerState {
  final Sp621eConnectionState connectionState;
  final bool isOn;

  final int brightness;

  final int r;
  final int g;
  final int b;

  final int effect;
  final int effectSpeed;
  final int effectLength;

  final bool isStormMode;

  const Sp621eControllerState({
    this.connectionState = Sp621eConnectionState.disconnected,
    this.isOn = false,
    this.brightness = 255,
    this.r = 255,
    this.g = 255,
    this.b = 255,
    this.effect = 0xBE,
    this.effectSpeed = 5,
    this.effectLength = 48,
    this.isStormMode = false,
  });

  Sp621eControllerState copyWith({
    Sp621eConnectionState? connectionState,
    bool? isOn,
    int? brightness,
    int? r,
    int? g,
    int? b,
    int? effect,
    int? effectSpeed,
    int? effectLength,
    bool? isStormMode,
  }) {
    return Sp621eControllerState(
      connectionState:
          connectionState ?? this.connectionState,
      isOn: isOn ?? this.isOn,
      brightness: brightness ?? this.brightness,
      r: r ?? this.r,
      g: g ?? this.g,
      b: b ?? this.b,
      effect: effect ?? this.effect,
      effectSpeed: effectSpeed ?? this.effectSpeed,
      effectLength: effectLength ?? this.effectLength,
      isStormMode: isStormMode ?? this.isStormMode,
    );
  }
}