/*
  Cube de statut - firmware
  Carte : Seeed Studio XIAO nRF52840 Sense
  Coeur Arduino : "Seeed nRF52 Boards" (Seeeduino:nrf52, PAS la version mbed)
  Bibliotheques : Adafruit NeoPixel, Seeed Arduino LSM6DS3

  Cablage (voir fiche projet) :
    D0  -> 330 ohm -> DIN de l'anneau WS2812 (12 LED)
    D1  -> grille du MOSFET P AO3401 (pull-up 10k vers 3V3) - LOW = anneau alimente
    3V3 -> source du AO3401, drain -> VCC de l'anneau
    BAT+/BAT- -> batterie LiPo 703450

  Protocole Bluetooth : voir PROTOCOLE.md
*/

#include <bluefruit.h>
#include <Adafruit_LittleFS.h>
#include <InternalFileSystem.h>
#include <Adafruit_NeoPixel.h>
#include <LSM6DS3.h>
#include <Wire.h>

using namespace Adafruit_LittleFS_Namespace;

// ---------------------------------------------------------------- reglages
#define FW_VERSION        "1.1.0"   // lue par l'app (Device Information, Firmware Revision)
#define NUM_LEDS          12
#define PIN_LED_DATA      D0
#define PIN_LED_POWER     D1        // LOW = anneau alimente (MOSFET P)
#define PIN_CHG_STATUS    23        // P0.17, LOW = en charge (BQ25101)
#define PIN_HICHG         22        // P0.13, LOW = charge a 100 mA

#define DEFAULT_BRIGHTNESS   25     // % de la puissance max des LED
#define MAX_BRIGHTNESS       40     // plafond (budget 200 mA du 3V3)
#define DEFAULT_FOCUS_MIN    60     // duree du mode concentre
#define AUTO_CALL_TIMEOUT_MS 30000  // l'ordinateur doit rafraichir l'appel
#define FACE_DEBOUNCE_MS     600    // la face doit etre stable aussi longtemps
#define FACE_MIN_G           0.75f  // composante minimale de la gravite

enum Status : uint8_t { ST_OFF = 0, ST_AVAILABLE = 1, ST_FOCUS = 2, ST_CALL = 3, ST_DISCO = 4 };  // disco : a distance seulement
enum Source : uint8_t { SRC_FACE = 0, SRC_REMOTE = 1, SRC_AUTO = 2 };

// UUID (ordre des octets inverse, format Bluefruit)
// 7c0be000-5a7e-4b1d-9c3a-2f6d8e1b4a00
const uint8_t UUID_SVC[16]    = {0x00,0x4a,0x1b,0x8e,0x6d,0x2f,0x3a,0x9c,0x1d,0x4b,0x7e,0x5a,0x00,0xe0,0x0b,0x7c};
const uint8_t UUID_STATUS[16] = {0x00,0x4a,0x1b,0x8e,0x6d,0x2f,0x3a,0x9c,0x1d,0x4b,0x7e,0x5a,0x01,0xe0,0x0b,0x7c};
const uint8_t UUID_CMD[16]    = {0x00,0x4a,0x1b,0x8e,0x6d,0x2f,0x3a,0x9c,0x1d,0x4b,0x7e,0x5a,0x02,0xe0,0x0b,0x7c};

// --------------------------------------------------------------- objets
BLEDfu            bledfu;                 // mise a jour du firmware par Bluetooth (OTA DFU)
BLEService        svcCube(UUID_SVC);
BLECharacteristic chrStatus(UUID_STATUS);
BLECharacteristic chrCmd(UUID_CMD);
BLEBas            blebas;
BLEDis            bledis;

Adafruit_NeoPixel ring(NUM_LEDS, PIN_LED_DATA, NEO_GRB + NEO_KHZ800);
LSM6DS3           imu(I2C_MODE, 0x6A);

// --------------------------------------------------------------- config persistante
struct Config {
  uint8_t magic;
  uint8_t faceStatus[6];   // statut affiche pour chaque face posee
  uint8_t brightness;
  uint8_t focusMinutes;
};
Config cfg;
const char *CFG_FILE = "/cube.cfg";

// Faces : 0 = +X en haut, 1 = -X en haut, 2 = +Y, 3 = -Y, 4 = +Z (LED vers le haut), 5 = -Z (LED contre la table)
// Valeurs par defaut, ajustables depuis l'appli (commande 0x05 "apprentissage").
void defaultConfig() {
  cfg.magic = 0xC7;
  cfg.faceStatus[0] = ST_AVAILABLE;  // USB-C en haut
  cfg.faceStatus[1] = ST_AVAILABLE;  // USB-C en bas
  cfg.faceStatus[2] = ST_FOCUS;
  cfg.faceStatus[3] = ST_CALL;
  cfg.faceStatus[4] = ST_AVAILABLE;  // a plat, LED vers le haut
  cfg.faceStatus[5] = ST_OFF;        // retourne : eteint
  cfg.brightness = DEFAULT_BRIGHTNESS;
  cfg.focusMinutes = DEFAULT_FOCUS_MIN;
}

void loadConfig() {
  defaultConfig();
  File f(InternalFS);
  if (f.open(CFG_FILE, FILE_O_READ)) {
    Config tmp;
    if (f.read(&tmp, sizeof(tmp)) == sizeof(tmp) && tmp.magic == 0xC7) cfg = tmp;
    f.close();
  }
}

void saveConfig() {
  InternalFS.remove(CFG_FILE);
  File f(InternalFS);
  if (f.open(CFG_FILE, FILE_O_WRITE)) { f.write((uint8_t *)&cfg, sizeof(cfg)); f.close(); }
}

// --------------------------------------------------------------- etat
volatile int8_t   remoteStatus  = -1;     // -1 = aucun choix a distance
volatile bool     autoCall      = false;
volatile uint32_t autoCallSeen  = 0;
volatile bool     cfgDirty      = false;
volatile int8_t   learnRequest  = -1;     // statut a associer a la face actuelle
volatile bool     factoryReset  = false;

int8_t   face           = 4;              // face stable
int8_t   faceCandidate  = 4;
uint32_t faceCandidateT = 0;
uint32_t faceSince      = 0;
bool     focusExpired   = false;

uint8_t  shownStatus = 255, shownSource = 255;
uint8_t  batteryPct = 100;
bool     charging = false;
bool     ledsPowered = false;

// --------------------------------------------------------------- batterie
float readBatteryVolts() {
  // pont diviseur 1M / 510k, reference interne 3.6 V
  analogReference(AR_INTERNAL);
  analogReadResolution(12);
  uint32_t sum = 0;
  for (int i = 0; i < 8; i++) sum += analogRead(PIN_VBAT);
  float adc = sum / 8.0f;
  return adc * (3.6f / 4096.0f) * (1510.0f / 510.0f);
}

uint8_t voltsToPercent(float v) {
  // courbe LiPo simplifiee
  const float pts[][2] = {{4.15f,100},{4.05f,90},{3.95f,78},{3.87f,65},{3.80f,52},
                          {3.75f,40},{3.70f,28},{3.65f,18},{3.55f,8},{3.40f,0}};
  if (v >= pts[0][0]) return 100;
  for (int i = 1; i < 10; i++) {
    if (v >= pts[i][0]) {
      float t = (v - pts[i][0]) / (pts[i-1][0] - pts[i][0]);
      return (uint8_t)(pts[i][1] + t * (pts[i-1][1] - pts[i][1]));
    }
  }
  return 0;
}

void updateBattery() {
  charging = digitalRead(PIN_CHG_STATUS) == LOW;
  uint8_t p = voltsToPercent(readBatteryVolts());
  static bool lastCharging = false;
  if (p != batteryPct || charging != lastCharging) { batteryPct = p; lastCharging = charging; blebas.notify(batteryPct); shownStatus = 255; }
}

// --------------------------------------------------------------- orientation
int8_t readFace() {
  float ax = imu.readFloatAccelX();
  float ay = imu.readFloatAccelY();
  float az = imu.readFloatAccelZ();
  float fx = fabsf(ax), fy = fabsf(ay), fz = fabsf(az);
  if (fx >= fy && fx >= fz && fx > FACE_MIN_G) return ax > 0 ? 0 : 1;
  if (fy >= fx && fy >= fz && fy > FACE_MIN_G) return ay > 0 ? 2 : 3;
  if (fz >= fx && fz >= fy && fz > FACE_MIN_G) return az > 0 ? 4 : 5;
  return -1;  // en mouvement ou en biais
}

void updateFace(uint32_t now) {
  int8_t f = readFace();
  if (f < 0) return;
  if (f != faceCandidate) { faceCandidate = f; faceCandidateT = now; return; }
  if (f != face && now - faceCandidateT >= FACE_DEBOUNCE_MS) {
    face = f;
    faceSince = now;
    focusExpired = false;
    remoteStatus = -1;          // retourner le cube reprend la main
    Serial.printf("Face %d -> statut %d\n", face, cfg.faceStatus[face]);
  }
}

// --------------------------------------------------------------- statut effectif
void effectiveStatus(uint32_t now, uint8_t &st, uint8_t &src) {
  if (autoCall && now - autoCallSeen > AUTO_CALL_TIMEOUT_MS) autoCall = false;

  uint8_t faceSt = cfg.faceStatus[face];
  if (faceSt == ST_FOCUS && !focusExpired &&
      now - faceSince > (uint32_t)cfg.focusMinutes * 60000UL) focusExpired = true;
  if (faceSt == ST_FOCUS && focusExpired) faceSt = ST_AVAILABLE;

  if (cfg.faceStatus[face] == ST_OFF) { st = ST_OFF; src = SRC_FACE; return; }
  if (autoCall)                       { st = ST_CALL; src = SRC_AUTO; return; }
  if (remoteStatus >= 0)              { st = remoteStatus; src = SRC_REMOTE; return; }
  st = faceSt; src = SRC_FACE;
}

void publishStatus(uint8_t st, uint8_t src) {
  uint8_t flags = (charging ? 1 : 0) | (autoCall ? 2 : 0) | (focusExpired ? 4 : 0);
  uint8_t buf[4] = {st, src, batteryPct, flags};
  chrStatus.write(buf, 4);
  for (uint16_t c = 0; c < BLE_MAX_CONNECTION; c++) {
    if (Bluefruit.connected(c) && chrStatus.notifyEnabled(c)) chrStatus.notify(c, buf, 4);
  }
}

// --------------------------------------------------------------- LED
// Chaque statut a sa couleur ET son mouvement, lisible sans distinguer les couleurs :
//   disponible = vert fixe, concentre = ambre qui respire, en appel = rouge avec un point qui tourne
//   disco = couleurs qui changent en rythme (choix a distance uniquement)
void ledPower(bool on) {
  if (on == ledsPowered) return;
  if (on) { digitalWrite(PIN_LED_POWER, LOW); delay(2); }
  else    { ring.clear(); ring.show(); digitalWrite(PIN_LED_POWER, HIGH); digitalWrite(PIN_LED_DATA, LOW); }
  ledsPowered = on;
}

uint32_t scaled(uint8_t r, uint8_t g, uint8_t b, float k) {
  k *= cfg.brightness / 100.0f;
  return ring.Color((uint8_t)(r * k), (uint8_t)(g * k), (uint8_t)(b * k));
}

void renderLeds(uint8_t st, uint32_t now) {
  if (st == ST_OFF) { ledPower(false); return; }
  ledPower(true);
  switch (st) {
    case ST_AVAILABLE:
      for (int i = 0; i < NUM_LEDS; i++) ring.setPixelColor(i, scaled(0, 200, 60, 0.6f));
      break;
    case ST_FOCUS: {
      float ph = (now % 4000) / 4000.0f * 2 * PI;
      float k = 0.2f + 0.8f * (0.5f - 0.5f * cosf(ph));
      for (int i = 0; i < NUM_LEDS; i++) ring.setPixelColor(i, scaled(255, 110, 0, k));
      break;
    }
    case ST_CALL: {
      float pos = (now % 2400) / 2400.0f * NUM_LEDS;
      for (int i = 0; i < NUM_LEDS; i++) {
        float d = fabsf(i - pos); if (d > NUM_LEDS / 2) d = NUM_LEDS - d;
        float k = 0.55f + 0.45f * max(0.0f, 1.0f - d / 2.0f);
        ring.setPixelColor(i, scaled(255, 0, 0, k));
      }
      break;
    }
    case ST_DISCO: {
      // 120 battements par minute (2 Hz, sous le seuil des 3 eclairs par seconde).
      // Trois figures qui alternent toutes les 8 battements.
      const uint32_t BEAT_MS = 500;
      uint32_t beat  = now / BEAT_MS;
      float    inBeat = (now % BEAT_MS) / (float)BEAT_MS;      // 0..1 dans le battement
      float    pulse = 1.0f - 0.65f * inBeat;                  // coup sur le temps, puis retombee
      uint8_t  figure = (beat / 8) % 3;
      uint16_t baseHue = (uint16_t)(beat * 9362UL);            // saut de couleur a chaque battement
      for (int i = 0; i < NUM_LEDS; i++) {
        uint16_t hue; float k;
        if (figure == 0) {                                     // arc-en-ciel qui tourne
          hue = (uint16_t)(now * 40UL) + (uint16_t)(i * (65536UL / NUM_LEDS));
          k = 0.45f + 0.55f * pulse;
        } else if (figure == 1) {                              // anneau entier, une couleur par battement
          hue = baseHue;
          k = pulse;
        } else {                                               // deux points opposes qui tournent
          float pos = (now % 1000) / 1000.0f * NUM_LEDS;
          float d = fabsf(i - pos); if (d > NUM_LEDS / 2) d = NUM_LEDS - d;
          float d2 = fabsf(d - NUM_LEDS / 2.0f);
          float near = max(0.0f, 1.0f - min(d, d2) / 1.5f);
          hue = baseHue + (d < d2 ? 0 : 32768);
          k = 0.12f + 0.88f * near;
        }
        uint8_t v = (uint8_t)(255.0f * k * cfg.brightness / 100.0f);
        ring.setPixelColor(i, ring.ColorHSV(hue, 255, v));
      }
      break;
    }
  }
  // batterie faible : une LED clignote en blanc 0.2 s toutes les 10 s
  if (batteryPct <= 10 && !charging && (now % 10000) < 200) ring.setPixelColor(0, scaled(255, 255, 255, 1.0f));
  ring.show();
}

// --------------------------------------------------------------- BLE
void onCommand(uint16_t conn, BLECharacteristic *chr, uint8_t *data, uint16_t len) {
  (void)conn; (void)chr;
  if (len < 1) return;
  uint8_t cmd = data[0], val = len > 1 ? data[1] : 0;
  switch (cmd) {
    case 0x01: remoteStatus = (val >= 1 && val <= 4) ? (int8_t)val : -1; break;   // 4 = disco
    case 0x02: autoCall = val != 0; autoCallSeen = millis(); break;
    case 0x03: cfg.brightness = constrain(val, 5, MAX_BRIGHTNESS); cfgDirty = true; break;
    case 0x04: cfg.focusMinutes = constrain(val, 1, 240); cfgDirty = true; break;
    case 0x05: if (val <= 3) learnRequest = val; break;
    case 0x06: factoryReset = true; break;
  }
  shownStatus = 255;  // forcer la republication
}

void onConnect(uint16_t conn)    { Serial.printf("Connexion %d\n", conn); shownStatus = 255; }
void onDisconnect(uint16_t conn, uint8_t reason) { Serial.printf("Deconnexion %d (0x%02X)\n", conn, reason); }

void setupBLE() {
  Bluefruit.begin(2, 0);                 // 2 connexions simultanees (ordinateur + iPhone)
  Bluefruit.setTxPower(0);
  uint8_t mac[6]; Bluefruit.getAddr(mac);
  char name[24]; snprintf(name, sizeof(name), "Cube-Statut-%02X%02X", mac[1], mac[0]);
  Bluefruit.setName(name);
  Bluefruit.Periph.setConnectCallback(onConnect);
  Bluefruit.Periph.setDisconnectCallback(onDisconnect);
  Bluefruit.Periph.setConnInterval(24, 80);  // 30-100 ms

  bledfu.begin();                        // a declarer en premier (recommandation Adafruit)

  bledis.setManufacturer("DIY");
  bledis.setModel("Cube de statut v1");
  bledis.setFirmwareRev(FW_VERSION);
  bledis.begin();
  blebas.begin();
  blebas.write(batteryPct);

  svcCube.begin();
  chrStatus.setProperties(CHR_PROPS_READ | CHR_PROPS_NOTIFY);
  chrStatus.setPermission(SECMODE_OPEN, SECMODE_NO_ACCESS);
  chrStatus.setFixedLen(4);
  chrStatus.begin();
  chrCmd.setProperties(CHR_PROPS_WRITE | CHR_PROPS_WRITE_WO_RESP);
  chrCmd.setPermission(SECMODE_NO_ACCESS, SECMODE_OPEN);
  chrCmd.setMaxLen(4);
  chrCmd.setWriteCallback(onCommand);
  chrCmd.begin();

  Bluefruit.Advertising.addFlags(BLE_GAP_ADV_FLAGS_LE_ONLY_GENERAL_DISC_MODE);
  Bluefruit.Advertising.addTxPower();
  Bluefruit.Advertising.addService(svcCube);
  Bluefruit.ScanResponse.addName();
  Bluefruit.Advertising.restartOnDisconnect(true);
  Bluefruit.Advertising.setInterval(160, 1600);   // 100 ms puis 1 s (en unites de 0.625 ms)
  Bluefruit.Advertising.setFastTimeout(30);
  Bluefruit.Advertising.start(0);
}

// --------------------------------------------------------------- setup / loop
void setup() {
  pinMode(PIN_LED_POWER, OUTPUT); digitalWrite(PIN_LED_POWER, HIGH);   // anneau coupe au demarrage
  pinMode(VBAT_ENABLE, OUTPUT);   digitalWrite(VBAT_ENABLE, LOW);      // lecture batterie (recommande par Seeed)
  pinMode(PIN_HICHG, OUTPUT);     digitalWrite(PIN_HICHG, LOW);        // charge a 100 mA
  pinMode(PIN_CHG_STATUS, INPUT_PULLUP);

  Serial.begin(115200);
  InternalFS.begin();
  loadConfig();

  imu.settings.gyroEnabled = 0;
  imu.settings.accelSampleRate = 26;   // Hz, suffisant et economique
  imu.settings.accelRange = 2;
  if (imu.begin() != 0) Serial.println("IMU introuvable");

  ring.begin();
  updateBattery();
  setupBLE();

  face = faceCandidate = (readFace() >= 0 ? readFace() : 4);
  faceSince = millis();
}

void loop() {
  static uint32_t lastBattery = 0;
  uint32_t now = millis();

  if (factoryReset) { factoryReset = false; defaultConfig(); saveConfig(); }
  if (learnRequest >= 0) {
    cfg.faceStatus[face] = (uint8_t)learnRequest;
    learnRequest = -1; remoteStatus = -1; saveConfig();
    Serial.printf("Face %d apprise -> %d\n", face, cfg.faceStatus[face]);
  }
  if (cfgDirty) { cfgDirty = false; saveConfig(); }

  updateFace(now);
  if (now - lastBattery > 60000 || lastBattery == 0) { lastBattery = now; updateBattery(); }

  uint8_t st, src;
  effectiveStatus(now, st, src);
  if (st != shownStatus || src != shownSource) {
    shownStatus = st; shownSource = src;
    publishStatus(st, src);
  }
  renderLeds(st, now);

  // eteint : on ralentit tout (le CPU dort pendant delay)
  delay(st == ST_OFF ? 500 : 30);
}
