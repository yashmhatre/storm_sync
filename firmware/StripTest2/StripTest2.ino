/*
 * StripTest2 — StripTest plus the two things the storm sketch does differently
 * ============================================================================
 *
 * Temporary diagnostic. StripTest works on all 300 pixels; StromSync_UNO does
 * not, despite computing correct pixel values and calling show() 30 times a
 * second. The two structural differences are:
 *
 *   1. Serial is open and printing (the storm sketch echoes and heartbeats)
 *   2. show() is called every 33 ms rather than every 2.5 s
 *
 * This sketch adds both to StripTest while keeping fill_solid, so the colour
 * maths cannot be blamed. If the strip goes dark here, one of those two is the
 * culprit. If it still cycles, the fault is in renderFrame() itself.
 */

#include <FastLED.h>

#define LED_PIN      6
#define NUM_LEDS     300
#define LED_TYPE     WS2812B
#define COLOR_ORDER  GRB
#define FRAME_MS     33

static CRGB leds[NUM_LEDS];
static uint32_t frameCount = 0;

void setup() {
  Serial.begin(57600);
  FastLED.addLeds<LED_TYPE, LED_PIN, COLOR_ORDER>(leds, NUM_LEDS);
  FastLED.setBrightness(60);
  FastLED.clear(true);
  Serial.println(F("StripTest2 ready"));
}

void loop() {
  uint32_t now = millis();

  // Colour changes every 2.5 s, exactly as StripTest does.
  static uint8_t phase = 0;
  static uint32_t nextPhaseAt = 0;
  if (now >= nextPhaseAt) {
    nextPhaseAt = now + 2500;
    phase = (uint8_t)((phase + 1) % 4);
  }

  CRGB c;
  switch (phase) {
    case 0:  c = CRGB::Red;   break;
    case 1:  c = CRGB::Green; break;
    case 2:  c = CRGB::Blue;  break;
    default: c = CRGB::Black; break;
  }

  // Difference 2: re-push the same colour at 30 fps instead of once per phase.
  static uint32_t nextFrameAt = 0;
  if (now >= nextFrameAt) {
    nextFrameAt = now + FRAME_MS;
    fill_solid(leds, NUM_LEDS, c);
    FastLED.show();
    frameCount++;
  }

  // Difference 1: chatty serial, same shape as the storm sketch's heartbeat.
  static uint32_t nextBeat = 0;
  if (now >= nextBeat) {
    nextBeat = now + 1000;
    Serial.print(F("HB phase="));
    Serial.print(phase);
    Serial.print(F(" frames="));
    Serial.println(frameCount);
  }
}
