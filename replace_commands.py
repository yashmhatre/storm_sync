import re

with open('lib/services/sp621e_ble_service.dart', 'r') as f:
    code = f.read()

# Replace powerOn
power_on_re = r"""Future<void> powerOn\(\) async \{.*?_updateState"""
power_on_new = """Future<void> powerOn() async {
  await _writeCommand([0x7E, 0x04, 0x04, 0x01, 0x00, 0x00, 0xFF, 0x00, 0xEF]);
  await _writeCommand([0x7E, 0x00, 0x04, 0x01, 0x00, 0x00, 0x00, 0x00, 0xEF]);
  await _writeCommand([0xCC, 0x23, 0x33]);
  _updateState"""
code = re.sub(power_on_re, power_on_new, code, flags=re.DOTALL)

# Replace powerOff
power_off_re = r"""Future<void> powerOff\(\) async \{.*?_updateState"""
power_off_new = """Future<void> powerOff() async {
  await _writeCommand([0x7E, 0x04, 0x04, 0x00, 0x00, 0x00, 0xFF, 0x00, 0xEF]);
  await _writeCommand([0x7E, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0xEF]);
  await _writeCommand([0xCC, 0x24, 0x33]);
  _updateState"""
code = re.sub(power_off_re, power_off_new, code, flags=re.DOTALL)

# Replace setBrightness
set_brightness_re = r"""Future<void> setBrightness\(int brightness\) async \{.*?_updateState"""
set_brightness_new = """Future<void> setBrightness(int brightness) async {
  final value = brightness.clamp(0, 255).toInt();
  await _writeCommand([0x7E, 0x04, 0x01, value, 0x00, 0x00, 0xFF, 0x00, 0xEF]);
  await _writeCommand([0x7E, 0x00, 0x01, value, 0x00, 0x00, 0x00, 0x00, 0xEF]);
  _updateState"""
code = re.sub(set_brightness_re, set_brightness_new, code, flags=re.DOTALL)

# Replace setEffect
set_effect_re = r"""Future<void> setEffect\(int effect\) async \{.*?_updateState"""
set_effect_new = """Future<void> setEffect(int effect) async {
  final value = effect.clamp(0, 255).toInt();
  await _writeCommand([0x7E, 0x04, 0x03, value, 0x00, 0x00, 0xFF, 0x00, 0xEF]);
  await _writeCommand([0x7E, 0x00, 0x03, value, 0x00, 0x00, 0x00, 0x00, 0xEF]);
  _updateState"""
code = re.sub(set_effect_re, set_effect_new, code, flags=re.DOTALL)

# Replace setEffectSpeed
set_speed_re = r"""Future<void> setEffectSpeed\(int speed\) async \{.*?_updateState"""
set_speed_new = """Future<void> setEffectSpeed(int speed) async {
  final value = speed.clamp(1, 10).toInt();
  await _writeCommand([0x7E, 0x04, 0x02, value, 0x00, 0x00, 0xFF, 0x00, 0xEF]);
  await _writeCommand([0x7E, 0x00, 0x02, value, 0x00, 0x00, 0x00, 0x00, 0xEF]);
  _updateState"""
code = re.sub(set_speed_re, set_speed_new, code, flags=re.DOTALL)

# Replace setEffectLength
set_len_re = r"""Future<void> setEffectLength\(int length\) async \{.*?_updateState"""
set_len_new = """Future<void> setEffectLength(int length) async {
  final value = length.clamp(1, 2000).toInt();
  final highByte = (value >> 8) & 0xFF;
  final lowByte = value & 0xFF;
  await _writeCommand([0x7E, 0x04, 0x03, highByte, lowByte, 0x00, 0xFF, 0x00, 0xEF]);
  await _writeCommand([0x7E, 0x00, 0x03, highByte, lowByte, 0x00, 0x00, 0x00, 0xEF]);
  _updateState"""
code = re.sub(set_len_re, set_len_new, code, flags=re.DOTALL)

# Replace setColor
set_color_re = r"""Future<void> setColor\(
  int r,
  int g,
  int b, \{
  int\? brightness,
\}\) async \{.*?_updateState"""
set_color_new = """Future<void> setColor(
  int r,
  int g,
  int b, {
  int? brightness,
}) async {
  final red = r.clamp(0, 255);
  final green = g.clamp(0, 255);
  final blue = b.clamp(0, 255);

  final level =
      (brightness ?? _state.brightness).clamp(0, 255);

  await _writeCommand([0x7E, 0x07, 0x05, 0x03, red, green, blue, 0x10, 0xEF]);
  await _writeCommand([0x7E, 0x00, 0x05, 0x03, red, green, blue, 0x00, 0xEF]);
  await _writeCommand([0x56, red, green, blue, 0x00, 0xF0, 0xAA]);

  if (brightness != null) {
    await _writeCommand([0x7E, 0x04, 0x01, level, 0x00, 0x00, 0xFF, 0x00, 0xEF]);
    await _writeCommand([0x7E, 0x00, 0x01, level, 0x00, 0x00, 0x00, 0x00, 0xEF]);
  }

  _updateState"""
code = re.sub(set_color_re, set_color_new, code, flags=re.DOTALL)

# Replace _runBatchStrike writes
batch_strike_re = r"""Future<void> _runBatchStrike\(\{.*?_updateState"""
batch_strike_new = """Future<void> _runBatchStrike({
  required double intensity,
  int segmentLength = _rowBatchLength,
  int? visualDurationMs,
  int? speed,
}) async {
  final actualIntensity =
      intensity.clamp(0.0, 1.0);

  final brightness =
      (255 * actualIntensity)
          .round()
          .clamp(1, 255)
          .toInt();

  final actualLength =
      segmentLength.clamp(8, 80).toInt();

  final actualSpeed =
      (speed ?? (8 + _random.nextInt(3)))
          .clamp(1, 10)
          .toInt();

  // Switch to white solid color just in case
  await _writeCommand([0x7E, 0x07, 0x05, 0x03, 255, 255, 255, 0x10, 0xEF]);
  // Set effect
  await _writeCommand([0x7E, 0x04, 0x03, _whiteSegmentSpinEffect, 0x00, 0x00, 0xFF, 0x00, 0xEF]);
  // Set speed
  await _writeCommand([0x7E, 0x04, 0x02, actualSpeed, 0x00, 0x00, 0xFF, 0x00, 0xEF]);
  // Set brightness
  await _writeCommand([0x7E, 0x04, 0x01, brightness, 0x00, 0x00, 0xFF, 0x00, 0xEF]);

  _updateState"""
code = re.sub(batch_strike_re, batch_strike_new, code, flags=re.DOTALL)

# Replace _impactFlash writes
impact_flash_re = r"""Future<void> _impactFlash\(\{.*?debugPrint"""
impact_flash_new = """Future<void> _impactFlash({
  required double intensity,
  int? durationMs,
}) async {
  final actualIntensity =
      intensity.clamp(0.0, 1.0);

  final brightness =
      (255 * actualIntensity)
          .round()
          .clamp(1, 255)
          .toInt();

  final duration =
      (durationMs ??
      (38 + _random.nextInt(25))) + 20;

  // Solid effect
  await _writeCommand([0x7E, 0x04, 0x03, _solidEffect, 0x00, 0x00, 0xFF, 0x00, 0xEF]);
  // Almost white color
  await _writeCommand([0x7E, 0x07, 0x05, 0x03, 245, 250, 255, 0x10, 0xEF]);
  // Brightness
  await _writeCommand([0x7E, 0x04, 0x01, brightness, 0x00, 0x00, 0xFF, 0x00, 0xEF]);

  debugPrint"""
code = re.sub(impact_flash_re, impact_flash_new, code, flags=re.DOTALL)


with open('lib/services/sp621e_ble_service.dart', 'w') as f:
    f.write(code)
