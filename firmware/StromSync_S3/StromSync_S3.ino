/*
 * StromSync — ESP32-S3 pixel receiver
 * ============================================================================
 *
 *   phone --WiFi/UDP (DDP)--> ESP32-S3 (this sketch) --> WS2812B strip
 *
 * The app renders the lightning and streams the finished pixels; this board
 * does nothing but put them on the strip. That split is deliberate. It is what
 * makes per-pixel bolts, real blue-white colour and true decay curves possible
 * at all, none of which a BLE LED controller can do, and it keeps the strike
 * engine on the phone where the audio analysis lives and where it can be tuned
 * without reflashing.
 *
 * Replaces the older two-board build. The S3 drives the strip itself, so the
 * pulse-counted link to the UNO — and the quarter of the bytes it used to lose
 * — is gone.
 *
 * ---------------------------------------------------------------------------
 * Wiring
 * ---------------------------------------------------------------------------
 *
 *   S3 GPIO 18 ──[330R]── strip DIN
 *   S3 GND     ─────────── strip GND      (must be common with the PSU)
 *   5V PSU     ─────────── strip 5V
 *
 * The strip is the one the SP621E was driving; nothing needs replacing.
 *
 * A WS2812B wants its data line above 0.7 x VDD, which is 3.5 V on a 5 V
 * supply, and the S3 only swings to 3.3 V. It usually works anyway, but if the
 * first pixels flicker or show wrong colours, put a 74AHCT125 between the two
 * as a level shifter. That is the fix — not lowering the brightness.
 *
 * Inject 5 V at both ends for a run this long, or the far end goes brown.
 *
 * ---------------------------------------------------------------------------
 * Protocol
 * ---------------------------------------------------------------------------
 *
 * DDP on UDP port 4048, the same format WLED accepts, so this sketch and WLED
 * are interchangeable as far as the app is concerned.
 *
 *   byte 0      flags: 0x40 version 1, bit 0 set means display this now
 *   byte 1      sequence 1-15
 *   byte 2      data type, 0x01 for 8-bit RGB
 *   byte 3      destination, 1
 *   bytes 4-7   byte offset into the strip, big endian
 *   bytes 8-9   payload length in bytes, big endian
 *   bytes 10+   RGB triples
 *
 * A frame longer than one datagram arrives as several packets; only the last
 * carries the push bit, so a frame is never shown half drawn.
 */

#include <Arduino.h>
#include <WiFi.h>
#include <WiFiUdp.h>
#include <FastLED.h>

// ============================================================== settings ===

#define WIFI_SSID       "your-network"
#define WIFI_PASSWORD   "your-password"

// Fixed address is worth setting: the app has to be told where to send, and a
// DHCP lease that moves means editing it again.
#define USE_STATIC_IP   1
IPAddress staticIp(192, 168, 1, 50);
IPAddress gateway(192, 168, 1, 1);
IPAddress subnet(255, 255, 255, 0);

#define LED_PIN         18
#define NUM_LEDS        288
#define LED_TYPE        WS2812B
#define COLOR_ORDER     GRB

// Ceiling on current draw. 288 pixels at full white would pull about 17 A,
// which no small supply will give and no thin wire will carry.
#define MAX_MILLIAMPS   4000

#define DDP_PORT        4048
#define DDP_HEADER_LEN  10
#define DDP_FLAG_PUSH   0x01

// If the app stops sending, fall back to something rather than freezing on
// whatever half-lit frame arrived last.
#define STREAM_TIMEOUT_MS 3000

// =================================================================== state ==

CRGB leds[NUM_LEDS];
WiFiUDP udp;

uint8_t packet[DDP_HEADER_LEN + NUM_LEDS * 3 + 64];
unsigned long lastPacketMs = 0;
bool streaming = false;

// ============================================================== idle glow ===

// Shown when nothing is streaming: a slow storm-blue breath, so the build
// looks alive with the phone away rather than dead.
void idleGlow() {
  const uint8_t level = 8 + (exp_u8(sin8(millis() / 24)) >> 5);

  for (int i = 0; i < NUM_LEDS; i++) {
    leds[i] = CRGB(level / 4, level / 2, level);
  }
  FastLED.show();
}

// ================================================================== setup ===

void setup() {
  Serial.begin(115200);
  delay(200);

  FastLED.addLeds<LED_TYPE, LED_PIN, COLOR_ORDER>(leds, NUM_LEDS)
      .setCorrection(TypicalLEDStrip);
  FastLED.setMaxPowerInVoltsAndMilliamps(5, MAX_MILLIAMPS);
  FastLED.clear(true);

  Serial.printf("[S3] %d pixels on GPIO %d\n", NUM_LEDS, LED_PIN);

#if USE_STATIC_IP
  WiFi.config(staticIp, gateway, subnet);
#endif

  WiFi.mode(WIFI_STA);
  // Power saving raises latency on every packet, which is the one thing this
  // board must not add.
  WiFi.setSleep(false);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  Serial.print("[S3] joining WiFi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(300);
    Serial.print(".");
  }

  Serial.printf("\n[S3] ready on %s:%d\n",
                WiFi.localIP().toString().c_str(), DDP_PORT);
  Serial.println("[S3] point the app at that address");

  udp.begin(DDP_PORT);
}

// =================================================================== loop ===

void loop() {
  int size = udp.parsePacket();

  while (size > 0) {
    const int read = udp.read(packet, sizeof(packet));

    if (read >= DDP_HEADER_LEN) {
      const uint8_t flags = packet[0];

      const uint32_t offset = ((uint32_t)packet[4] << 24) |
                              ((uint32_t)packet[5] << 16) |
                              ((uint32_t)packet[6] << 8) |
                              (uint32_t)packet[7];

      uint16_t length = ((uint16_t)packet[8] << 8) | (uint16_t)packet[9];

      // Trust the datagram over the declared length: a truncated packet must
      // not be allowed to read past what actually arrived.
      if (length > read - DDP_HEADER_LEN) {
        length = read - DDP_HEADER_LEN;
      }

      uint8_t *rgb = (uint8_t *)leds;
      const uint32_t capacity = NUM_LEDS * 3;

      if (offset < capacity) {
        const uint32_t copy = min((uint32_t)length, capacity - offset);
        memcpy(rgb + offset, packet + DDP_HEADER_LEN, copy);
      }

      lastPacketMs = millis();
      streaming = true;

      // Only the packet that completes a frame puts it on the strip.
      if (flags & DDP_FLAG_PUSH) {
        FastLED.show();
      }
    }

    size = udp.parsePacket();
  }

  if (streaming && millis() - lastPacketMs > STREAM_TIMEOUT_MS) {
    streaming = false;
    Serial.println("[S3] stream stopped, back to idle");
  }

  if (!streaming) {
    idleGlow();
    delay(16);
  }
}
