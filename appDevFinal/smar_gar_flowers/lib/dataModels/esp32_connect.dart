import 'package:hive/hive.dart';

part 'esp32_connect.g.dart';

@HiveType(typeId: 1) // Make sure this typeId is unique across your app
class ESP32Connection extends HiveObject {
  @HiveField(0)
  String? ipAddress;

  @HiveField(1)
  String? ssid;

  @HiveField(2)
  DateTime? lastConnected;

  @HiveField(3)
  bool isConnected;

  @HiveField(4)
  String? deviceName;

  ESP32Connection({
    this.ipAddress,
    this.ssid,
    this.lastConnected,
    this.isConnected = false,
    this.deviceName = 'F.L.O.W.E.R.S. Garden',
  });

  // Helper method to update connection status
  void updateConnection({
    String? newIpAddress,
    String? newSSID,
    bool? connected,
  }) {
    if (newIpAddress != null) ipAddress = newIpAddress;
    if (newSSID != null) ssid = newSSID;
    if (connected != null) isConnected = connected;
    if (connected == true) lastConnected = DateTime.now();
    save(); // Save to Hive
  }

  // Helper method to disconnect
  void disconnect() {
    isConnected = false;
    save();
  }

  @override
  String toString() {
    return 'ESP32Connection{ipAddress: $ipAddress, ssid: $ssid, lastConnected: $lastConnected, isConnected: $isConnected}';
  }
}