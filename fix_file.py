import re

with open('lib/services/sp621e_ble_service.dart', 'r') as f:
    code = f.read()

# 1. Remove thunderPlayer.playAfter from the top of triggerThunder
code = re.sub(
    r'(\s*thunderPlayer\.playAfter\(\s*_audioDistance\(selected\),\s*thunderDelay,\s*\);)',
    '',
    code,
    count=1
)

# 2. Add playAfter to distant block
distant_target = "    if (selected ==\n        LightningProfile.distant) {\n      await _runBatchStrike("
distant_replace = """    if (selected ==
        LightningProfile.distant) {
      thunderPlayer.playAfter(
        _audioDistance(selected),
        thunderDelay,
      );

      await _runBatchStrike("""
code = code.replace(distant_target, distant_replace)

# 3. Add playAfter to impactFlash block
impact_target = "    await _impactFlash("
impact_replace = """    thunderPlayer.playAfter(
      _audioDistance(selected),
      thunderDelay,
    );

    await _impactFlash("""
code = code.replace(impact_target, impact_replace)

# 4. Modify _runBatchStrike to set color to white before changing effect
batch_strike_target = """  // White Segment Spin.
  //
  // IMPORTANT:
  // This is the command that prevents every LED from simply
  // becoming white simultaneously.
  await _writeCommand([
    0xA0,
    0x63,
    0x01,
    _whiteSegmentSpinEffect,
  ]);"""

batch_strike_replace = """  // Set color to white first, so the segment spin effect isn't black!
  // This temporarily switches to solid mode, but the next command
  // instantly switches it to the spin effect.
  await _writeCommand([
    0xA0,
    0x69,
    0x04,
    255,
    255,
    255,
    brightness,
  ]);

  // White Segment Spin.
  await _writeCommand([
    0xA0,
    0x63,
    0x01,
    _whiteSegmentSpinEffect,
  ]);"""
code = code.replace(batch_strike_target, batch_strike_replace)

# 5. Increase _impactFlash duration
impact_flash_target = """  final duration =
      durationMs ??
      (38 + _random.nextInt(25));"""
impact_flash_replace = """  final duration =
      (durationMs ??
      (38 + _random.nextInt(25))) + 20;"""
code = code.replace(impact_flash_target, impact_flash_replace)

with open('lib/services/sp621e_ble_service.dart', 'w') as f:
    f.write(code)
