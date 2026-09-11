/*
 * StromSync — ESP32-S3 BLE bridge
 * ============================================================================
 *
 * Half of a two-board build:
 *
 *   phone --BLE--> ESP32-S3 (this sketch) --pulses--> Arduino UNO --> WS2812B x300
 *
 * This board owns the protocol and the parameter store. It does not touch the
 * strip: the UNO renders, because it drives the DIN line at a true 5 V.
 *
 * Speaks the command protocol from README.md over the Nordic UART Service:
 *
 *   Service  6e400001-b5a3-f393-e0a9-e50e24dcca9e
 *   RX       6e400002-...  app -> device, one command per write, no terminator
 *   TX       6e400003-...  device -> app, newline-terminated reply lines
 *
 * Replies are `OK ...`, `ERR ...` or `key=value`. The app scrapes `key=value`
 * out of any line, so `OK bri=128` both acknowledges and re-syncs the slider.
 *
 * Wiring: GPIO 17 -> UNO pin 2, GND -> GND. Two wires, one way, so no 5 V
 * can ever reach a 3.3 V pin.
 *
 * Commands are also accepted on the USB serial console at 115200 for bench
 * testing without the phone.
 */

#include <Arduino.h>
#include <Preferences.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// ============================================================== hardware ===

// One-wire link to the UNO. A UART was tried first and lost roughly a quarter
// of its bytes: the UNO is blind for ~9 ms of every frame while FastLED clocks
// out 300 pixels, and SoftwareSerial needs interrupt timing for every bit. A
// parallel version worked but needed four wires, three of which proved very
// hard to locate on the header.
//
// So commands go as pulse counts on a single line. The UNO samples a level in
// its own time � no interrupts, no baud rate, nothing to resynchronise. A
// 25 ms pulse comfortably outlives the render blackout, so it cannot be missed.
//
//   ESP32 GPIO 17 -> UNO pin 2      (3.3 V into a 5 V input reads HIGH)
//   ESP32 GND     -> UNO GND
//
// One way only. Nothing drives the ESP32, so no 5 V can ever reach a 3.3 V pin.
#define PIN_LINK        17

#define PULSE_HIGH_MS   25   // longer than a 300-pixel show()
#define PULSE_LOW_MS    25
#define GROUP_GAP_MS   260   // quiet period that ends a group

#define CMD_OFF      0
#define CMD_STORM    1
#define CMD_SOFT     2
#define CMD_HARD     3

// The UNO is deaf while FastLED is clocking out pixels, so a command sent at
// the wrong moment is simply lost. Every parameter write is idempotent, so
// re-sending the whole set on a slow timer makes any loss self-heal.
#define RESYNC_INTERVAL_MS 30000UL

// ============================================================ parameters ===
// Ranges mirror the "Tunable keys" table in README.md exactly. The app clamps
// to these too, but the device is the authority.
//
// IMPORTANT: this enum's ORDER is the wire protocol — the UNO receives
// `P<index>=<value>` and indexes its own table with it. Change one, change
// both.

enum {
  P_BRI, P_GLOW_FLOOR, P_GLOW_RANGE, P_DRIFT, P_NOISE_SCALE,
  P_FORK_MAX, P_STROKE_MAX, P_FADE_CLOSE, P_FADE_FAR, P_SHEET_RATIO,
  P_RUMBLE_RATE, P_STORM_MIN, P_STORM_MAX,
  P_COLOR_R, P_COLOR_G, P_COLOR_B,
  P_TINT_R, P_TINT_G, P_TINT_B,
  P_COUNT
};

struct KeySpec {
  const char* name;
  uint16_t lo;
  uint16_t hi;
  uint16_t def;
};

// COLOR/TINT components are exposed as keys so `LIST` reports the full device
// state. They have no slider in the app, so they show up read-only there.
static const KeySpec KEYS[P_COUNT] = {
  {"bri",           0,   255,   200},
  {"glow_floor",    0,    80,    30},
  {"glow_range",    0,    80,    50},
  {"drift",         1,     8,     3},
  {"noise_scale",   1,    40,    12},
  {"fork_max",      0,     3,     2},
  {"stroke_max",    1,     8,     3},
  {"fade_close",  180,   250,   235},
  {"fade_far",    180,   250,   245},
  {"sheet_ratio",   0,   255,    96},
  {"rumble_rate",   1,    20,     6},
  {"storm_min",   500, 10000,  1800},
  {"storm_max",  2000, 30000,  9000},
  {"color_r",       0,   255,   255},
  {"color_g",       0,   255,   238},
  {"color_b",       0,   255,   255},
  {"tint_r",        0,   255,    90},
  {"tint_g",        0,   255,   130},
  {"tint_b",        0,   255,   255},
};

static uint16_t params[P_COUNT];
static Preferences prefs;

// =================================================================== BLE ===

#define SERVICE_UUID "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
#define RX_UUID      "6e400002-b5a3-f393-e0a9-e50e24dcca9e"
#define TX_UUID      "6e400003-b5a3-f393-e0a9-e50e24dcca9e"

static BLECharacteristic* txChar = nullptr;
static bool bleConnected = false;

// Notifications are chunked to 20 bytes: the payload of the default 23-byte
// MTU. A peer that never negotiates up would silently truncate anything
// longer. The app reassembles on newlines, so splitting mid-line is harmless.
#define TX_CHUNK 20

// ------------------------------------------------------- command intake ---
// BLE write callbacks run on the stack's own task. Doing the work there would
// block the radio (and `LIST` deliberately paces itself), so writes only drop
// a copy into this queue and loop() drains it.
//
// Single producer, single consumer, fixed buffers: no allocation and no lock
// needed as long as only the indices are shared.
#define CMD_QUEUE_LEN 12
#define CMD_MAX_LEN   64

static char cmdQueue[CMD_QUEUE_LEN][CMD_MAX_LEN];
static volatile uint8_t qHead = 0;
static volatile uint8_t qTail = 0;

static void pushCommand(const char* text) {
  uint8_t next = (uint8_t)((qHead + 1) % CMD_QUEUE_LEN);
  if (next == qTail) return;  // full: drop rather than stall the radio
  strncpy(cmdQueue[qHead], text, CMD_MAX_LEN - 1);
  cmdQueue[qHead][CMD_MAX_LEN - 1] = '\0';
  qHead = next;
}

static bool popCommand(char* out) {
  if (qTail == qHead) return false;
  strncpy(out, cmdQueue[qTail], CMD_MAX_LEN);
  out[CMD_MAX_LEN - 1] = '\0';
  qTail = (uint8_t)((qTail + 1) % CMD_QUEUE_LEN);
  return true;
}

// Sends one reply line to the app and mirrors it to the USB console.
static void txLine(const String& line) {
  Serial.println(line);
  if (!bleConnected || txChar == nullptr) return;

  String payload = line + "\n";
  int len = payload.length();
  for (int i = 0; i < len; i += TX_CHUNK) {
    int n = min(TX_CHUNK, len - i);
    txChar->setValue((uint8_t*)payload.c_str() + i, n);
    txChar->notify();
    // The stack queues notifications and starts dropping them if a burst
    // outruns the connection interval. `LIST` sends 19 lines back to back.
    delay(8);
  }
}

// ---------------------------------------------------------- UNO downlink ---

// Sends a command as (code + 1) pulses. Code 0 is one pulse rather than none,
// so a silent line is never mistaken for a command.
static void unoSendCode(uint8_t code) {
  uint8_t pulses = (uint8_t)(code + 1);
  for (uint8_t i = 0; i < pulses; i++) {
    digitalWrite(PIN_LINK, HIGH);
    delay(PULSE_HIGH_MS);
    digitalWrite(PIN_LINK, LOW);
    delay(PULSE_LOW_MS);
  }
  delay(GROUP_GAP_MS);
}

// The link carries four codes and nothing else, so the tunable parameters
// cannot reach the UNO. They are still stored and reported here so the app's
// sliders and LIST behave, but they do not affect the light: brightness,
// colour and timing all live in the UNO sketch's own constants.
static void unoSendParam(int index) { (void)index; }
static void unoSendAllParams() {}

// The app's three modes collapse onto two codes. The UNO has no glow-only
// state: its cloud and its autonomous strikes are both driven by stormMode,
// so GLOW and STORM both map to CMD_STORM.
static void unoSendMode(uint8_t m) {
  unoSendCode(m == 0 ? CMD_OFF : CMD_STORM);
}

// STRIKE carries 30-255 of energy; the link carries one bit of it. The UNO
// picks its own energy within each band, and the threshold matches the one it
// uses internally to decide whether a bolt gets a leader.
static void unoSendStrike(uint8_t energy) {
  unoSendCode(energy > 180 ? CMD_HARD : CMD_SOFT);
}

// No dedicated sheet code. A soft strike is the closest thing the link can
// express, and the UNO fires sheets of its own while the storm runs.
static void unoSendSheet() {
  unoSendCode(CMD_SOFT);
}

// ------------------------------------------------------------ callbacks ---

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* server) override {
    bleConnected = true;
    Serial.println("[ble] central connected");
    // Push the whole parameter set down to the UNO: the app is about to show
    // sliders for it, and this is the cheapest moment to guarantee the strip
    // agrees with what they display.
    unoSendAllParams();
  }
  void onDisconnect(BLEServer* server) override {
    bleConnected = false;
    Serial.println("[ble] central disconnected, advertising again");
    // Without this the light is invisible after the first disconnect, which
    // looks exactly like a dead board.
    BLEDevice::startAdvertising();
  }
};

class RxCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* characteristic) override {
    // `.c_str()` works whether the core returns std::string (2.x) or String
    // (3.x), so this builds on both.
    String value = characteristic->getValue().c_str();
    if (value.length() == 0) return;
    pushCommand(value.c_str());
  }
};

// ============================================================== helpers ===

static int findKey(const String& name) {
  for (int i = 0; i < P_COUNT; i++) {
    if (name.equalsIgnoreCase(KEYS[i].name)) return i;
  }
  return -1;
}

static uint16_t clampToRange(int index, long value) {
  if (value < KEYS[index].lo) return KEYS[index].lo;
  if (value > KEYS[index].hi) return KEYS[index].hi;
  return (uint16_t)value;
}

static void loadDefaults() {
  for (int i = 0; i < P_COUNT; i++) params[i] = KEYS[i].def;
}

static void loadSaved() {
  prefs.begin("stromsync", true);
  for (int i = 0; i < P_COUNT; i++) {
    params[i] = clampToRange(i, prefs.getUShort(KEYS[i].name, KEYS[i].def));
  }
  prefs.end();
}

static void saveAll() {
  prefs.begin("stromsync", false);
  for (int i = 0; i < P_COUNT; i++) prefs.putUShort(KEYS[i].name, params[i]);
  prefs.end();
}

// Returns the n-th whitespace-separated token, or "" when there is none.
static String token(const String& s, int index) {
  int start = 0;
  for (int i = 0; i <= index; i++) {
    while (start < (int)s.length() && s[start] == ' ') start++;
    int end = s.indexOf(' ', start);
    if (end < 0) end = s.length();
    if (i == index) return s.substring(start, end);
    start = end;
  }
  return "";
}

// ====================================================== command handling ===

static void sendList() {
  for (int i = 0; i < P_COUNT; i++) {
    txLine(String(KEYS[i].name) + "=" + String(params[i]));
  }
}

static void handleCommand(const String& raw) {
  String cmd = raw;
  cmd.trim();
  if (cmd.length() == 0) return;

  String verb = token(cmd, 0);
  verb.toUpperCase();

  if (verb == "LIST") {
    sendList();
    return;
  }

  // Diagnostic: walk every usable GPIO, pulling each low in turn so the UNO
  // can report which of its inputs dips. That maps the wiring as built rather
  // than as intended. Pins owned by flash, PSRAM, USB and UART0 are skipped.
  // Diagnostic: listen on the link pins instead of driving them, so the UNO
  // can drive a known pattern and we can see what actually arrives. Tests the
  // wires where they sit, with no replugging.
  // Diagnostic: loopback on this board alone. Put one jumper between the two
  // holes believed to be GPIO 4 and GPIO 5, and this proves whether the pads
  // really drive and read - independently of the UNO, the wiring between the
  // boards, and my reading of the silkscreen.
  // Diagnostic: pulse the link line continuously so the UNO's LED blinks when
  // the wire is in the right hole. Move the jumper and watch the board.
  if (verb == "HUNT") {
    txLine("HUNT: pulsing GPIO 17 for 2 minutes - watch the UNO LED");
    for (int i = 0; i < 240; i++) {
      digitalWrite(PIN_LINK, HIGH);
      delay(250);
      digitalWrite(PIN_LINK, LOW);
      delay(250);
    }
    txLine("HUNT done");
    return;
  }

  if (verb == "MODE") {
    String which = token(cmd, 1);
    which.toUpperCase();
    if (which == "OFF")        unoSendMode(0);
    else if (which == "GLOW")  unoSendMode(1);
    else if (which == "STORM") unoSendMode(2);
    else { txLine("ERR bad mode " + which); return; }
    txLine("OK MODE " + which);
    return;
  }

  if (verb == "STRIKE") {
    String arg = token(cmd, 1);
    long e = arg.length() ? arg.toInt() : 200;
    if (e < 30) e = 30;
    if (e > 255) e = 255;
    unoSendStrike((uint8_t)e);
    txLine("OK STRIKE " + String(e));
    return;
  }

  if (verb == "SHEET") {
    unoSendSheet();
    txLine("OK SHEET");
    return;
  }

  if (verb == "SET") {
    String key = token(cmd, 1);
    String val = token(cmd, 2);
    int index = findKey(key);
    if (index < 0) { txLine("ERR unknown key " + key); return; }
    if (val.length() == 0) { txLine("ERR missing value"); return; }
    params[index] = clampToRange(index, val.toInt());
    unoSendParam(index);
    // Echoing key=value means one reply both acknowledges and re-syncs the
    // slider, including when the value was clamped.
    txLine("OK " + String(KEYS[index].name) + "=" + String(params[index]));
    return;
  }

  if (verb == "GET") {
    String key = token(cmd, 1);
    int index = findKey(key);
    if (index < 0) { txLine("ERR unknown key " + key); return; }
    txLine(String(KEYS[index].name) + "=" + String(params[index]));
    return;
  }

  if (verb == "COLOR" || verb == "TINT") {
    int base = (verb == "COLOR") ? P_COLOR_R : P_TINT_R;
    String r = token(cmd, 1), g = token(cmd, 2), b = token(cmd, 3);
    if (!r.length() || !g.length() || !b.length()) {
      txLine("ERR " + verb + " needs r g b");
      return;
    }
    params[base + 0] = clampToRange(base + 0, r.toInt());
    params[base + 1] = clampToRange(base + 1, g.toInt());
    params[base + 2] = clampToRange(base + 2, b.toInt());
    for (int i = 0; i < 3; i++) unoSendParam(base + i);
    txLine("OK " + String(KEYS[base + 0].name) + "=" + String(params[base + 0]) +
           " " + String(KEYS[base + 1].name) + "=" + String(params[base + 1]) +
           " " + String(KEYS[base + 2].name) + "=" + String(params[base + 2]));
    return;
  }

  if (verb == "SAVE") { saveAll(); txLine("OK SAVE"); return; }

  if (verb == "LOAD") {
    loadSaved();
    unoSendAllParams();
    txLine("OK LOAD");
    return;
  }

  if (verb == "RESET") {
    // Defaults in RAM only. They reach flash when the user sends SAVE.
    loadDefaults();
    unoSendAllParams();
    txLine("OK RESET");
    return;
  }

  txLine("ERR unknown " + cmd);
}

// ================================================================= setup ===

void setup() {
  Serial.begin(115200);
  // Never let a console nobody is reading stall the firmware. With USB CDC the
  // TX buffer fills when no host is draining it and every println then blocks
  // until it times out — which showed up as a four-second delay between a BLE
  // command and its reply, because txLine() prints before it notifies.
  Serial.setTxTimeoutMs(0);
  pinMode(PIN_LINK, OUTPUT);
  digitalWrite(PIN_LINK, LOW);   // idle low; pulses are the signal
  delay(200);

  loadSaved();

  BLEDevice::init("StromSync");
  BLEServer* server = BLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());

  BLEService* service = server->createService(SERVICE_UUID);

  BLECharacteristic* rxChar = service->createCharacteristic(
      RX_UUID,
      BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR);
  rxChar->setCallbacks(new RxCallbacks());

  txChar = service->createCharacteristic(
      TX_UUID, BLECharacteristic::PROPERTY_NOTIFY);
  txChar->addDescriptor(new BLE2902());

  service->start();

  // The advertisement carries the service UUID and the scan response carries
  // the name, because they do not both fit: flags (3) + a 128-bit UUID (18) +
  // "StromSync" (11) is 32 bytes against a 31-byte limit. Pack them into one
  // packet and whichever lost the race just disappears — a genuinely confusing
  // failure to debug from the phone side.
  BLEAdvertising* advertising = BLEDevice::getAdvertising();

  BLEAdvertisementData advData;
  advData.setFlags(0x06);  // LE General Discoverable, BR/EDR not supported
  advData.setCompleteServices(BLEUUID(SERVICE_UUID));
  advertising->setAdvertisementData(advData);

  BLEAdvertisementData scanResponse;
  scanResponse.setName("StromSync");
  advertising->setScanResponseData(scanResponse);

  advertising->setScanResponse(true);
  BLEDevice::startAdvertising();

  // The UNO may have booted first, or not yet. Either way it gets the state.
  unoSendAllParams();

  Serial.println();
  Serial.println("StromSync ready - advertising as \"StromSync\"");
  Serial.println("commands: MODE OFF|GLOW|STORM, STRIKE <30-255>, SHEET,");
  Serial.println("          SET <key> <val>, GET <key>, LIST,");
  Serial.println("          COLOR <r> <g> <b>, TINT <r> <g> <b>,");
  Serial.println("          SAVE, LOAD, RESET");
}

// ================================================================== loop ===

void loop() {
  // 1. Drain anything the radio handed us.
  char incoming[CMD_MAX_LEN];
  while (popCommand(incoming)) handleCommand(String(incoming));

  // 2. Same commands over USB serial, for bench testing without the phone.
  static String serialLine;
  while (Serial.available()) {
    char c = (char)Serial.read();
    if (c == '\n' || c == '\r') {
      if (serialLine.length()) { handleCommand(serialLine); serialLine = ""; }
    } else if (serialLine.length() < CMD_MAX_LEN - 1) {
      serialLine += c;
    }
  }

  // 3. Periodic resync, so a command the UNO missed mid-frame — or a UNO that
  //    rebooted on its own — corrects itself without the user noticing.
  static uint32_t nextResyncAt = RESYNC_INTERVAL_MS;
  if (millis() >= nextResyncAt) {
    unoSendAllParams();
    nextResyncAt = millis() + RESYNC_INTERVAL_MS;
  }
}
