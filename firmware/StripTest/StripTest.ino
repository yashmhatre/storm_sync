/*
 * StripTest — minimal WS2812B proof
 * ============================================================================
 *
 * Temporary diagnostic, not part of the build. No serial, no protocol, no
 * storm logic: just solid colours on a timer. If the strip does not cycle
 * red -> green -> blue -> black with this loaded, the fault is in the strip,
 * its power, or its data line — and nothing in StromSync_UNO.ino can be
 * blamed for it.
 *
 * Brightness is deliberately low. 300 pixels at full white is ~18 A; at 60/255
 * on a single colour it is closer to 1 A, which any sane feed handles.
 */

#include <FastLED.h>

#define LED_PIN      6
#define NUM_LEDS     300
#define LED_TYPE     WS2812B
#define COLOR_ORDER  GRB

static CRGB leds[NUM_LEDS];

void setup() {
  FastLED.addLeds<LED_TYPE, LED_PIN, COLOR_ORDER>(leds, NUM_LEDS);
  FastLED.setBrightness(60);
  FastLED.clear(true);

  // Onboard LED marks each cycle, so a dark strip can still be told apart
  // from a board that is not running at all.
  pinMode(LED_BUILTIN, OUTPUT);
}

static void show(CRGB c, uint16_t ms) {
  fill_solid(leds, NUM_LEDS, c);
  FastLED.show();
  delay(ms);
}

void loop() {
  digitalWrite(LED_BUILTIN, HIGH);
  show(CRGB::Red, 2500);
  show(CRGB::Green, 2500);
  show(CRGB::Blue, 2500);
  digitalWrite(LED_BUILTIN, LOW);
  show(CRGB::Black, 2000);
}
