/*
 * LinkDrive_UNO — drives the link pins so the ESP32 can listen
 *
 * Temporary diagnostic, the mirror image of LinkScan. Rather than asking the
 * UNO to detect what the ESP32 sends, this drives a known pattern from the UNO
 * and lets the ESP32 report what arrives. Same wires, same connectors, tested
 * exactly where they sit — nothing has to be unplugged.
 *
 * The UNO's outputs swing a full 5 V, so unlike the other direction there is
 * no marginal-threshold question: if a wire conducts, the ESP32 will see it.
 * (5 V into a 3.3 V pin is out of spec, but the ESP32's clamp diodes handle it
 * briefly at these currents, and this sketch is not left running.)
 *
 * Pattern, one step per 2 s, cycling 0..7 as a 3-bit count:
 *   D2 = bit 0    D4 = bit 1    D5 = bit 2
 */

const uint8_t PIN_D2 = 2;
const uint8_t PIN_D4 = 4;
const uint8_t PIN_D5 = 5;

void setup() {
  Serial.begin(9600);
  pinMode(PIN_D2, OUTPUT);
  pinMode(PIN_D4, OUTPUT);
  pinMode(PIN_D5, OUTPUT);
  Serial.println(F("LinkDrive ready - counting 0..7 on D2/D4/D5"));
}

void loop() {
  static uint8_t n = 0;
  static unsigned long nextAt = 0;

  if (millis() >= nextAt) {
    nextAt = millis() + 2000;
    digitalWrite(PIN_D2, (n & 1) ? HIGH : LOW);
    digitalWrite(PIN_D4, (n & 2) ? HIGH : LOW);
    digitalWrite(PIN_D5, (n & 4) ? HIGH : LOW);
    Serial.print(F("DRIVE d2="));
    Serial.print((n & 1) ? 1 : 0);
    Serial.print(F(" d4="));
    Serial.print((n & 2) ? 1 : 0);
    Serial.print(F(" d5="));
    Serial.println((n & 4) ? 1 : 0);
    n = (uint8_t)((n + 1) & 7);
  }
}
