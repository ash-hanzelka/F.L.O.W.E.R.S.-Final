import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:hive/hive.dart';
import '../dataModels/esp32_connect.dart';

class ConnectionInstructionsScreen extends StatefulWidget {
  @override
  _ConnectionInstructionsScreenState createState() => _ConnectionInstructionsScreenState();
}

class _ConnectionInstructionsScreenState extends State<ConnectionInstructionsScreen> {
  final TextEditingController ssidController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final ScrollController scrollController = ScrollController();

  String statusMessage = "";
  String? connectedIP;
  bool _isLoading = false;
  ESP32Connection? _esp32Connection;
  late Box<ESP32Connection> _connectionBox;

  @override
  void initState() {
    super.initState();
    _initializeHive();
  }

  Future<void> _initializeHive() async {
    try {
      _connectionBox = await Hive.openBox<ESP32Connection>('esp32_connection');
      
      // Load existing connection if it exists
      if (_connectionBox.isNotEmpty) {
        _esp32Connection = _connectionBox.getAt(0);
        if (_esp32Connection != null) {
          setState(() {
            connectedIP = _esp32Connection!.ipAddress;
            if (_esp32Connection!.isConnected && _esp32Connection!.ipAddress != null) {
              statusMessage = "🌸 Previously connected to ${_esp32Connection!.ssid} (IP: ${_esp32Connection!.ipAddress})";
            }
          });
        }
      }
    } catch (e) {
      print('Error initializing Hive: $e');
    }
  }

  Future<void> _saveConnection({
    required String ssid,
    String? ipAddress,
    bool isConnected = false,
  }) async {
    try {
      if (_esp32Connection == null) {
        _esp32Connection = ESP32Connection();
        await _connectionBox.add(_esp32Connection!);
      }
      
      _esp32Connection!.updateConnection(
        newIpAddress: ipAddress,
        newSSID: ssid,
        connected: isConnected,
      );
      
      print('Connection saved: ${_esp32Connection.toString()}');
    } catch (e) {
      print('Error saving connection: $e');
    }
  }

  @override
  void dispose() {
    ssidController.dispose();
    passwordController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  void _dismissKeyboard() {
    FocusScope.of(context).unfocus();
  }

  Future<void> sendCredentials() async {
    final ssid = ssidController.text;
    final password = passwordController.text;

    if (ssid.isEmpty) {
      setState(() {
        statusMessage = "🌱 Please enter a Wi-Fi SSID to connect your garden.";
        connectedIP = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      statusMessage = "🌿 Connecting your garden to the network...";
      connectedIP = null;
    });

    final url = Uri.parse('http://192.168.4.1/wifi');
    final body = jsonEncode({'ssid': ssid, 'password': password});

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      if (response.statusCode == 200) {
        // Try to parse JSON response
        try {
          final responseData = jsonDecode(response.body);
          final ip = responseData['ip'];
          
          // Save successful connection to Hive
          await _saveConnection(
            ssid: ssid,
            ipAddress: ip,
            isConnected: true,
          );
          
          setState(() {
            statusMessage = "Officially connected! Your F.L.O.W.E.R.S. garden is now online!";
            connectedIP = ip;
          });
        } catch (e) {
          // Fallback if response isn't JSON - still save the connection
          await _saveConnection(
            ssid: ssid,
            isConnected: true,
          );
          
          setState(() {
            statusMessage = "Success! Your F.L.O.W.E.R.S. garden is now connected!";
            connectedIP = null;
          });
        }
      } else {
        // Save failed connection attempt
        await _saveConnection(
          ssid: ssid,
          isConnected: false,
        );
        
        setState(() {
          statusMessage = "Connection failed (Error: ${response.statusCode})";
          connectedIP = null;
        });
      }
    } catch (e) {
      // Save failed connection attempt
      await _saveConnection(
        ssid: ssid,
        isConnected: false,
      );
      
      setState(() {
        statusMessage = "Could not reach your garden device. Please check the connection.";
        connectedIP = null;
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Method to clear saved connection
  Future<void> _clearSavedConnection() async {
    try {
      if (_esp32Connection != null) {
        _esp32Connection!.disconnect();
        setState(() {
          connectedIP = null;
          statusMessage = "Connection cleared.";
        });
      }
    } catch (e) {
      print('Error clearing connection: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _dismissKeyboard,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min, // Prevent overflow in title
            children: [
              Icon(Icons.local_florist_outlined, color: Color.fromARGB(255, 72, 105, 79)),
              SizedBox(width: 8),
              Flexible( // Allow text to wrap if needed
                child: Text(
                  'F.L.O.W.E.R.S. Garden Setup',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          centerTitle: false,
          backgroundColor: Color.fromARGB(255, 172, 210, 180),
          foregroundColor: Color.fromARGB(255, 72, 105, 79),
          actions: [
            if (_esp32Connection != null && _esp32Connection!.isConnected)
              IconButton(
                icon: Icon(Icons.clear),
                onPressed: _clearSavedConnection,
                tooltip: 'Clear saved connection',
              ),
          ],
        ),
        body: Container(
          decoration: BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/images/backgrounds/phoneBckgdDark.jpg'),
              fit: BoxFit.cover,
            ),
          ),
          child: SafeArea(
            child: LayoutBuilder( // Use LayoutBuilder to get screen constraints
              builder: (context, constraints) {
                return SingleChildScrollView(
                  controller: scrollController,
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12), // Reduced padding
                  child: ConstrainedBox( // Ensure content doesn't exceed screen width
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 24, // Account for padding
                      maxWidth: constraints.maxWidth - 32, // Account for horizontal padding
                    ),
                    child: IntrinsicHeight( // Let content determine height
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Header Card
                          Card(
                            elevation: 4,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: Container(
                              padding: EdgeInsets.all(16), // Reduced padding
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(15),
                                gradient: LinearGradient(
                                  colors: [Colors.white, Color(0xFFF1F8E9)],
                                ),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.cell_tower_outlined,
                                    size: 40, // Slightly smaller icon
                                    color: Color(0xFF2E7D32),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'Connect Your Smart Garden',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF2E7D32),
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  SizedBox(height: 6),
                                  Text(
                                    'Follow these steps to connect your F.L.O.W.E.R.S. environment to your home WiFi',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF4A5A4A),
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(height: 16),
                          
                          // Show saved connection info if available
                          if (_esp32Connection != null && _esp32Connection!.isConnected) ...[
                            Card(
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Container(
                                padding: EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  color: Color(0xFF4CAF50),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check_circle, color: Colors.white, size: 28),
                                    SizedBox(height: 6),
                                    Text(
                                      'Previously Connected',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Network: ${_esp32Connection!.ssid ?? 'Unknown'}',
                                      style: TextStyle(color: Colors.white, fontSize: 13),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (_esp32Connection!.ipAddress != null)
                                      Text(
                                        'IP: ${_esp32Connection!.ipAddress}',
                                        style: TextStyle(color: Colors.white, fontSize: 13),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    if (_esp32Connection!.lastConnected != null)
                                      Text(
                                        'Last: ${_esp32Connection!.lastConnected!.toLocal().toString().split('.')[0]}',
                                        style: TextStyle(color: Colors.white70, fontSize: 11),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            SizedBox(height: 16),
                          ],
                          
                          // Instructions Card
                          Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.list_alt, color: Color(0xFF2E7D32)),
                                      SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          'Setup Instructions',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF2E7D32),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 10),
                                  _buildInstructionStep('1', 'Power on your F.L.O.W.E.R.S. environment'),
                                  _buildInstructionStep('2', 'Go to iPhone Settings > WiFi'),
                                  _buildInstructionStep('3', 'Connect to "FLOWERS-SETUP" (password: 12345678)'),
                                  _buildInstructionStep('4', 'Return to this app'),
                                  _buildInstructionStep('5', 'Enter your home WiFi credentials below'),
                                  _buildInstructionStep('6', 'Tap "Connect Garden" to send credentials'),
                                  _buildInstructionStep('7', 'Reconnect your phone to home WiFi'),
                                  _buildInstructionStep('8', 'Forget the "FLOWERS-SETUP" network to avoid future connection issues'),
                                  SizedBox(height: 8),
                                  Container(
                                    padding: EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Color(0xFFE8F5E8),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Color(0xFF81C784)),
                                    ),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Icon(Icons.info_outline, color: Color(0xFF2E7D32), size: 18),
                                        SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'NOTE: Your phone and F.L.O.W.E.R.S. environment must be on the same network to maintain connection.',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Color(0xFF2E7D32),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(height: 16),
                          
                          // WiFi Credentials Form
                          Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.wifi, color: Color(0xFF2E7D32)),
                                      SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          'WiFi Credentials',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF2E7D32),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 14),
                                  TextField(
                                    controller: ssidController,
                                    decoration: InputDecoration(
                                      labelText: 'WiFi Network Name (SSID)',
                                      prefixIcon: Icon(Icons.wifi),
                                      hintText: 'Enter your home WiFi name',
                                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                      isDense: true,
                                    ),
                                  ),
                                  SizedBox(height: 14),
                                  TextField(
                                    controller: passwordController,
                                    decoration: InputDecoration(
                                      labelText: 'WiFi Password',
                                      prefixIcon: Icon(Icons.lock),
                                      hintText: 'Enter your WiFi password',
                                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                      isDense: true,
                                    ),
                                    obscureText: true,
                                  ),
                                  SizedBox(height: 20),
                                  Center(
                                    child: _isLoading
                                        ? Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              CircularProgressIndicator(
                                                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2E7D32)),
                                              ),
                                              SizedBox(height: 10),
                                              Text(
                                                'Connecting your garden...',
                                                style: TextStyle(color: Color(0xFF2E7D32), fontSize: 13),
                                              ),
                                            ],
                                          )
                                        : SizedBox(
                                            width: MediaQuery.of(context).size.width * 0.6,
                                            child: ElevatedButton.icon(
                                              onPressed: sendCredentials,
                                              icon: Icon(Icons.send, color: Color.fromARGB(255, 72, 105, 79)),
                                              label: Text('Connect Garden'),
                                              style: ElevatedButton.styleFrom(
                                                padding: EdgeInsets.symmetric(vertical: 12),
                                                backgroundColor: Color.fromARGB(255, 172, 210, 180),
                                                foregroundColor: Color.fromARGB(255, 72, 105, 79),
                                              ),
                                            ),
                                          ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(height: 16),
                          
                          // Status Message
                          if (statusMessage.isNotEmpty)
                            Card(
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Container(
                                width: double.infinity,
                                padding: EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  color: _getStatusColor(),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      statusMessage,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w500,
                                        fontSize: 13,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    if (connectedIP != null) ...[
                                      SizedBox(height: 6),
                                      Container(
                                        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          'IP Address: $connectedIP',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInstructionStep(String number, String instruction) {
    return Padding(
      padding: EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: Color(0xFF4CAF50),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Center(
              child: Text(
                number,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              instruction,
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF4A5A4A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor() {
    if (statusMessage.contains('Success') || statusMessage.contains('🌸') || statusMessage.contains('Officially connected')) {
      return Color(0xFF4CAF50);
    } else if (statusMessage.contains('failed') || statusMessage.contains('🥀') || statusMessage.contains('🌵')) {
      return Color(0xFFE57373);
    } else if (statusMessage.contains('🌿')) {
      return Color(0xFF81C784);
    } else {
      return Color(0xFF2E7D32);
    }
  }
}