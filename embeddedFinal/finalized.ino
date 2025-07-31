#include <Wire.h>
#include "Adafruit_VEML7700.h"
#include <WiFi.h>
#include <HTTPClient.h>
#include <WebServer.h>
#include <ArduinoJson.h>
#include <Preferences.h>

#include "esp_task_wdt.h"

// ==== System State Management ====
enum SystemState {
  WIFI_SETUP_MODE,  // device awaiting wifi config
  MONITORING_MODE   // wifi is connected and can now monitor
};

bool veml7700SensorsNeedReinit = false;
unsigned long lastWateringEndTime = 0;
const unsigned long VEML7700_SKIP_AFTER_WATERING = 5000;  // Skip VEML7700 for 15 seconds after watering

bool reactiveLightControlEnabled = true;  // Enable reactive control
unsigned long lastReactiveLightUpdate = 0;
const unsigned long REACTIVE_LIGHT_INTERVAL = 2000;  // Update every 3 seconds

bool wateringInProgress = false;
unsigned long wateringStartTime = 0;
const unsigned long WATERING_DURATION = 5000;  // 5 seconds total protection
const unsigned long I2C_DELAY_AFTER_WATERING = 3000;  // 3 seconds after watering stops


SystemState currentState = WIFI_SETUP_MODE;
Preferences preferences;
WebServer server(80);

// ==== Shelly Device IPs ====
const char* shellyLightIP = "192.168.1.207";  // Light control device
const char* shellyWaterIP = "192.168.1.145";  // Watering control device

// ==== PCA9547D Multiplexer Configuration ====
#define SDA_PIN 13
#define SCL_PIN 14
#define PCA9547D_ADDR 0x70
#define SHT4X_ADDR 0x44

// ==== Environmental Sensor Configuration ====
// SHT4x sensor configuration
#define SHT4X_CHANNEL_START 0
#define SHT4X_CHANNEL_END 2
#define SHT4X_COUNT 3

// VEML7700 sensor configuration
#define VEML7700_CHANNEL_START 5
#define VEML7700_CHANNEL_END 7
#define VEML7700_COUNT 3

// SHT4x commands
#define SHT4X_CMD_MEASURE_HIGH_PRECISION 0xFD
#define SHT4X_CMD_SOFT_RESET 0x94

Adafruit_VEML7700 veml_sensors[VEML7700_COUNT];

// ==== Moisture Sensor ADC pins ====
#define AOUT_PIN 35   // Sensor 1
#define AOUT_PIN2 34  // Sensor 2
#define AOUT_PIN3 32  // Sensor 3

// ==== Shelly Light Control Channels ====
const int LIGHT_CHANNELS[3] = { 0, 2, 3 };  // Sensor 1->B(2), Sensor 2->R(0), Sensor 3->W(3)

// ==== Shelly Water Control Channels ====
const int W_CHANNEL = 3;  // W channel (white) - controlled by Pin 32
const int G_CHANNEL = 2;  // G channel (green) - controlled by Pin 34
const int B_CHANNEL = 1;  // B channel (blue) - controlled by Pin 35

// ==== Light Control - Lux Thresholds ====
// const float DARK_THRESHOLD = 230.0;
// const float DIM_THRESHOLD = 370.0;

const int channels[] = { 0, 1, 2, 3 };

// ==== Cubbies Data Storage (Setpoints) ====
struct CubbyData {
  int lightLower;
  int lightUpper;
  int soilLower;  // Wet threshold (lower values = wetter)
  int soilUpper;  // Dry threshold (higher values = drier)
  int humidityLower;
  int humidityUpper;
  int temperatureLower;
  int temperatureUpper;
  unsigned long lastUpdated;
  bool hasData;
};

CubbyData cubbiesData[3] = {
  { 230, 3000, 2000, 3000, 40, 65, 20, 27, 0, false },
  { 230, 3000, 2000, 3000, 40, 65, 20, 27, 0, false },
  { 230, 1000, 2000, 3000, 40, 65, 20, 27, 0, false }
};

// ==== Light Cycling States ====
enum CycleState { CYCLE_DARK,
                  CYCLE_DIM,
                  CYCLE_BRIGHT };
enum PhaseState { PHASE_ADJUSTING,
                  PHASE_HOLDING };

struct ChamberState {
  CycleState currentCycle;
  PhaseState currentPhase;
  int targetBrightness;
  int currentBrightness;
  unsigned long phaseStartTime;
  unsigned long lastAdjustTime;
  bool cycleComplete;
};

ChamberState chambers[3];

// ==== Sensor Reading Storage ====
int lastMoistureValue1 = 0;
int lastMoistureValue2 = 0;
int lastMoistureValue3 = 0;
String lastMoistureStatus1 = "unknown";
String lastMoistureStatus2 = "unknown";
String lastMoistureStatus3 = "unknown";

float lastTemp[3] = { 0 };
String lastTempStatus[3] = { "" };
float lastHumidity[3] = { 0 };
String lastHumidityStatus[3] = { "" };
float lastLux[3] = { 0 };
String lastLightStatus[3] = { "" };

// ==== Timing Configuration ====
unsigned long lastMoistureReadTime = 0;
unsigned long lastEnvironmentalReadTime = 0;
const unsigned long MOISTURE_INTERVAL = 10000;
const unsigned long ENVIRONMENTAL_INTERVAL = 5000;  // Even slower to reduce conflicts

// ==== Watering Control Variables ====
unsigned long lastWateringTime_B = 0;
unsigned long lastWateringTime_G = 0;
unsigned long lastWateringTime_W = 0;
const unsigned long MIN_WATERING_INTERVAL = 30000;

// ==== Global Light Cycle Control ====
// bool allChambersComplete = false;
unsigned long cycleStartTime = 0;

// ==== NEW: Continuous Light Cycling Control ====
bool lightCycleEnabled = true;  // Enable/disable continuous light cycling
bool lightsCurrentlyOn = false;
unsigned long lastLightToggle = 0;
const unsigned long LIGHT_CYCLE_INTERVAL = 5000;  // 5 seconds ON, 5 seconds OFF
const uint16_t HTTP_TIMEOUT_MS = 750;             // Fast HTTP timeout

// ==== I2C Health and Safety Variables ====
bool i2cBusOK = false;  // Start disabled
unsigned long lastI2CError = 0;
int i2cErrorCount = 0;
const int MAX_I2C_ERRORS = 3;  // Lower threshold for safety

// ==== SIMPLE DELAY-BASED PROTECTION ====
bool ENABLE_I2C_SENSORS = true;  // ENABLE I2C TO TEST
bool I2C_INIT_ATTEMPTED = false;
unsigned long lastWatchdogTime = 0;
const unsigned long WATCHDOG_MAX_INTERVAL = 2000;  // 2 seconds max without watchdog
unsigned long lastSuccessfulI2CRead = 0;
unsigned long lastMemoryCheck = 0;
const unsigned long MEMORY_CHECK_INTERVAL = 30000;  // Check every 30 seconds
unsigned long emergencyResetTimer = 0;
const unsigned long EMERGENCY_RESET_INTERVAL = 300000;  // 5 minutes

// ==== SIMPLE TIMING SEPARATION ====
unsigned long lastNetworkOperation = 0;
const unsigned long I2C_DELAY_AFTER_NETWORK = 500;  // Just 500ms delay after network ops

float targetLux[3] = { 0.0, 0.0, 0.0 };    // Will be calculated from user's cubby data
int targetBrightness[3] = { 20, 20, 20 };  // Will be calculated from targetLux
bool luxBasedControlEnabled = true;        // Enable/disable lux-based control
unsigned long lastLuxControlUpdate = 0;
const unsigned long LUX_CONTROL_INTERVAL = 5000;  // Update every 5 seconds

bool justWatered[3] = { false, false, false };
unsigned long lastWateringEventTime[3] = { 0, 0, 0 };

// ========== WiFi Setup Functions ==========
void handleWifiConfig() {
  lastNetworkOperation = millis();

  if (server.method() == HTTP_POST) {
    StaticJsonDocument<200> doc;
    DeserializationError error = deserializeJson(doc, server.arg("plain"));

    if (error) {
      server.send(400, "text/plain", "Invalid JSON");
      Serial.println("\n✗✗✗✗✗ JSON parse error");
      return;
    }

    const char* ssid = doc["ssid"];
    const char* password = doc["password"];

    // const char* ssid = "Zuperior WiFi";
    // const char* password = "Qwerty123!";

    Serial.println("ᯤ ᯤ ᯤ Attempting to connect with:");
    Serial.print("SSID: ");
    Serial.println(ssid);

    WiFi.begin(ssid, password);

    int attempts = 0;
    while (WiFi.status() != WL_CONNECTED && attempts++ < 30) {
      delay(500);
      Serial.print(".");
    }

    if (WiFi.status() == WL_CONNECTED) {
      Serial.println("\n✔✔✔✔ Connected to Wi-Fi!");
      Serial.print("IP address: ");
      Serial.println(WiFi.localIP());
      Serial.println();

      preferences.begin("wifi", false);
      preferences.putString("ssid", ssid);
      preferences.putString("password", password);
      preferences.end();

      StaticJsonDocument<200> response;
      response["status"] = "success";
      response["message"] = "Connected successfully! Switching to monitoring mode...";
      response["ip"] = WiFi.localIP().toString();

      String responseString;
      serializeJson(response, responseString);
      server.send(200, "application/json", responseString);

      delay(2000);
      switchToMonitoringMode();

    } else {
      Serial.println("\n!!!!!!! Failed to connect to Wi-Fi.");

      WiFi.disconnect();
      delay(1000);

      preferences.begin("wifi", false);
      preferences.remove("ssid");
      preferences.remove("password");
      preferences.end();

      StaticJsonDocument<200> response;
      response["status"] = "error";
      response["message"] = "Failed to connect to Wi-Fi. Please check credentials and try again.";

      String responseString;
      serializeJson(response, responseString);
      server.send(500, "application/json", responseString);

      Serial.println("↺ Restarting access point for retry...");
      delay(2000);

      WiFi.mode(WIFI_AP);
      WiFi.softAP("FLOWERS-SETUP", "12345678");

      Serial.print("(ᯤ) AP restarted at IP: ");
      Serial.println(WiFi.softAPIP());
    }
  } else {
    server.send(405, "text/plain", "Use POST");
  }
}

void handleSetupRoot() {
  lastNetworkOperation = millis();

  String html = "<!DOCTYPE html><html><head><title>Plant Monitor Setup</title>";
  html += "<meta name='viewport' content='width=device-width, initial-scale=1'>";
  html += "<style>body{font-family:Arial;margin:20px;background:#f0f0f0;}";
  html += ".container{max-width:400px;margin:0 auto;background:white;padding:20px;border-radius:10px;box-shadow:0 2px 10px rgba(0,0,0,0.1);}";
  html += "h1{color:#2c3e50;text-align:center;}";
  html += "input{width:100%;padding:10px;margin:10px 0;border:1px solid #ddd;border-radius:5px;box-sizing:border-box;}";
  html += "button{width:100%;padding:12px;background:#3498db;color:white;border:none;border-radius:5px;cursor:pointer;font-size:16px;}";
  html += "button:hover{background:#2980b9;}";
  html += ".status{margin-top:10px;padding:10px;border-radius:5px;display:none;}";
  html += ".success{background:#d4edda;color:#155724;border:1px solid #c3e6cb;}";
  html += ".error{background:#f8d7da;color:#721c24;border:1px solid #f5c6cb;}";
  html += "</style></head><body>";
  html += "<div class='container'>";
  html += "<h1>🌱 Plant Monitor Setup</h1>";
  html += "<p>Connect your plant monitoring system to WiFi:</p>";
  html += "<form id='wifiForm'>";
  html += "<input type='text' id='ssid' placeholder='WiFi Network Name (SSID)' required>";
  html += "<input type='password' id='password' placeholder='WiFi Password' required>";
  html += "<button type='submit'>Connect to WiFi</button>";
  html += "</form>";
  html += "<div id='status' class='status'></div>";
  html += "</div>";
  html += "<script>";
  html += "document.getElementById('wifiForm').addEventListener('submit', function(e) {";
  html += "e.preventDefault();";
  html += "const ssid = document.getElementById('ssid').value;";
  html += "const password = document.getElementById('password').value;";
  html += "const statusDiv = document.getElementById('status');";
  html += "statusDiv.style.display = 'block';";
  html += "statusDiv.className = 'status';";
  html += "statusDiv.innerHTML = 'Connecting...';";
  html += "fetch('/wifi', {";
  html += "method: 'POST',";
  html += "headers: {'Content-Type': 'application/json'},";
  html += "body: JSON.stringify({ssid: ssid, password: password})";
  html += "}).then(response => response.json()).then(data => {";
  html += "if (data.status === 'success') {";
  html += "statusDiv.className = 'status success';";
  html += "statusDiv.innerHTML = 'Connected! IP: ' + data.ip + '<br>Switching to monitoring mode...';";
  html += "} else {";
  html += "statusDiv.className = 'status error';";
  html += "statusDiv.innerHTML = 'Error: ' + data.message;";
  html += "}";
  html += "}).catch(error => {";
  html += "statusDiv.className = 'status error';";
  html += "statusDiv.innerHTML = 'Connection failed. Please try again.';";
  html += "});";
  html += "});";
  html += "</script></body></html>";

  server.send(200, "text/html", html);
}

// used
void setupWiFiAccessPoint() {
  Serial.println("🔧 Starting WiFi Setup Mode...");
  WiFi.mode(WIFI_AP);
  WiFi.softAP("FLOWERS-SETUP", "12345678");
  Serial.print("(ᯤ) AP started at IP: ");
  Serial.println(WiFi.softAPIP());

  server.on("/", HTTP_GET, handleSetupRoot);
  server.on("/wifi", HTTP_POST, handleWifiConfig);
  server.begin();
  Serial.println("Setup server started");
}

bool tryStoredWiFiConnection() {
  preferences.begin("wifi", true);
  String ssid = preferences.getString("ssid", "");
  String password = preferences.getString("password", "");
  preferences.end();

  if (ssid.length() > 0) {
    Serial.println("ᯤ Attempting to connect with stored credentials...");
    Serial.print("SSID: ");
    Serial.println(ssid);

    WiFi.begin(ssid.c_str(), password.c_str());

    int attempts = 0;
    while (WiFi.status() != WL_CONNECTED && attempts++ < 30) {
      delay(500);
      Serial.print(".");
    }

    if (WiFi.status() == WL_CONNECTED) {
      Serial.println("\n✓ Connected to stored WiFi!");
      Serial.print("IP address: ");
      Serial.println(WiFi.localIP());
      return true;
    } else {
      Serial.println("\n𓏵 Failed to connect with stored credentials.");
      preferences.begin("wifi", false);
      preferences.remove("ssid");
      preferences.remove("password");
      preferences.end();
      WiFi.disconnect();
    }
  }
  return false;
}

// used
void switchToMonitoringMode() {
  Serial.println("⇆ Switching to monitoring mode...");
  Serial.println();
  server.stop();
  WiFi.softAPdisconnect(true);
  currentState = MONITORING_MODE;

  // Log I2C sensor status
  if (ENABLE_I2C_SENSORS) {
    Serial.println("❄ I2C sensors enabled - using simple delay separation");
  } else {
    Serial.println("⊘ I2C sensors disabled for safety");
  }

  initializeChamberStates();
  cycleStartTime = millis();

  setupMonitoringServer();
  Serial.println("✓ Monitoring mode activated!");
  Serial.print("Monitor at: http://");
  Serial.println(WiFi.localIP());
}

void initializeI2CRobust() {
  Serial.println("⛀ Robust I2C initialization for light sensors...");

  // Completely reset I2C bus
  Wire.end();
  delay(500);

  // Initialize with conservative settings
  Wire.begin(SDA_PIN, SCL_PIN);
  Wire.setClock(50000);   // Slower clock for stability (50kHz instead of 100kHz)
  Wire.setTimeout(1000);  // 1 second timeout

  delay(200);
  yield();

  // Test PCA9547D multiplexer first
  Serial.println("Testing PCA9547D multiplexer...");
  Wire.beginTransmission(PCA9547D_ADDR);
  byte error = Wire.endTransmission();

  if (error == 0) {
    Serial.printf("✓ PCA9547D confirmed at address 0x%02X\n", PCA9547D_ADDR);

    // Initialize VEML7700 sensors one by one with error checking
    bool allSensorsOK = true;
    for (int i = 0; i < VEML7700_COUNT; i++) {
      int channel = VEML7700_CHANNEL_START + i;
      if (initVEML7700Robust(channel, i)) {
        Serial.printf("✓ VEML7700 sensor %d initialized on channel %d\n", i + 1, channel);
      } else {
        Serial.printf("✗ VEML7700 sensor %d failed on channel %d\n", i + 1, channel);
        allSensorsOK = false;
      }
      delay(300);  // Longer delay between sensor inits
      yield();
    }

    if (allSensorsOK) {
      i2cBusOK = true;
      Serial.println("✓ All VEML7700 light sensors initialized successfully!");
    } else {
      Serial.println("⚠️ Some VEML7700 sensors failed - will retry individually");
      i2cBusOK = true;  // Still allow partial operation
    }

  } else {
    Serial.printf("✗ PCA9547D communication failed (error: %d)\n", error);
    i2cBusOK = false;
    ENABLE_I2C_SENSORS = false;
  }
}

// ========== Simple Delay-Based I2C Functions ==========
void initializeI2CSafe() {
  Serial.println("⚒ Robust I2C initialization for light sensors...");

  Wire.end();
  delay(500);

  Wire.begin(SDA_PIN, SCL_PIN);
  Wire.setClock(50000);  // Slower clock for stability
  Wire.setTimeout(1000);

  delay(200);
  yield();

  Serial.println("Testing PCA9547D multiplexer...");
  Wire.beginTransmission(PCA9547D_ADDR);
  byte error = Wire.endTransmission();

  if (error == 0) {
    Serial.printf("\t✓ PCA9547D confirmed at address 0x%02X\n", PCA9547D_ADDR);

    bool allSensorsOK = true;
    for (int i = 0; i < VEML7700_COUNT; i++) {
      int channel = VEML7700_CHANNEL_START + i;
      if (initVEML7700Robust(channel, i)) {
        Serial.printf("\t✓ VEML7700 sensor %d initialized on channel %d\n", i + 1, channel);
      } else {
        Serial.printf("\t✗ VEML7700 sensor %d failed on channel %d\n", i + 1, channel);
        allSensorsOK = false;
      }
      delay(300);
      yield();
    }

    if (allSensorsOK) {
      i2cBusOK = true;
      Serial.println("✓ All VEML7700 light sensors initialized successfully!");
    } else {
      Serial.println("⚠️ Some VEML7700 sensors failed - will retry individually");
      i2cBusOK = true;
    }

  } else {
    Serial.printf("✗ PCA9547D communication failed (error: %d)\n", error);
    i2cBusOK = false;
    ENABLE_I2C_SENSORS = false;
  }
}

bool selectChannelRobust(int channel) {
  if (channel < 0 || channel > 7) return false;

  const int MAX_ATTEMPTS = 3;
  byte channelSelect = 0x08 | channel;

  for (int attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
    Wire.beginTransmission(PCA9547D_ADDR);
    Wire.write(channelSelect);
    byte error = Wire.endTransmission();

    if (error == 0) {
      delay(50);
      return true;
    }

    if (attempt < MAX_ATTEMPTS) {
      delay(100);
      yield();
    }
  }

  return false;
}


// Simple channel selection (same as test code)
bool selectChannelSimple(int channel) {
  if (channel < 0 || channel > 7) {
    Serial.printf("Invalid channel %d! Must be 0-7\n", channel);
    return false;
  }

  byte channelSelect = 0x08 | channel;
  Wire.beginTransmission(PCA9547D_ADDR);
  Wire.write(channelSelect);
  byte error = Wire.endTransmission();

  return (error == 0);
}

bool initVEML7700Robust(int channel, int sensor_index) {
  const int MAX_INIT_ATTEMPTS = 3;

  for (int attempt = 1; attempt <= MAX_INIT_ATTEMPTS; attempt++) {
    Serial.printf("VEML7700 #%d init attempt %d...\n", sensor_index + 1, attempt);

    if (!selectChannelRobust(channel)) {
      Serial.printf("Failed to select channel %d on attempt %d\n", channel, attempt);
      delay(200);
      continue;
    }

    if (veml_sensors[sensor_index].begin()) {
      veml_sensors[sensor_index].setGain(VEML7700_GAIN_1_8);
      veml_sensors[sensor_index].setIntegrationTime(VEML7700_IT_200MS);

      delay(300);

      float testLux = veml_sensors[sensor_index].readLux();
      if (!isnan(testLux) && testLux >= 0 && testLux < 120000) {
        Serial.printf("\t✓ VEML7700 #%d working (test read: %.1f lux)\n", sensor_index + 1, testLux);
        return true;
      }
    }

    if (attempt < MAX_INIT_ATTEMPTS) {
      delay(500);
      yield();
    }
  }

  return false;
}

bool initVEML7700Simple(int channel, int sensor_index) {
  // Select channel for VEML7700 (same as test code)
  if (!selectChannelSimple(channel)) {
    Serial.printf("Failed to select VEML7700 channel %d\n", channel);
    return false;
  }

  // Initialize the VEML7700 sensor using Adafruit library (same as test code)
  if (!veml_sensors[sensor_index].begin()) {
    Serial.printf("VEML7700 #%d not found on channel %d\n", sensor_index + 1, channel);
    return false;
  }

  // Configure sensor settings (same as test code)
  veml_sensors[sensor_index].setGain(VEML7700_GAIN_1);
  veml_sensors[sensor_index].setIntegrationTime(VEML7700_IT_100MS);

  delay(100);  // Same wait as test code
  return true;
}

void disableI2CEmergency() {
  Serial.println("🚨 EMERGENCY I2C DISABLE");

  i2cBusOK = false;
  ENABLE_I2C_SENSORS = false;
  i2cErrorCount = MAX_I2C_ERRORS;

  try {
    Wire.end();
    delay(100);
  } catch (...) {
    Serial.println("✘ Could not safely end I2C");
  }

  Serial.println("🛡️ System will continue with moisture sensors only");
}

// used
void feedWatchdogForce() {
  unsigned long now = millis();
  lastWatchdogTime = now;
  yield();
  delay(1);
}

// Simple SHT4x reading (exact copy of working test code)
bool readSHT4xDataSimple(int channel) {
  // Select channel for SHT4x (same as test code)
  if (!selectChannelSimple(channel)) {
    Serial.printf("Failed to select SHT4x channel %d\n", channel);
    return false;
  }

  // Send measurement command (same as test code)
  Wire.beginTransmission(SHT4X_ADDR);
  Wire.write(SHT4X_CMD_MEASURE_HIGH_PRECISION);
  byte error = Wire.endTransmission();

  if (error != 0) {
    Serial.printf("Failed to send measurement command (error: %d)\n", error);
    return false;
  }

  delay(10);  // Same delay as test code

  // Read 6 bytes of data (same as test code)
  Wire.requestFrom(SHT4X_ADDR, 6);

  if (Wire.available() < 6) {
    Serial.println("Failed to read SHT4x data");
    return false;
  }

  byte data[6];
  for (int i = 0; i < 6; i++) {
    data[i] = Wire.read();
  }

  // Convert raw data to temperature and humidity (same as test code)
  uint16_t temp_raw = (data[0] << 8) | data[1];
  uint16_t hum_raw = (data[3] << 8) | data[4];

  float temperature = -45.0 + 175.0 * temp_raw / 65535.0;
  float humidity = -6.0 + 125.0 * hum_raw / 65535.0;

  // Clamp humidity to valid range (same as test code)
  if (humidity > 100.0) humidity = 100.0;
  if (humidity < 0.0) humidity = 0.0;

  lastTemp[channel] = temperature;
  lastHumidity[channel] = humidity;
  lastTempStatus[channel] = (temperature > 25) ? "warm" : "normal";
  lastHumidityStatus[channel] = (humidity > 60) ? "humid" : "normal";

  return true;
}

// Simple VEML reading (exact copy of working test code)
float readVEML7700DataSimple(int channel, int sensor_index) {
  // Select channel for VEML7700 (same as test code)
  if (!selectChannelSimple(channel)) {
    Serial.printf("Failed to select VEML7700 channel %d\n", channel);
    return -1.0;
  }

  // Read data using Adafruit library (same as test code)
  float lux = veml_sensors[sensor_index].readLux();

  // Basic sanity check
  if (lux < 0 || lux > 120000 || isnan(lux)) {
    return -1.0;
  }

  return lux;
}


float readVEML7700Robust(int channel, int sensor_index) {
  const int MAX_READ_ATTEMPTS = 3;

  for (int attempt = 1; attempt <= MAX_READ_ATTEMPTS; attempt++) {
    if (!selectChannelRobust(channel)) {
      continue;
    }

    try {
      float lux = veml_sensors[sensor_index].readLux();

      if (!isnan(lux) && lux >= 0 && lux <= 120000) {
        return lux;
      }
    } catch (...) {
      Serial.printf("Exception reading VEML7700 #%d\n", sensor_index + 1);
    }

    if (attempt < MAX_READ_ATTEMPTS) {
      delay(100);
      yield();
    }
  }

  return -1.0;
}

void applyReactiveLightControl() {
  Serial.println("💡 Applying REACTIVE light control...");

  lastNetworkOperation = millis();

  for (int i = 0; i < 3; i++) {
    float currentLux = lastLux[i];
    int reactiveBrightness = calculateReactiveBrightness(currentLux);

    setShellyChannelSafe(LIGHT_CHANNELS[i], true, reactiveBrightness);
    delay(200);

    Serial.printf("💡 Sensor %d: %.1f lux → Ch%d = %d%%\n",
                  i + 1, currentLux, LIGHT_CHANNELS[i], reactiveBrightness);
  }

  setShellyChannelSafe(1, true, 30);
  Serial.println("✓ Reactive control applied!");
}

bool readSHT4xDataRobust(int channel) {
  if (!selectChannelRobust(channel)) {
    return false;
  }

  // Send measurement command
  Wire.beginTransmission(SHT4X_ADDR);
  Wire.write(SHT4X_CMD_MEASURE_HIGH_PRECISION);
  byte error = Wire.endTransmission();

  if (error != 0) {
    Serial.printf("SHT4x command failed (error: %d)\n", error);
    return false;
  }

  delay(15);  // Slightly longer delay for high precision

  // Read data
  Wire.requestFrom(SHT4X_ADDR, 6);
  if (Wire.available() < 6) {
    Serial.println("SHT4x data unavailable");
    return false;
  }

  byte data[6];
  for (int i = 0; i < 6; i++) {
    data[i] = Wire.read();
  }

  // Convert to temperature and humidity
  uint16_t temp_raw = (data[0] << 8) | data[1];
  uint16_t hum_raw = (data[3] << 8) | data[4];

  float temperature = -45.0 + 175.0 * temp_raw / 65535.0;
  float humidity = -6.0 + 125.0 * hum_raw / 65535.0;

  // Clamp humidity
  if (humidity > 100.0) humidity = 100.0;
  if (humidity < 0.0) humidity = 0.0;

  // Store results
  lastTemp[channel] = temperature;
  lastHumidity[channel] = humidity;
  updateTemperatureStatus(channel, temperature, lastTempStatus[channel]);
  updateHumidityStatus(channel, humidity, lastHumidityStatus[channel]);

  return true;
}

int calculateReactiveBrightness(float currentLux) {
  if (currentLux < 50) {
    return 100;  // Very dark → Max brightness
  } else if (currentLux < 100) {
    return 90;
  } else if (currentLux < 150) {
    return 70;  // Dark → High brightness
  } else if (currentLux < 300) {
    return 50;  // Moderate → Medium brightness
  } else if (currentLux < 500) {
    return 30;  // Bright → Low brightness
  } else {
    return 15;  // Very bright → Min brightness
  }
}

void processEnvironmentalSensorsSafe() {
  static unsigned long lastEnvironmentalCycle = 0;
  unsigned long now = millis();

  if (!ENABLE_I2C_SENSORS) {
    static unsigned long lastI2CDisabledMessage = 0;
    if (now - lastI2CDisabledMessage > 10000) {
      lastI2CDisabledMessage = now;
      if (wateringInProgress) {
        Serial.println("ℹ️ I2C sensors temporarily disabled during watering for power stability");
      } else {
        Serial.println("ℹ️ I2C sensors disabled - change ENABLE_I2C_SENSORS to true to enable");
      }
    }
    return;
  }

  // ===== SKIP VEML7700 SENSORS AFTER WATERING TO PREVENT CRASHES =====
  if ((now - lastWateringEndTime) < VEML7700_SKIP_AFTER_WATERING) {
    unsigned long remainingSkip = VEML7700_SKIP_AFTER_WATERING - (now - lastWateringEndTime);
    Serial.printf("⏸ Skipping light sensors for %lu more seconds after watering (crash prevention)\n", remainingSkip / 1000);

    // Still read temperature/humidity sensors since they work fine
    if (now - lastEnvironmentalCycle >= ENVIRONMENTAL_INTERVAL) {
      lastEnvironmentalCycle = now;

      Serial.println("☼ᨒ Reading temperature/humidity only (skipping light sensors)...");

      for (int channel = SHT4X_CHANNEL_START; channel <= SHT4X_CHANNEL_END; channel++) {
        esp_task_wdt_reset();
        if (readSHT4xDataSimple(channel)) {
          Serial.printf("SHT4x #%d: %.2f°C, %.2f%% RH\n",
                        channel + 1, lastTemp[channel], lastHumidity[channel]);
        }
        delay(200);
        yield();
      }
    }
    return;
  }

  // Enhanced delay after any network operation
  unsigned long delayNeeded = max(I2C_DELAY_AFTER_NETWORK, 1000UL);
  if ((now - lastNetworkOperation) < delayNeeded) {
    Serial.printf("⏸ Waiting %lu ms after network operation for I2C safety\n",
                  delayNeeded - (now - lastNetworkOperation));
    return;
  }

  if (now - lastEnvironmentalCycle >= ENVIRONMENTAL_INTERVAL) {
    lastEnvironmentalCycle = now;
    esp_task_wdt_reset();

    Serial.println();
    Serial.println("🀢 Reading environmental sensors (enhanced protection)...");

    if (!I2C_INIT_ATTEMPTED) {
      Serial.println("⚒ First-time I2C initialization...");
      esp_task_wdt_reset();
      initializeI2CSafe();
      I2C_INIT_ATTEMPTED = true;
      delay(1000);
      esp_task_wdt_reset();
      return;
    }

    if (!i2cBusOK) {
      Serial.println("✘ I2C not initialized properly");
      return;
    }

    try {
      bool anySuccess = false;

      // Read SHT4x sensors (these work fine after watering)
      Serial.println("-------------- SHT4x Temperature & Humidity Sensors --------------");
      for (int channel = SHT4X_CHANNEL_START; channel <= SHT4X_CHANNEL_END; channel++) {
        esp_task_wdt_reset();

        Serial.printf("\tSHT4x Sensor #%d (Channel %d):\n", channel + 1, channel);
        if (readSHT4xDataSimple(channel)) {
          anySuccess = true;
          lastSuccessfulI2CRead = millis();
          Serial.printf("  Temperature: %.2f°C\n", lastTemp[channel]);
          Serial.printf("  Humidity: %.2f%% RH\n", lastHumidity[channel]);
        } else {
          Serial.println("  Failed to read SHT4x");
        }

        delay(200);
        yield();
        esp_task_wdt_reset();
      }

      // ===== CAREFUL VEML7700 HANDLING AFTER WATERING =====
      Serial.println("-------------- VEML7700 Light Sensors (CRASH-PROTECTED) --------------");

      // Reinitialize VEML7700 sensors if needed
      if (veml7700SensorsNeedReinit) {
        if (!reinitializeVEML7700AfterWatering()) {
          Serial.println("✘ VEML7700 reinitialization failed - skipping light sensors this cycle");
          return;  // Skip light sensors this cycle
        }
      }

      bool lightSensorSuccess = false;

      for (int i = 0; i < VEML7700_COUNT; i++) {
        esp_task_wdt_reset();

        int channel = VEML7700_CHANNEL_START + i;

        Serial.printf("⚯  Reading VEML7700 #%d (Channel %d) with crash protection...\n", i + 1, channel);

        try {
          // Extra careful reading with immediate error handling
          if (!selectChannelSimple(channel)) {
            Serial.printf("✘ Failed to select channel %d\n", channel);
            continue;
          }

          delay(100);  // Extra delay for stability
          esp_task_wdt_reset();

          float lux = veml_sensors[i].readLux();

          // Immediate validation
          if (isnan(lux) || lux < 0 || lux > 120000) {
            Serial.printf("✘ VEML7700 #%d: Invalid reading (%.1f)\n", i + 1, lux);

            // Mark for reinitialization on next cycle
            veml7700SensorsNeedReinit = true;
            continue;
          }

          // Success!
          lastLux[i] = lux;
          updateLightStatus(i, lux, lastLightStatus[i]);
          lightSensorSuccess = true;
          Serial.printf("✓ VEML7700 #%d: %.1f lux (%s)\n",
                        i + 1, lux, lastLightStatus[i].c_str());

        } catch (...) {
          Serial.printf("✘ Exception reading VEML7700 #%d - marking for reinitialization\n", i + 1);
          veml7700SensorsNeedReinit = true;
        }

        delay(400);  // Longer delay between light sensors
        yield();
        esp_task_wdt_reset();
      }

      if (lightSensorSuccess) {
        lastSuccessfulI2CRead = millis();
        Serial.println("✓ Light sensors read successfully!");

        // Apply reactive light control (only if not watering)
        if (!wateringInProgress) {
          esp_task_wdt_reset();
          applySmartReactiveLightControl();
          esp_task_wdt_reset();
        }
      } else {
        Serial.println("⚠️ All light sensors failed - will reinitialize next cycle");
        veml7700SensorsNeedReinit = true;
      }

      if (anySuccess) {
        Serial.println("✓ Environmental sensor read completed");
      } else {
        i2cErrorCount++;
        Serial.printf("✘ All sensors failed (error count: %d)\n", i2cErrorCount);

        if (i2cErrorCount >= MAX_I2C_ERRORS) {
          Serial.println("🚫 Too many I2C failures - disabling I2C");
          disableI2CEmergency();
        }
      }

    } catch (...) {
      Serial.println("✘ Exception in environmental sensors - disabling I2C");
      disableI2CEmergency();
    }
  }
}

void applySmartReactiveLightControl() {
  Serial.println("✧ Applying SMART reactive light control (chamber-specific)...");

  lastNetworkOperation = millis();

  for (int i = 0; i < 3; i++) {
    float currentLux = lastLux[i];
    int smartBrightness;

    if (cubbiesData[i].hasData) {
      // Use chamber-specific reactive control based on cubby targets
      smartBrightness = calculateSmartReactiveBrightness(currentLux, i);
      Serial.printf("✩ Chamber %d: %.1f lux (target: %.1f) → Ch%d = %d%% (smart)\n",
                    i + 1, currentLux, targetLux[i], LIGHT_CHANNELS[i], smartBrightness);
    } else {
      // Fall back to generic reactive control for unassigned chambers
      smartBrightness = calculateReactiveBrightness(currentLux);
      Serial.printf("𖥔 Chamber %d: %.1f lux → Ch%d = %d%% (generic)\n",
                    i + 1, currentLux, LIGHT_CHANNELS[i], smartBrightness);
    }

    setShellyChannelSafe(LIGHT_CHANNELS[i], true, smartBrightness);
    delay(200);
  }

  setShellyChannelSafe(1, true, 30);
  Serial.println("✓ Smart reactive control applied!");
}

// NEW function: Calculate brightness based on chamber's specific target
int calculateSmartReactiveBrightness(float currentLux, int cubbyIndex) {
  if (!cubbiesData[cubbyIndex].hasData) {
    return calculateReactiveBrightness(currentLux);  // Fall back to generic
  }

  float targetLuxValue = targetLux[cubbyIndex];
  // float luxDifference = targetLuxValue - currentLux;
  float luxRatio = currentLux / targetLuxValue;

  if (luxRatio < 0.1) {
    Serial.printf("🔦 EXTREME: Chamber %d very dark (%.1f/%.1f = %.1f%%) → 100%% brightness\n",
                  cubbyIndex + 1, currentLux, targetLuxValue, luxRatio * 100);
    return 100;  // MAX BRIGHTNESS for covered sensors
  }
  if (luxRatio > 5.0) {
    Serial.printf("🔆 EXTREME: Chamber %d very bright (%.1f/%.1f = %.1f%%) → 0%% brightness\n",
                  cubbyIndex + 1, currentLux, targetLuxValue, luxRatio * 100);
    return 0;  // LIGHTS OFF for flashlight interference
  }
  if (luxRatio < 0.5) {
    int aggressiveBrightness = 80 + (20 * (0.5 - luxRatio) / 0.4);  // 80-100%
    Serial.printf("🔦 DARK: Chamber %d (%.1f%% of target) → %d%% brightness\n",
                  cubbyIndex + 1, luxRatio * 100, aggressiveBrightness);
    return min(100, aggressiveBrightness);
  }
  if (luxRatio > 2.0) {
    int aggressiveBrightness = 20 - (15 * (luxRatio - 2.0) / 3.0);  // 5-20%
    Serial.printf("🔆 BRIGHT: Chamber %d (%.1f%% of target) → %d%% brightness\n",
                  cubbyIndex + 1, luxRatio * 100, aggressiveBrightness);
    return max(0, aggressiveBrightness);
  }
  if (luxRatio < 0.8) {
    int moderateBrightness = targetBrightness[cubbyIndex] + (30 * (0.8 - luxRatio) / 0.3);
    Serial.printf("✮ Dim: Chamber %d (%.1f%% of target) → %d%% brightness\n",
                  cubbyIndex + 1, luxRatio * 100, moderateBrightness);
    return min(80, moderateBrightness);
  }

  // Somewhat bright (120-200% of target) - Decrease moderately
  if (luxRatio > 1.2) {
    int moderateBrightness = targetBrightness[cubbyIndex] - (25 * (luxRatio - 1.2) / 0.8);
    Serial.printf("✴ Bright: Chamber %d (%.1f%% of target) → %d%% brightness\n",
                  cubbyIndex + 1, luxRatio * 100, moderateBrightness);
    return max(20, moderateBrightness);
  }

  // OPTIMAL RANGE (80-120% of target) - Use target brightness
  Serial.printf("✓ OPTIMAL: Chamber %d (%.1f%% of target) → %d%% brightness (target)\n",
                cubbyIndex + 1, luxRatio * 100, targetBrightness[cubbyIndex]);
  return targetBrightness[cubbyIndex];
}

// ========== Cubbies Handler ==========
void handleCubbies() {
  lastNetworkOperation = millis();

  server.sendHeader("Access-Control-Allow-Origin", "*");
  server.sendHeader("Access-Control-Allow-Methods", "POST, GET, OPTIONS");
  server.sendHeader("Access-Control-Allow-Headers", "Content-Type");

  if (server.method() == HTTP_POST) {
    String body = server.arg("plain");
    Serial.println("📦 Received cubbies data: " + body);

    StaticJsonDocument<1024> doc;
    DeserializationError error = deserializeJson(doc, body);

    if (error) {
      Serial.println("✘ JSON parsing failed: " + String(error.c_str()));
      server.send(400, "application/json", "{\"status\":\"error\",\"message\":\"Invalid JSON format\"}");
      return;
    }

    bool validData = true;
    String errorMessage = "";
    int updatedCubbies = 0;

    for (int i = 0; i < 3; i++) {
      String cubbyKey = "cubby" + String(i + 1);

      if (doc.containsKey(cubbyKey)) {
        JsonObject cubby = doc[cubbyKey];

        if (cubby.containsKey("lightLower") && cubby.containsKey("lightUpper") && cubby.containsKey("soilLower") && cubby.containsKey("soilUpper") && cubby.containsKey("humidityLower") && cubby.containsKey("humidityUpper") && cubby.containsKey("temperatureLower") && cubby.containsKey("temperatureUpper")) {

          cubbiesData[i].lightLower = cubby["lightLower"];
          cubbiesData[i].lightUpper = cubby["lightUpper"];
          cubbiesData[i].soilLower = cubby["soilLower"];
          cubbiesData[i].soilUpper = cubby["soilUpper"];
          cubbiesData[i].humidityLower = cubby["humidityLower"];
          cubbiesData[i].humidityUpper = cubby["humidityUpper"];
          cubbiesData[i].temperatureLower = cubby["temperatureLower"];
          cubbiesData[i].temperatureUpper = cubby["temperatureUpper"];
          cubbiesData[i].hasData = true;
          cubbiesData[i].lastUpdated = millis();

          // ==== NEW: Calculate target lux and brightness from user's light range ====
          targetLux[i] = (cubbiesData[i].lightLower + cubbiesData[i].lightUpper) / 2.0;
          targetBrightness[i] = calculateBrightnessFromLux(targetLux[i]);

          Serial.printf("✓ Updated %s: lightRange=%d-%d, targetLux=%.1f, brightness=%d%%\n",
                        cubbyKey.c_str(),
                        cubbiesData[i].lightLower, cubbiesData[i].lightUpper,
                        targetLux[i], targetBrightness[i]);
          Serial.printf("   soilRange=%d-%d, humidityRange=%d-%d%%, tempRange=%d-%d°C\n",
                        cubbiesData[i].soilLower, cubbiesData[i].soilUpper,
                        cubbiesData[i].humidityLower, cubbiesData[i].humidityUpper,
                        cubbiesData[i].temperatureLower, cubbiesData[i].temperatureUpper);

          updatedCubbies++;
        } else {
          Serial.println("⚠️ " + cubbyKey + " missing required sensor fields");
          validData = false;
          errorMessage += cubbyKey + " missing sensor data; ";
        }
      }
    }

    if (validData && updatedCubbies > 0) {
      // Apply new lighting immediately based on user's plant assignments
      Serial.println("⊹ Applying lighting changes based on new plant assignments...");
      updateLuxBasedLighting();

      StaticJsonDocument<300> response;
      response["status"] = "success";
      response["message"] = "Cubbies data received successfully - lighting updated";
      response["updated_cubbies"] = updatedCubbies;
      response["lighting_applied"] = true;

      String responseString;
      serializeJson(response, responseString);
      server.send(200, "application/json", responseString);
    } else {
      StaticJsonDocument<300> response;
      response["status"] = "error";
      response["message"] = errorMessage.length() > 0 ? errorMessage : "No valid cubby data found";

      String responseString;
      serializeJson(response, responseString);
      server.send(400, "application/json", responseString);
    }

  } else if (server.method() == HTTP_GET) {
    server.sendHeader("Access-Control-Allow-Origin", "*");

    StaticJsonDocument<1024> doc;

    for (int i = 0; i < 3; i++) {
      String cubbyKey = "cubby" + String(i + 1);

      doc[cubbyKey]["lightLower"] = cubbiesData[i].hasData ? cubbiesData[i].lightLower : 0;
      doc[cubbyKey]["lightUpper"] = cubbiesData[i].hasData ? cubbiesData[i].lightUpper : 0;
      doc[cubbyKey]["soilLower"] = cubbiesData[i].hasData ? cubbiesData[i].soilLower : 0;
      doc[cubbyKey]["soilUpper"] = cubbiesData[i].hasData ? cubbiesData[i].soilUpper : 0;
      doc[cubbyKey]["humidityLower"] = cubbiesData[i].hasData ? cubbiesData[i].humidityLower : 0;
      doc[cubbyKey]["humidityUpper"] = cubbiesData[i].hasData ? cubbiesData[i].humidityUpper : 0;
      doc[cubbyKey]["temperatureLower"] = cubbiesData[i].hasData ? cubbiesData[i].temperatureLower : 0;
      doc[cubbyKey]["temperatureUpper"] = cubbiesData[i].hasData ? cubbiesData[i].temperatureUpper : 0;
      doc[cubbyKey]["has_data"] = cubbiesData[i].hasData;
      doc[cubbyKey]["targetLux"] = targetLux[i];                // NEW: Include target lux
      doc[cubbyKey]["targetBrightness"] = targetBrightness[i];  // NEW: Include target brightness

      if (cubbiesData[i].hasData) {
        doc[cubbyKey]["last_updated"] = cubbiesData[i].lastUpdated;
      }
    }

    String json;
    serializeJson(doc, json);
    server.send(200, "application/json", json);

  } else if (server.method() == HTTP_OPTIONS) {
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.sendHeader("Access-Control-Allow-Methods", "POST, GET, OPTIONS");
    server.sendHeader("Access-Control-Allow-Headers", "Content-Type");
    server.send(200, "text/plain", "");
  } else {
    server.send(405, "text/plain", "Method not allowed");
  }
}

void updateLuxBasedLighting() {
  if (!luxBasedControlEnabled) return;

  // Check if we have any user data before setting lights
  bool hasAnyUserData = false;
  for (int i = 0; i < 3; i++) {
    if (cubbiesData[i].hasData) {
      hasAnyUserData = true;
      break;
    }
  }

  if (!hasAnyUserData) {
    Serial.println("⟡ No user cubby data available - lights remain off until plants are assigned");
    // Turn all lights off until user assigns plants
    setAllShelly(false, 0);
    return;
  }

  Serial.println("☀︎ Updating lux-based lighting from user cubby assignments...");

  // Mark network operation
  lastNetworkOperation = millis();

  // Control each channel based on its cubby's target brightness
  // Using the mapping: Sensor 1->Channel 2, Sensor 2->Channel 0, Sensor 3->Channel 3
  setShellyChannelSafe(LIGHT_CHANNELS[0], true, targetBrightness[0]);  // Cubby 1 → Channel 2
  delay(200);
  setShellyChannelSafe(LIGHT_CHANNELS[1], true, targetBrightness[1]);  // Cubby 2 → Channel 0
  delay(200);
  setShellyChannelSafe(LIGHT_CHANNELS[2], true, targetBrightness[2]);  // Cubby 3 → Channel 3
  delay(200);

  // Channel 1 (not mapped to any cubby) - set to minimum
  setShellyChannelSafe(1, true, 10);

  Serial.printf("☀ Applied user lighting: Ch%d=%d%% (%.1flux), Ch%d=%d%% (%.1flux), Ch%d=%d%% (%.1flux), Ch1=10%%\n",
                LIGHT_CHANNELS[0], targetBrightness[0], targetLux[0],
                LIGHT_CHANNELS[1], targetBrightness[1], targetLux[1],
                LIGHT_CHANNELS[2], targetBrightness[2], targetLux[2]);
}

int calculateBrightnessFromLux(float lux) {
  if (lux <= 230) {
    return 20;  // 0-230 lux → 20% brightness
  } else if (lux <= 370) {
    return 50;  // 230-370 lux → 50% brightness
  } else {
    return 90;  // 370+ lux → 90% brightness
  }
}

// ========== Monitoring Server Setup ==========
void setupMonitoringServer() {
  server.on("/", HTTP_GET, handleRoot);
  server.on("/sensors", HTTP_GET, handleData);
  server.on("/moisture", HTTP_GET, handleMoisture);
  server.on("/cubbies", HTTP_POST, handleCubbies);
  server.on("/cubbies", HTTP_GET, handleCubbies);
  server.on("/cubbies", HTTP_OPTIONS, handleCubbies);
  server.on("/lights", HTTP_GET, handleLightControl);
  server.on("/reset", HTTP_GET, handleReset);
  server.begin();
  Serial.println("HTTP monitoring server started");
  Serial.print("⿻ Cubbies endpoint available at: http://");
  Serial.print(WiFi.localIP());
  Serial.println("/cubbies");
  Serial.print("✦ Light control available at: http://");
  Serial.print(WiFi.localIP());
  Serial.println();
  Serial.println("/lights?action=toggle");
}

void handleReset() {
  lastNetworkOperation = millis();

  Serial.println("🔄 Resetting WiFi settings...");
  preferences.begin("wifi", false);
  preferences.clear();
  preferences.end();
  server.send(200, "text/html", "<h2>WiFi settings cleared. Restarting...</h2>");
  delay(2000);
  ESP.restart();
}

void handleMoisture() {
  lastNetworkOperation = millis();

  StaticJsonDocument<200> doc;
  doc["value1"] = lastMoistureValue1;
  doc["value2"] = lastMoistureValue2;
  doc["value3"] = lastMoistureValue3;

  String json;
  server.sendHeader("Access-Control-Allow-Origin", "*");
  serializeJson(doc, json);
  server.send(200, "application/json", json);
}

void handleLightControl() {
  lastNetworkOperation = millis();

  String action = server.arg("action");

  if (action == "toggle") {
    luxBasedControlEnabled = !luxBasedControlEnabled;
    if (!luxBasedControlEnabled) {
      // Turn all lights off when disabling
      setAllShelly(false, 0);
    } else {
      // Apply lux-based control when enabling
      updateLuxBasedLighting();
    }
    Serial.printf("𖥔 Lux-based lighting %s\n", luxBasedControlEnabled ? "ENABLED" : "DISABLED");
  } else if (action == "on") {
    luxBasedControlEnabled = true;
    updateLuxBasedLighting();
    Serial.println("✩ Lux-based lighting ENABLED");
  } else if (action == "off") {
    luxBasedControlEnabled = false;
    setAllShelly(false, 0);
    Serial.println("✴︎ Lux-based lighting DISABLED");
  }

  StaticJsonDocument<300> doc;
  doc["luxBasedControlEnabled"] = luxBasedControlEnabled;
  doc["targetLux1"] = targetLux[0];
  doc["targetLux2"] = targetLux[1];
  doc["targetLux3"] = targetLux[2];
  doc["targetBrightness1"] = targetBrightness[0];
  doc["targetBrightness2"] = targetBrightness[1];
  doc["targetBrightness3"] = targetBrightness[2];
  doc["action"] = action;

  String json;
  server.sendHeader("Access-Control-Allow-Origin", "*");
  serializeJson(doc, json);
  server.send(200, "application/json", json);
}


void handleRoot() {
  lastNetworkOperation = millis();

  String html = "<html><head><meta http-equiv='refresh' content='5'>";
  html += "<style>body{font-family:Arial;margin:20px;}";
  html += ".sensor{background:#f0f0f0;padding:15px;margin-bottom:10px;border-radius:5px;}";
  html += ".cubby{background:#e8f5e8;padding:15px;margin-bottom:10px;border-radius:5px;}";
  html += ".system{background:#e3f2fd;padding:15px;margin-bottom:10px;border-radius:5px;}";
  html += ".reset-btn{background:#e74c3c;color:white;padding:10px 20px;text-decoration:none;border-radius:5px;display:inline-block;margin-top:20px;}";
  html += ".status{font-weight:bold;}";
  html += ".safe{color:#27ae60;}";
  html += ".disabled{color:#e74c3c;}";
  html += ".active{color:#2980b9;}";
  html += "</style></head><body>";
  html += "<h1>🌱 Plant Monitor + Lux-Based Lighting System</h1>";

  // System status
  html += "<div class='system'><h2>⚙️ System Status</h2>";
  html += "<p>Free Memory: <span class='status'>" + String(ESP.getFreeHeap()) + " bytes</span></p>";
  html += "<p>Uptime: <span class='status'>" + String(millis() / 60000) + " minutes</span></p>";
  html += "<p>WiFi: <span class='status " + String(WiFi.status() == WL_CONNECTED ? "safe'>Connected" : "disabled'>Disconnected") + "</span></p>";
  html += "<p>I2C Sensors: <span class='status " + String(ENABLE_I2C_SENSORS ? (i2cBusOK ? "active'>Enabled & Working" : "disabled'>Enabled but Failed") : "disabled'>Disabled") + "</span></p>";
  html += "<p>Lux-Based Lighting: <span class='status " + String(luxBasedControlEnabled ? "active'>ENABLED" : "disabled'>DISABLED") + "</span></p>";
  html += "<p>Timing Method: <span class='status safe'>Simple Delay-Based</span></p>";
  html += "</div>";

  // Soil moisture
  html += "<div class='sensor'><h2>💧 Soil Moisture Control</h2>";
  html += "<p>Sensor 1 (Pin 35 → B Channel): <strong>" + String(lastMoistureValue1) + "</strong> (" + lastMoistureStatus1 + ")</p>";
  html += "<p>Sensor 2 (Pin 34 → G Channel): <strong>" + String(lastMoistureValue2) + "</strong> (" + lastMoistureStatus2 + ")</p>";
  html += "<p>Sensor 3 (Pin 32 → W Channel): <strong>" + String(lastMoistureValue3) + "</strong> (" + lastMoistureStatus3 + ")</p></div>";

  // Environmental data (only if I2C is enabled and working)
  if (ENABLE_I2C_SENSORS && i2cBusOK) {
    html += "<div class='sensor'><h2>𖤣 Environmental Sensors (Delay-Protected)</h2>";
    for (int i = 0; i < 3; i++) {
      html += "<h3>Sensor Group " + String(i + 1) + "</h3>";
      html += "<p>Temperature: " + String(lastTemp[i], 1) + "°C (" + lastTempStatus[i] + ")</p>";
      html += "<p>Humidity: " + String(lastHumidity[i], 1) + "% (" + lastHumidityStatus[i] + ")</p>";
      html += "<p>Target Light: " + String(targetLux[i], 1) + " lux → " + String(targetBrightness[i]) + "% brightness</p>";
    }
    html += "</div>";
  } else if (!ENABLE_I2C_SENSORS) {
    html += "<div class='sensor'><h2>𖤣 Environmental Sensors</h2>";
    html += "<p class='disabled'>Environmental sensors disabled</p>";
    html += "<p><small>To enable: Change ENABLE_I2C_SENSORS to true in code</small></p>";

    // Still show light targets
    html += "<h3>🔦 Light Targets</h3>";
    for (int i = 0; i < 3; i++) {
      html += "<p>Cubby " + String(i + 1) + ": " + String(targetLux[i], 1) + " lux → " + String(targetBrightness[i]) + "% brightness</p>";
    }
    html += "</div>";
  } else {
    html += "<div class='sensor'><h2>𖤣 Environmental Sensors</h2>";
    html += "<p class='disabled'>I2C sensors failed - running in safe mode</p></div>";
  }

  // Light Control Status
  html += "<div class='sensor'><h2>✧ Lux-Based Light Control System</h2>";
  html += "<p>Control Status: <span class='status " + String(luxBasedControlEnabled ? "active'>ENABLED" : "disabled'>DISABLED") + "</span></p>";

  // Check if we have any user data
  bool hasAnyUserData = false;
  for (int i = 0; i < 3; i++) {
    if (cubbiesData[i].hasData) {
      hasAnyUserData = true;
      break;
    }
  }

  if (!hasAnyUserData) {
    html += "<p class='disabled'>⚠️ Waiting for user to assign plants to cubbies</p>";
    html += "<p><small>Lights will remain off until plant assignments are received from the app</small></p>";
  } else {
    html += "<p>Brightness Mapping:</p>";
    html += "<ul>";
    html += "<li>0-230 lux → 20% brightness</li>";
    html += "<li>230-370 lux → 50% brightness</li>";
    html += "<li>370+ lux → 90% brightness</li>";
    html += "</ul>";
    html += "<p>Current User-Defined Targets:</p>";
    html += "<ul>";
    for (int i = 0; i < 3; i++) {
      if (cubbiesData[i].hasData) {
        html += "<li>Cubby " + String(i + 1) + " (Ch" + String(LIGHT_CHANNELS[i]) + "): " + String(targetLux[i], 1) + " lux → " + String(targetBrightness[i]) + "%</li>";
      } else {
        html += "<li>Cubby " + String(i + 1) + " (Ch" + String(LIGHT_CHANNELS[i]) + "): No assignment yet</li>";
      }
    }
    html += "</ul>";
  }
  html += "</div>";

  // Cubbies setpoints
  html += "<div class='cubby'><h2>📦 Cubbies Setpoints</h2>";
  for (int i = 0; i < 3; i++) {
    html += "<h3>Cubby " + String(i + 1) + "</h3>";
    if (cubbiesData[i].hasData) {
      html += "<p>Light Range: " + String(cubbiesData[i].lightLower) + " - " + String(cubbiesData[i].lightUpper) + " (Target: " + String(targetLux[i], 1) + " lux)</p>";
      html += "<p>Soil Range: " + String(cubbiesData[i].soilLower) + " - " + String(cubbiesData[i].soilUpper) + "</p>";
      html += "<p>Humidity Range: " + String(cubbiesData[i].humidityLower) + " - " + String(cubbiesData[i].humidityUpper) + "%</p>";
      html += "<p>Temperature Range: " + String(cubbiesData[i].temperatureLower) + " - " + String(cubbiesData[i].temperatureUpper) + "°C</p>";
      html += "<p>Last Updated: " + String((millis() - cubbiesData[i].lastUpdated) / 1000) + "s ago</p>";
    } else {
      html += "<p>No setpoints received - using defaults (Target: " + String(targetLux[i], 1) + " lux)</p>";
    }
  }
  html += "</div>";

  html += "<p>Auto-refresh every 5 seconds | System: <strong class='safe'>Delay-Based Protection + Lux-Based Lighting</strong></p>";
  html += "<a href='/lights?action=toggle' class='reset-btn' style='background:#3498db;margin-right:10px;'>Toggle Lux-Based Lighting</a>";
  html += "<a href='/reset' class='reset-btn'>Reset WiFi Settings</a>";
  html += "</body></html>";

  server.send(200, "text/html", html);
}

void handleData() {
  lastNetworkOperation = millis();

  StaticJsonDocument<2048> doc;

  // System status
  doc["system"]["freeMemory"] = ESP.getFreeHeap();
  doc["system"]["uptimeMinutes"] = millis() / 60000;
  doc["system"]["wifiStatus"] = WiFi.status() == WL_CONNECTED ? "Connected" : "Disconnected";
  doc["system"]["i2cEnabled"] = ENABLE_I2C_SENSORS;
  doc["system"]["i2cStatus"] = i2cBusOK ? "OK" : "DISABLED";
  doc["system"]["i2cErrors"] = i2cErrorCount;
  doc["system"]["luxBasedControlEnabled"] = luxBasedControlEnabled;  // Updated field name
  doc["system"]["timingMethod"] = "Delay-Based";

  // Soil moisture data
  doc["soil"]["sensor1"]["value"] = lastMoistureValue1;
  doc["soil"]["sensor1"]["status"] = lastMoistureStatus1;
  doc["soil"]["sensor2"]["value"] = lastMoistureValue2;
  doc["soil"]["sensor2"]["status"] = lastMoistureStatus2;
  doc["soil"]["sensor3"]["value"] = lastMoistureValue3;
  doc["soil"]["sensor3"]["status"] = lastMoistureStatus3;

  // Environmental data
  for (int i = 0; i < 3; i++) {
    if (ENABLE_I2C_SENSORS && i2cBusOK) {
      doc["environment"]["temperature" + String(i + 1)]["value"] = lastTemp[i];
      doc["environment"]["temperature" + String(i + 1)]["status"] = lastTempStatus[i];
      doc["environment"]["humidity" + String(i + 1)]["value"] = lastHumidity[i];
      doc["environment"]["humidity" + String(i + 1)]["status"] = lastHumidityStatus[i];
    }

    // ==== NEW: Return target lux instead of "disabled" ====
    doc["environment"]["light" + String(i + 1)]["value"] = lastLux[i];
    doc["environment"]["light" + String(i + 1)]["status"] = luxBasedControlEnabled ? "target" : "disabled";
    doc["environment"]["light" + String(i + 1)]["brightness"] = targetBrightness[i];
  }

  // Watering events
  for (int i = 0; i < 3; i++) {
    if (justWatered[i] && (millis() - lastWateringEventTime[i] < 5000)) {
      doc["watering"]["cubby" + String(i + 1)] = true;
      justWatered[i] = false;  // Reset after sending
    } else {
      doc["watering"]["cubby" + String(i + 1)] = false;
    }
  }

  // Cubbies setpoints
  for (int i = 0; i < 3; i++) {
    String cubbyKey = "cubby" + String(i + 1);
    doc[cubbyKey]["lightLower"] = cubbiesData[i].lightLower;
    doc[cubbyKey]["lightUpper"] = cubbiesData[i].lightUpper;
    doc[cubbyKey]["soilLower"] = cubbiesData[i].soilLower;
    doc[cubbyKey]["soilUpper"] = cubbiesData[i].soilUpper;
    doc[cubbyKey]["humidityLower"] = cubbiesData[i].humidityLower;
    doc[cubbyKey]["humidityUpper"] = cubbiesData[i].humidityUpper;
    doc[cubbyKey]["temperatureLower"] = cubbiesData[i].temperatureLower;
    doc[cubbyKey]["temperatureUpper"] = cubbiesData[i].temperatureUpper;
    doc[cubbyKey]["has_data"] = cubbiesData[i].hasData;
    doc[cubbyKey]["targetLux"] = targetLux[i];                // NEW: Include target lux
    doc[cubbyKey]["targetBrightness"] = targetBrightness[i];  // NEW: Include target brightness
  }

  String json;
  server.sendHeader("Access-Control-Allow-Origin", "*");
  serializeJson(doc, json);
  server.send(200, "application/json", json);
}

// used
// ========== System Health Functions ==========
void checkSystemHealth() {
  unsigned long now = millis();

  // Memory check
  if (now - lastMemoryCheck >= MEMORY_CHECK_INTERVAL) {
    lastMemoryCheck = now;

    size_t freeHeap = ESP.getFreeHeap();
    if (freeHeap < 10000) {  // Less than 10KB free
      Serial.printf("⚠️ LOW MEMORY WARNING: %u bytes free\n", freeHeap);
    }

    // Check WiFi connection
    if (WiFi.status() != WL_CONNECTED) {
      Serial.println("⚠️ WiFi disconnected - attempting reconnection");
    }
  }
}

// ========== Safe Moisture Control ==========
void processMoistureControlSafe() {
  static unsigned long lastMoistureCycle = 0;
  unsigned long now = millis();

  if (now - lastMoistureCycle >= MOISTURE_INTERVAL) {
    lastMoistureCycle = now;

    try {
      Serial.println("\n\n Reading moisture sensors...");

      lastMoistureValue1 = analogRead(AOUT_PIN);
      yield();

      lastMoistureValue2 = analogRead(AOUT_PIN2);
      yield();

      lastMoistureValue3 = readMoistureAverageSafe(AOUT_PIN3);
      yield();

      // Update status based on cubby setpoints
      updateMoistureStatus(0, lastMoistureValue1, lastMoistureStatus1);
      updateMoistureStatus(1, lastMoistureValue2, lastMoistureStatus2);
      updateMoistureStatus(2, lastMoistureValue3, lastMoistureStatus3);

      Serial.println("=== Moisture Readings ===");
      Serial.printf("\tSensor 1 (Pin 35 → B): %d (%s)\n", lastMoistureValue1, lastMoistureStatus1.c_str());
      Serial.printf("\tSensor 2 (Pin 34 → G): %d (%s)\n", lastMoistureValue2, lastMoistureStatus2.c_str());
      Serial.printf("\tSensor 3 (Pin 32 → W): %d (%s)\n", lastMoistureValue3, lastMoistureStatus3.c_str());

      // Control watering with error isolation
      controlWateringSafe(0, lastMoistureValue1, B_CHANNEL, &lastWateringTime_B);
      yield();

      controlWateringSafe(1, lastMoistureValue2, G_CHANNEL, &lastWateringTime_G);
      yield();

      controlWateringSafe(2, lastMoistureValue3, W_CHANNEL, &lastWateringTime_W);
      yield();

    } catch (...) {
      Serial.println("✘ Exception in moisture control - continuing");
    }
  }
}

int readMoistureAverageSafe(int pin) {
  const int SAFE_NUM_SAMPLES = 20;
  long sum = 0;
  int validSamples = 0;

  for (int i = 0; i < SAFE_NUM_SAMPLES; i++) {
    int reading = analogRead(pin);

    if (reading >= 0 && reading <= 4095) {
      sum += reading;
      validSamples++;
    }

    delay(2);

    if (i % 5 == 0) {
      yield();
    }
  }

  if (validSamples == 0) {
    Serial.printf("⚠️ No valid moisture readings from pin %d\n", pin);
    return 0;
  }

  return sum / validSamples;
}

void controlWateringSafe(int cubbyIndex, int moistureValue, int channel, unsigned long* lastWateringTime) {
  try {
    if (cubbiesData[cubbyIndex].hasData) {
      if (moistureValue >= cubbiesData[cubbyIndex].soilUpper) {
        Serial.printf("🚰 Cubby %d: Soil dry (>= %d), activating channel %d\n",
                      cubbyIndex + 1, cubbiesData[cubbyIndex].soilUpper, channel);
        if (shellyControlWateringChannelSafe(channel, true, lastWateringTime)) {
          justWatered[cubbyIndex] = true;
          lastWateringEventTime[cubbyIndex] = millis();
        }
      } else {
        Serial.printf("💧 Cubby %d: Soil adequate (<= %d), channel %d OFF\n",
                      cubbyIndex + 1, cubbiesData[cubbyIndex].soilUpper, channel);
        shellyControlWateringChannelSafe(channel, false, lastWateringTime);
      }
    } else {
      const int DEFAULT_DRY_THRESHOLD = 1800;
      if (moistureValue >= DEFAULT_DRY_THRESHOLD) {
        Serial.printf("☔︎︎ Default: Soil dry, activating channel %d\n", channel);
        if (shellyControlWateringChannelSafe(channel, true, lastWateringTime)) {
          justWatered[cubbyIndex] = true;
          lastWateringEventTime[cubbyIndex] = millis();
        }
      } else {
        Serial.printf("⛆ Default: Soil wet, channel %d OFF\n", channel);
        shellyControlWateringChannelSafe(channel, false, lastWateringTime);
      }
    }
  } catch (...) {
    Serial.printf("𝕏 Exception in watering control for cubby %d\n", cubbyIndex + 1);
  }
}

bool shellyControlWateringChannelSafe(int channel, bool turnOn, unsigned long* lastWateringTime) {
  if (!turnOn) {
    if (shellyControlWateringChannelBasic(channel, false)) {
      delay(200);
      yield();
      esp_task_wdt_reset();
      return true;
    }
    return false;
  }

  unsigned long now = millis();
  bool enoughTimePassedSinceLastWatering = (now - *lastWateringTime) >= MIN_WATERING_INTERVAL;

  if (enoughTimePassedSinceLastWatering) {

    // DISABLE I2C BEFORE WATERING
    Serial.println("⛆ WATERING START - Temporarily disabling I2C sensors for power stability");
    bool i2cWasEnabled = ENABLE_I2C_SENSORS;
    ENABLE_I2C_SENSORS = false;
    wateringInProgress = true;
    wateringStartTime = now;

    esp_task_wdt_reset();

    if (shellyControlWateringChannelBasic(channel, true)) {
      *lastWateringTime = now;

      Serial.println("⛈ Watering active - enhanced watchdog protection for 5 seconds");

      // Wait with frequent watchdog feeding
      unsigned long wateringEnd = now + WATERING_DURATION;
      while (millis() < wateringEnd) {
        esp_task_wdt_reset();
        delay(200);
        yield();
        server.handleClient();
        yield();
      }

      Serial.println("☔︎︎ WATERING COMPLETE - Re-enabling I2C after stabilization delay");

      // Additional stabilization delay
      delay(1000);
      esp_task_wdt_reset();

      // Re-enable I2C with VEML7700 reinitialization flag
      if (i2cWasEnabled) {
        ENABLE_I2C_SENSORS = true;
        lastNetworkOperation = millis();

        // ===== CRITICAL: Mark VEML7700 sensors for reinitialization =====
        veml7700SensorsNeedReinit = true;
        lastWateringEndTime = millis();

        Serial.println("⌯⌲ I2C re-enabled - VEML7700 sensors marked for reinitialization");
        Serial.println("✧ Light sensors will be skipped for 15 seconds to prevent crashes");
      }

      wateringInProgress = false;
      return true;
    } else {
      ENABLE_I2C_SENSORS = i2cWasEnabled;
      wateringInProgress = false;
      return false;
    }
  } else {
    unsigned long remainingCooldown = (MIN_WATERING_INTERVAL - (now - *lastWateringTime)) / 1000;
    Serial.printf("\tೱ Channel %d: Waiting %lu more seconds\n", channel, remainingCooldown);
    return false;
  }
}

bool reinitializeVEML7700AfterWatering() {
  Serial.println("⚙ Reinitializing VEML7700 sensors after watering disturbance...");

  // Feed watchdog before reinitialization
  esp_task_wdt_reset();

  bool allSensorsOK = true;

  for (int i = 0; i < VEML7700_COUNT; i++) {
    int channel = VEML7700_CHANNEL_START + i;

    Serial.printf("🔧 Reinitializing VEML7700 #%d on channel %d...\n", i + 1, channel);

    // Select channel carefully
    if (!selectChannelSimple(channel)) {
      Serial.printf("✖️ Failed to select channel %d during reinitialization\n", channel);
      allSensorsOK = false;
      continue;
    }

    // Reinitialize this specific sensor
    try {
      if (veml_sensors[i].begin()) {
        // Reconfigure with conservative settings after power disturbance
        veml_sensors[i].setGain(VEML7700_GAIN_1_8);
        veml_sensors[i].setIntegrationTime(VEML7700_IT_200MS);

        delay(300);  // Longer stabilization delay
        esp_task_wdt_reset();

        // Test read to verify functionality
        float testLux = veml_sensors[i].readLux();
        if (!isnan(testLux) && testLux >= 0 && testLux < 120000) {
          Serial.printf("✓ VEML7700 #%d reinitialized successfully (%.1f lux)\n", i + 1, testLux);
        } else {
          Serial.printf("⚠️ VEML7700 #%d reinitialized but test read failed\n", i + 1);
          allSensorsOK = false;
        }
      } else {
        Serial.printf("✖️ VEML7700 #%d reinitialization failed\n", i + 1);
        allSensorsOK = false;
      }
    } catch (...) {
      Serial.printf("✖️ Exception during VEML7700 #%d reinitialization\n", i + 1);
      allSensorsOK = false;
    }

    delay(500);  // Longer delay between sensor reinits
    yield();
    esp_task_wdt_reset();
  }

  if (allSensorsOK) {
    Serial.println("✓ All VEML7700 sensors reinitialized successfully after watering");
    veml7700SensorsNeedReinit = false;
    return true;
  } else {
    Serial.println("⚠️ Some VEML7700 sensors failed reinitialization - will retry next cycle");
    return false;
  }
}

bool shellyControlWateringChannelBasic(int channel, bool turnOn) {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("✖️ WiFi not connected, cannot control Shelly");
    return false;
  }

  // Mark network operation
  lastNetworkOperation = millis();

  const int MAX_RETRIES = 2;
  const unsigned long HTTP_TIMEOUT = 3000;

  for (int attempt = 1; attempt <= MAX_RETRIES; attempt++) {
    HTTPClient http;
    String url = String("http://") + shellyWaterIP + "/rpc/Light.Set";

    if (!http.begin(url)) {
      Serial.printf("✖️ HTTP begin failed for channel %d\n", channel);
      continue;
    }

    http.addHeader("Content-Type", "application/json");
    http.setTimeout(HTTP_TIMEOUT);

    String payload;
    if (turnOn) {
      payload = String("{\"id\":") + channel + ",\"on\":true,\"brightness\":100}";
    } else {
      payload = String("{\"id\":") + channel + ",\"on\":false}";
    }

    int code = http.POST(payload);

    if (code == 200) {
      Serial.printf("\t✓ Shelly Channel %d → %s (attempt %d)\n",
                    channel, turnOn ? "ON" : "OFF", attempt);
      http.end();
      return true;
    } else {
      Serial.printf("⚠️ Shelly Channel %d failed (attempt %d): HTTP %d\n",
                    channel, attempt, code);
    }

    http.end();

    if (attempt < MAX_RETRIES) {
      delay(500);
      yield();
    }
  }

  Serial.printf("⊘ Failed to control Shelly Channel %d after %d attempts\n",
                channel, MAX_RETRIES);
  return false;
}

void updateMoistureStatus(int cubbyIndex, int moistureValue, String& status) {
  if (cubbiesData[cubbyIndex].hasData) {
    if (moistureValue >= cubbiesData[cubbyIndex].soilUpper) {
      status = "dry";
    } else if (moistureValue <= cubbiesData[cubbyIndex].soilLower) {
      status = "wet";
    } else {
      status = "normal";
    }
  } else {
    status = moistureValue > 2200 ? "dry" : "wet";
  }
}

void updateLightStatus(int cubbyIndex, float lux, String& status) {
  if (cubbiesData[cubbyIndex].hasData) {
    if (lux >= cubbiesData[cubbyIndex].lightUpper) {
      status = "bright";
    } else if (lux <= cubbiesData[cubbyIndex].lightLower) {
      status = "dark";
    } else {
      status = "dim";
    }
  }
}

void updateTemperatureStatus(int cubbyIndex, float temperature, String& status) {
  if (cubbiesData[cubbyIndex].hasData) {
    if (temperature >= cubbiesData[cubbyIndex].temperatureUpper) {
      status = "hot";
    } else if (temperature <= cubbiesData[cubbyIndex].temperatureLower) {
      status = "cold";
    } else {
      status = "normal";
    }
  }
}

void updateHumidityStatus(int cubbyIndex, float humidity, String& status) {
  if (cubbiesData[cubbyIndex].hasData) {
    if (humidity >= cubbiesData[cubbyIndex].humidityUpper) {
      status = "humid";
    } else if (humidity <= cubbiesData[cubbyIndex].humidityLower) {
      status = "dry";
    } else {
      status = "normal";
    }
  }
}

void initializeLuxBasedLighting() {
  // Calculate target lux values from current cubby data (if available)
  for (int i = 0; i < 3; i++) {
    if (cubbiesData[i].hasData) {
      // Calculate from user's actual light range
      targetLux[i] = (cubbiesData[i].lightLower + cubbiesData[i].lightUpper) / 2.0;
      targetBrightness[i] = calculateBrightnessFromLux(targetLux[i]);
      Serial.printf("✮ Cubby %d: Using user data - Target %.1f lux (%d%% brightness)\n",
                    i + 1, targetLux[i], targetBrightness[i]);
    } else {
      // No user data yet - use safe defaults (will be updated when user sends data)
      targetLux[i] = 115.0;      // Reasonable default
      targetBrightness[i] = 20;  // Safe low brightness
      Serial.printf("☀ Cubby %d: No user data - Using default %.1f lux (%d%% brightness)\n",
                    i + 1, targetLux[i], targetBrightness[i]);
    }
  }

  lastLuxControlUpdate = millis();
  luxBasedControlEnabled = true;

  Serial.println("⭒ Lux-based lighting system initialized");
  Serial.println("⋆ Will update automatically when user assigns plants to cubbies");

  // Only apply initial lighting if we have user data
  bool hasAnyUserData = false;
  for (int i = 0; i < 3; i++) {
    if (cubbiesData[i].hasData) {
      hasAnyUserData = true;
      break;
    }
  }

  if (hasAnyUserData) {
    Serial.println("⊹  Applying initial lighting based on user data");
    updateLuxBasedLighting();
  } else {
    Serial.println("˖ Waiting for user to assign plants to cubbies before setting lights");
  }
}

void initializeChamberStates() {
  for (int i = 0; i < 3; i++) {
    chambers[i].currentCycle = CYCLE_DARK;
    chambers[i].currentPhase = PHASE_ADJUSTING;
    chambers[i].currentBrightness = 0;
    chambers[i].phaseStartTime = 0;
    chambers[i].lastAdjustTime = 0;
    chambers[i].cycleComplete = false;
  }
  Serial.println("Light chambers initialized");

  // Initialize light cycling
  lastLightToggle = millis();
  lightsCurrentlyOn = false;
  Serial.println("✦ Continuous light cycling enabled (5s ON/OFF cycle)");
  Serial.println();
}

// ========== NEW: Continuous Light Cycling Functions ==========
// void processLightCycling() {
//   if (!lightCycleEnabled) return;

//   unsigned long now = millis();

//   // Check if it's time to toggle lights
//   if (now - lastLightToggle >= LIGHT_CYCLE_INTERVAL) {
//     lastLightToggle = now;
//     lightsCurrentlyOn = !lightsCurrentlyOn;  // Toggle state

//     // Mark network operation to coordinate with I2C
//     lastNetworkOperation = millis();

//     if (lightsCurrentlyOn) {
//       Serial.println("𖤓 Cycling lights ON (5 seconds)");
//       setAllShelly(true, 100);
//     } else {
//       Serial.println("✶ Cycling lights OFF (5 seconds)");
//       setAllShelly(false, 0);
//     }
//   }
// }

void setAllShelly(bool on, int brightness) {
  // Send sequentially with short gap to avoid crowding Shelly
  for (int i = 0; i < 4; i++) {
    setShellyChannel(channels[i], on, brightness);
    delay(150);  // small stagger
    yield();
  }
}

bool setShellyChannelSafe(int channel, bool on, int brightness) {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("メ WiFi not connected, cannot control Shelly");
    return false;
  }

  const int MAX_RETRIES = 2;
  const unsigned long HTTP_TIMEOUT = 2000;

  for (int attempt = 1; attempt <= MAX_RETRIES; attempt++) {
    HTTPClient http;
    String url = String("http://") + shellyLightIP + "/rpc/Light.Set";

    if (!http.begin(url)) {
      Serial.printf("メ HTTP begin failed for channel %d\n", channel);
      continue;
    }

    http.addHeader("Content-Type", "application/json");
    http.setTimeout(HTTP_TIMEOUT);

    String payload;
    if (on) {
      payload = String("{\"id\":") + channel + ",\"on\":true,\"brightness\":" + brightness + "}";
    } else {
      payload = String("{\"id\":") + channel + ",\"on\":false}";
    }

    int code = http.POST(payload);

    if (code == 200) {
      Serial.printf("✓⌨ Shelly Ch%d → %s %d%% (attempt %d)\n",
                    channel, on ? "ON" : "OFF", brightness, attempt);
      http.end();
      return true;
    } else {
      Serial.printf("⚠️ Shelly Ch%d failed (attempt %d): HTTP %d\n",
                    channel, attempt, code);
    }

    http.end();

    if (attempt < MAX_RETRIES) {
      delay(300);
      yield();
    }
  }

  Serial.printf("メ Failed to control Shelly Ch%d after %d attempts\n",
                channel, MAX_RETRIES);
  return false;
}

void processLuxBasedLighting() {
  if (!luxBasedControlEnabled) return;

  unsigned long now = millis();

  // Update lighting every 5 seconds (or when new cubby data is received)
  if (now - lastLuxControlUpdate >= LUX_CONTROL_INTERVAL) {
    lastLuxControlUpdate = now;
    updateLuxBasedLighting();
  }
}

void setShellyChannel(int ch, bool on, int brightness) {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("WiFi not connected; skipping Shelly light command.");
    return;
  }

  HTTPClient http;
  String url = String("http://") + shellyLightIP + "/rpc/Light.Set";
  http.begin(url);
  http.setTimeout(HTTP_TIMEOUT_MS);
  http.addHeader("Content-Type", "application/json");

  String payload;
  if (on) {
    payload = String("{\"id\":") + ch + ",\"on\":true,\"brightness\":" + brightness + "}";
  } else {
    payload = String("{\"id\":") + ch + ",\"on\":false}";
  }

  int code = http.POST(payload);
  Serial.printf("  Shelly Ch %d → %s (HTTP %d)\n", ch, on ? "ON" : "OFF", code);
  http.end();
}

void printSystemStatus() {
  static unsigned long lastPrintTime = 0;
  unsigned long now = millis();

  if (now - lastPrintTime >= 15000) {
    lastPrintTime = now;

    // Serial.println("\n" + String("=").substring(0, 50));
    // Serial.println("◌ DELAY-BASED SYSTEM STATUS");
    // Serial.println(String("=").substring(0, 50));

    Serial.printf("모 Free Heap: %u bytes\n", ESP.getFreeHeap());
    Serial.printf("𒅒 WiFi: %s (IP: %s)\n",
                  WiFi.status() == WL_CONNECTED ? "Connected" : "Disconnected",
                  WiFi.localIP().toString().c_str());
    Serial.printf("\n⚒ I2C: %s (enabled: %s, errors: %d)\n",
                  i2cBusOK ? "OK" : "DISABLED",
                  ENABLE_I2C_SENSORS ? "YES" : "NO",
                  i2cErrorCount);
    Serial.printf("⩇⩇:⩇⩇ Uptime: %lu minutes\n", now / 60000);

    Serial.println("\n༄ Moisture Status:");
    Serial.printf("  Sensor 1: %d (%s)\n", lastMoistureValue1, lastMoistureStatus1.c_str());
    Serial.printf("  Sensor 2: %d (%s)\n", lastMoistureValue2, lastMoistureStatus2.c_str());
    Serial.printf("  Sensor 3: %d (%s)\n", lastMoistureValue3, lastMoistureStatus3.c_str());

    if (ENABLE_I2C_SENSORS && i2cBusOK) {
      Serial.println("\n𓇗 Environmental Status (Delay-Protected):");
      for (int i = 0; i < 3; i++) {
        Serial.printf("  Group %d: %.1f°C, %.1f%%, %.1f lux\n",
                      i + 1, lastTemp[i], lastHumidity[i], lastLux[i]);
      }
    } else if (!ENABLE_I2C_SENSORS) {
      Serial.println("\n 𓇢𓆸 Environmental: DISABLED");
    }

    Serial.println("\n◱ Cubbies Status:");
    for (int i = 0; i < 3; i++) {
      if (cubbiesData[i].hasData) {
        Serial.printf("  Cubby %d: Active (updated %lus ago)\n",
                      i + 1, (now - cubbiesData[i].lastUpdated) / 1000);
      } else {
        Serial.printf("  Cubby %d: Using defaults\n", i + 1);
      }
    }

    // Serial.println(String("=").substring(0, 50) + "\n");
  }
}

// ========== Simple Delay-Based Main Loop ==========
void loop() {
  esp_task_wdt_reset();
  unsigned long now = millis();

  // Feed watchdog
  if (now - lastWatchdogTime > WATCHDOG_MAX_INTERVAL) {
    feedWatchdogForce();
  }

  // Handle server requests (marks network activity)
  server.handleClient();
  yield();

  if (wateringInProgress) {
    esp_task_wdt_reset();
  }

  // Check system health
  checkSystemHealth();
  yield();


  if (currentState == MONITORING_MODE) {

    // Moisture control (always safe)
    processMoistureControlSafe();
    yield();

    // Environmental sensors (with simple delay protection)
    if (ENABLE_I2C_SENSORS) {
      // Serial.println();
      processEnvironmentalSensorsSafe();
    }
    yield();
    esp_task_wdt_reset();

    if (ENABLE_I2C_SENSORS && !wateringInProgress) {
      processEnvironmentalSensorsSafe();
    }
    yield();
    esp_task_wdt_reset();  // Feed after environmental sensors

    // Status printing
    printSystemStatus();
    yield();
  }

  // Simple delay
  delay(200);
  yield();
}

// ========== Setup ==========
void setup() {

  esp_task_wdt_init(20, true);  // 30 second timeout
  esp_task_wdt_add(NULL);

  Serial.begin(115200);
  delay(1000);
  Serial.println("⏻ Starting Plant Monitoring + Light Cycling System...");
  Serial.println();

  Serial.println("⟡ Light cycling enabled: 5s ON/OFF continuous cycle");
  Serial.println();

  if (ENABLE_I2C_SENSORS) {
    Serial.println("⛀ I2C sensors enabled - using simple delay separation");
    Serial.printf("⏱︎ Delay after network operations: %lu ms\n", I2C_DELAY_AFTER_NETWORK);
    Serial.println();
  } else {
    Serial.println("✘ I2C sensors disabled");
  }

  if (tryStoredWiFiConnection()) {
    currentState = MONITORING_MODE;
    switchToMonitoringMode();
    Serial.println("✓ Started in monitoring mode!");
  } else {
    setupWiFiAccessPoint();
  }
}  // 2204 -->