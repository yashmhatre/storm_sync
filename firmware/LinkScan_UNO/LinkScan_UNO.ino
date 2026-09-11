/*
 * LinkScan_UNO — finds which UNO pins are actually wired to the ESP32
 *
 * Temporary diagnostic. Every candidate input is held up by its internal
 * pullup, so an unconnected pin reads HIGH and sits still. The ESP32 walks
 * its own GPIOs pulling each one LOW in turn; whichever UNO pin dips is
 * physically connected to whichever ESP32 pin was low at that moment.
 *
 * Pulling low rather than driving high is deliberate: the AVR has no internal
 * pulldown, so a floating input cannot be told from a driven one. A pullup
 * gives every unconnected pin a definite resting state, and it also sidesteps
 * the 3.3 V / 5 V threshold problem entirely — a low is a low.
 *
 * D0/D1 are the USB serial pair and D6 drives the strip, so all three are
 * left out.
 */

const uint8_t PINS[] = {2, 3, 4, 5, 7, 8, 9, 10, 11, 12, 13, A0, A1, A2, A3, A4, A5};
const uint8_t N = sizeof(PINS) / sizeof(PINS[0]);

char lastReport[64] = "";

void setup() {
  Serial.begin(9600);
  for (uint8_t i = 0; i < N; i++) pinMode(PINS[i], INPUT_PULLUP);
  delay(200);
  Serial.println(F("LinkScan ready - watching for pins pulled LOW"));
}

void loop() {
  char buf[64];
  uint8_t n = 0;
  buf[0] = '\0';

  for (uint8_t i = 0; i < N; i++) {
    if (digitalRead(PINS[i]) == LOW) {
      char item[8];
      uint8_t p = PINS[i];
      if (p >= A0) snprintf(item, sizeof(item), "A%d ", p - A0);
      else         snprintf(item, sizeof(item), "D%d ", p);
      if (strlen(buf) + strlen(item) < sizeof(buf) - 1) strcat(buf, item);
      n++;
    }
  }

  // Report every second regardless of change. Reporting only on change made a
  // disconnected wire indistinguishable from a scanner that had stopped
  // running — both produced silence.
  static unsigned long nextAt = 0;
  if (millis() >= nextAt) {
    nextAt = millis() + 1000;
    Serial.print(F("LOW: "));
    Serial.print(n == 0 ? "(none)" : buf);
    Serial.print(F("   d2="));
    Serial.print(digitalRead(2));
    Serial.print(F(" d4="));
    Serial.print(digitalRead(4));
    Serial.print(F(" d5="));
    Serial.println(digitalRead(5));
  }

  delay(20);
}
