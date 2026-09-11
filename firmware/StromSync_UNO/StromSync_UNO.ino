/*
 * StromSync - Arduino Uno lightning driver (300 px, ambient + rumble)
 *
 * Link from ESP32 (2 data bits + strobe):
 *   ESP32 GPIO 4 -> D4    bit 0
 *   ESP32 GPIO 5 -> D5    bit 1
 *   ESP32 GPIO 6 -> D2    strobe
 *   10k pulldown from each of D4, D5, D2 to GND
 *
 *   D6 -> 470 ohm -> strip DIN
 *
 * Codes: 0 off, 1 storm mode, 2 soft strike, 3 hard strike
 *
 * Three layers, always in this order:
 *   1. base    slow Perlin drift, cold blue, the cloud is never dead
 *   2. bolt    composited on top, never replaces the base
 *   3. rumble  a swell through the base after a strike, decaying ~7 s
 *
 * POWER: 300 px needs the 5 V 20 A supply, injected at both ends of the
 * run and again near the middle. USB cannot drive this.
 */

#include <FastLED.h>

#define LED_PIN       6
#define NUM_LEDS      300
#define LED_TYPE      WS2812B
#define COLOR_ORDER   GRB
#define MAX_MA        15000
#define MASTER_BRI    90

#define AMBIENT_BASE  22       // idle cloud brightness, try 14 to 34
#define NOISE_GROUP   4        // pixels per noise sample, keeps the Uno fast

#define PIN_BIT0      4
#define PIN_BIT1      5
#define PIN_STROBE    2

#define CMD_OFF       0
#define CMD_STORM     1
#define CMD_SOFT      2
#define CMD_HARD      3

CRGB leds[NUM_LEDS];

bool     stormMode   = false;
bool     inFlash     = false;
bool     abortFlash  = false;
bool     lastStrobe  = LOW;
uint8_t  pendingCode = 255;
uint8_t  rumble      = 0;      // thunder energy, decays to 0
unsigned long nextAmbientAt = 0;
unsigned long nextBaseAt    = 0;
unsigned long nextRumbleAt  = 0;

// Fork geometry is fixed for the duration of one stroke, otherwise the
// branches jitter about during the decay and look like noise.
int16_t forkOff[3];
uint8_t forkAmt[3];
uint8_t forkCount = 0;

// ---------------------------------------------------------------- link

void pollLink() {
  bool s = digitalRead(PIN_STROBE);
  if (s == HIGH && lastStrobe == LOW) {
    uint8_t code = digitalRead(PIN_BIT0) | (digitalRead(PIN_BIT1) << 1);
    if (inFlash) {
      if (code == CMD_OFF) abortFlash = true;
    } else {
      pendingCode = code;
    }
  }
  lastStrobe = s;
}

bool hold(uint16_t ms) {
  pollLink();
  if (abortFlash) return false;

  unsigned long t = millis();
  while (millis() - t < ms) {
    pollLink();
    if (abortFlash) return false;
    delay(1);
  }
  return true;
}

// ------------------------------------------------------------- layer 1

// How bright the cloud sits right now. Rises while thunder is rolling.
uint8_t baseAmp() {
  if (!stormMode) return 0;
  return qadd8(AMBIENT_BASE, scale8(rumble, 42));
}

inline CRGB cloudColor(uint8_t v) {
  // Cold blue-white. Warm tones read as firelight, not storm.
  return CRGB(scale8(v, 55), scale8(v, 105), v);
}

/*
 * The living cloud. Perlin noise drifting slowly along the strip, plus a
 * single global swell driven by rumble so the whole cloud breathes while
 * the thunder rolls. Sampled every NOISE_GROUP pixels because the
 * diffuser blurs that resolution away anyway and the Uno needs the time.
 */
void renderBaseNoise() {
  uint8_t amp = baseAmp();
  if (amp == 0) {
    fill_solid(leds, NUM_LEDS, CRGB::Black);
    FastLED.show();
    return;
  }

  uint16_t t    = (uint16_t)(millis() >> 4);          // drift speed
  uint8_t  gust = scale8(inoise8(t << 2, 30000), rumble);

  for (int16_t i = 0; i < NUM_LEDS; i += NOISE_GROUP) {
    uint8_t n = inoise8((uint16_t)i * 9, t);
    uint8_t v = qadd8(scale8(n, amp), scale8(gust, 20));
    CRGB    c = cloudColor(v);
    for (int16_t k = i; k < i + NOISE_GROUP && k < NUM_LEDS; k++) leds[k] = c;
  }
  FastLED.show();
}

// Flat version of the base, used underneath a bolt. Far cheaper, and a
// bright stroke washes out the noise detail regardless.
void fillBaseFlat() {
  fill_solid(leds, NUM_LEDS, cloudColor(baseAmp()));
}

// ------------------------------------------------------------- layer 2

inline void addPix(int16_t i, uint8_t v) {
  if (v == 0) return;
  leds[i].r = qadd8(leds[i].r, scale8(v, 232));
  leds[i].g = qadd8(leds[i].g, scale8(v, 242));
  leds[i].b = qadd8(leds[i].b, v);
}

/*
 * Adds one channel, decaying outward from center. Carries the previous
 * value forward instead of recomputing a power per pixel, so this stays
 * O(N) at 300 px.
 *
 * fade:  205 narrow bolt   232 a metre of glow   250 broad wash
 */
void addBolt(int16_t center, uint8_t peak, uint8_t fade) {
  center = constrain(center, 0, NUM_LEDS - 1);

  uint8_t v = peak;
  for (int16_t i = center; i < NUM_LEDS; i++) {
    if (v == 0) break;
    addPix(i, v);
    v = scale8(v, fade);
  }

  v = scale8(peak, fade);
  for (int16_t i = center - 1; i >= 0; i--) {
    if (v == 0) break;
    addPix(i, v);
    v = scale8(v, fade);
  }
}

void drawFrame(int16_t center, uint8_t peak, uint8_t fade) {
  fillBaseFlat();
  addBolt(center, peak, fade);
  for (uint8_t f = 0; f < forkCount; f++)
    addBolt(center + forkOff[f], scale8(peak, forkAmt[f]), fade);
  FastLED.show();
}

/*
 * One return stroke. Full brightness on the very first frame, no ramp:
 * that abruptness is the whole point. Then an exponential decay tail,
 * which settles back onto the base rather than to black.
 */
void returnStroke(int16_t center, uint8_t peak, uint8_t fade) {
  drawFrame(center, peak, fade);
  if (!hold(random8(3, 10))) return;

  uint8_t p = peak;
  while (p > 5) {
    p = scale8(p, 148);
    drawFrame(center, p, fade);
    if (!hold(0)) return;
  }
}

/*
 * Full strike. energy is proximity: 255 overhead, ~100 a few km off.
 * Close strikes get no leader at all, because a nearby bolt gives you no
 * warning whatsoever. Distant ones get a brief faint flicker first.
 */
void lightning(uint8_t energy) {
  inFlash    = true;
  abortFlash = false;

  int16_t center  = random16(NUM_LEDS);
  bool    close   = energy > 180;
  uint8_t fade    = close ? 236 : 216;
  uint8_t strokes = close ? random8(3, 6) : random8(2, 4);
  uint8_t peak    = energy;

  forkCount = close ? random8(1, 4) : random8(0, 2);
  for (uint8_t f = 0; f < forkCount; f++) {
    forkOff[f] = (int16_t)random16(NUM_LEDS / 5) - (NUM_LEDS / 10);
    forkAmt[f] = random8(90, 165);
  }

  if (!close) {                                  // faint distant leader
    for (uint8_t s = 0; s < random8(2, 4); s++) {
      drawFrame(center + (int16_t)random8(30) - 15, random8(10, 26), 206);
      if (!hold(random8(4, 11))) break;
    }
  }

  for (uint8_t s = 0; s < strokes && !abortFlash; s++) {
    int16_t c = center + (int16_t)random16(NUM_LEDS / 12) - (NUM_LEDS / 24);
    returnStroke(c, peak, fade);

    peak = scale8(peak, random8(150, 215));      // later strokes are weaker
    if (peak < 25) break;

    hold(random8(25, 95));                       // the dark gap is the flicker
  }

  // Continuing current: the channel glows down slowly onto the base.
  if (!abortFlash) {
    uint8_t p = scale8(energy, 45);
    while (p > 3 && !abortFlash) {
      drawFrame(center, p, 246);
      p = scale8(p, 205);
      if (!hold(8)) break;
    }
  }

  // Layer 3 begins: hand the energy to the thunder.
  rumble       = qadd8(rumble, scale8(energy, 235));
  nextRumbleAt = millis() + 50;

  fillBaseFlat();
  FastLED.show();

  inFlash    = false;
  abortFlash = false;
}

/*
 * Sheet lightning: a strike hidden behind cloud, no channel visible.
 * Broad, slow, soft. The contrast is what makes direct strikes land.
 */
void sheetFlash() {
  inFlash = true;
  forkCount = 0;
  int16_t center = random16(NUM_LEDS);
  uint8_t peak   = random8(25, 70);

  for (int16_t v = 0; v <= peak; v += 3) {
    drawFrame(center, v, 250);
    if (!hold(2)) break;
  }
  hold(random8(20, 70));
  for (int16_t v = peak; v >= 0; v -= 2) {
    drawFrame(center, v, 250);
    if (!hold(4)) break;
  }

  rumble  = qadd8(rumble, random8(60, 120));
  inFlash = false;
}

// -------------------------------------------------------------- control

void handleCommand(uint8_t code) {
  switch (code) {
    case CMD_OFF:
      stormMode = false;
      rumble    = 0;
      fill_solid(leds, NUM_LEDS, CRGB::Black);
      FastLED.show();
      break;
    case CMD_STORM:
      stormMode     = true;
      nextAmbientAt = millis() + random(1500, 5000);
      break;
    case CMD_SOFT: lightning(random8(90, 150));  break;
    case CMD_HARD: lightning(random8(215, 255)); break;
  }
}

void setup() {
  Serial.begin(9600);
  delay(2000);                    // let the rail settle before drawing

  pinMode(PIN_BIT0, INPUT);
  pinMode(PIN_BIT1, INPUT);
  pinMode(PIN_STROBE, INPUT);

  FastLED.addLeds<LED_TYPE, LED_PIN, COLOR_ORDER>(leds, NUM_LEDS)
         .setCorrection(TypicalLEDStrip);
  FastLED.setMaxPowerInVoltsAndMilliamps(5, MAX_MA);
  FastLED.setBrightness(MASTER_BRI);

  random16_set_seed(analogRead(A0) ^ micros());
  fill_solid(leds, NUM_LEDS, CRGB::Black);
  FastLED.show();
  Serial.println("uno ready, 300 px");
}

void loop() {
  pollLink();

  if (pendingCode != 255) {
    uint8_t c = pendingCode;
    pendingCode = 255;
    handleCommand(c);
  }

  unsigned long now = millis();

  // Layer 3: thunder decays over roughly seven seconds.
  if (rumble && now >= nextRumbleAt) {
    rumble       = qsub8(rumble, 2);
    nextRumbleAt = now + 50;
  }

  // Layer 1: the cloud keeps breathing whenever the storm is running.
  if (stormMode && now >= nextBaseAt) {
    renderBaseNoise();
    nextBaseAt = now + 40;
  }

  if (stormMode && now >= nextAmbientAt) {
    if (random8() < 60) lightning(random8(80, 140));
    else                sheetFlash();
    nextAmbientAt = now + random(2500, 11000);
  }
}
