import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../../dataModels/esp32_connect.dart';
import '../../dataModels/plant.dart';

class ClimateHotkeyScreen extends StatefulWidget {
  const ClimateHotkeyScreen({Key? key}) : super(key: key);

  @override
  State<ClimateHotkeyScreen> createState() => _ClimateHotkeyScreenState();
}

class _ClimateHotkeyScreenState extends State<ClimateHotkeyScreen>
    with TickerProviderStateMixin {
  int? selectedCubby;
  late Box<ESP32Connection> esp32Box;
  late Box<Plant> plantsBox;
  late Box<int> cubbyBox;
  Map<String, dynamic>? sensorData;
  Timer? sensorDataTimer;
  bool isLoadingSensorData = false;
  bool isInitialized = false;

  // Tab controller for switching between temperature and humidity
  late TabController _tabController;
  
  // Temperature ranges (in Fahrenheit)
  final Map<String, Map<String, double>> temperatureRanges = {
    'cold': {'lower': 0, 'upper': 68},
    'warm': {'lower': 68, 'upper': 80},
    'hot': {'lower': 80, 'upper': 200}, // High upper limit for hot
  };

  // Humidity ranges (in percentage)
  final Map<String, Map<String, int>> humidityRanges = {
    'dry': {'lower': 0, 'upper': 35},
    'normal': {'lower': 35, 'upper': 65},
    'humid': {'lower': 65, 'upper': 100},
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initializeBoxes();
  }

  @override
  void dispose() {
    sensorDataTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _initializeBoxes() async {
    try {
      esp32Box = await Hive.openBox<ESP32Connection>('esp32_connection');
      plantsBox = Hive.box<Plant>('plantsBox');
      cubbyBox = Hive.box<int>('cubbyAssignments');
      await _fetchSensorData();
      _startPeriodicSensorDataUpdate();
      setState(() {
        isInitialized = true;
      });
    } catch (e) {
      print('Error initializing boxes: $e');
      setState(() {
        isInitialized = true;
      });
    }
  }

  void _startPeriodicSensorDataUpdate() {
    sensorDataTimer = Timer.periodic(Duration(seconds: 10), (timer) {
      _fetchSensorData();
    });
  }

  Future<void> _fetchSensorData() async {
    if (!isInitialized || esp32Box.isEmpty) {
      print('ESP32 box is empty or not initialized');
      setState(() {
        sensorData = null;
        isLoadingSensorData = false;
      });
      return;
    }

    final esp32 = esp32Box.getAt(0);
    if (esp32 == null || esp32.ipAddress == null || esp32.ipAddress!.isEmpty) {
      print('No ESP32 device configured or no IP address');
      setState(() {
        sensorData = null;
        isLoadingSensorData = false;
      });
      return;
    }

    setState(() {
      isLoadingSensorData = true;
    });

    final url = Uri.parse('http://${esp32.ipAddress}/sensors');

    try {
      print('Fetching sensor data from: $url');
      final response = await http.get(url).timeout(Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          sensorData = data;
          isLoadingSensorData = false;
        });
        print('Sensor data fetched successfully: $sensorData');
      } else {
        print('Failed to fetch sensor data: ${response.statusCode}');
        setState(() {
          sensorData = null;
          isLoadingSensorData = false;
        });
      }
    } catch (e) {
      print('Error fetching sensor data: $e');
      setState(() {
        sensorData = null;
        isLoadingSensorData = false;
      });
    }
  }

  // Convert Celsius to Fahrenheit
  double _celsiusToFahrenheit(double celsius) {
    return (celsius * 9 / 5) + 32;
  }

  // Get current temperature reading
  String _getCurrentTemperature(int cubbyIndex) {
    if (isLoadingSensorData) return 'Loading...';
    if (sensorData == null) return 'No connection';

    final sensorKey = 'temperature${cubbyIndex + 1}';
    final tempData = sensorData!['environment']?[sensorKey];

    if (tempData != null && 
        tempData['value'] != null && 
        tempData['value'] != 0) {
      final celsiusValue = tempData['value'].toDouble();
      final fahrenheitValue = _celsiusToFahrenheit(celsiusValue);
      final category = _getTemperatureCategory(fahrenheitValue);
      return '${fahrenheitValue.toStringAsFixed(1)}°F ($category)';
    }
    return 'No data';
  }

  // Get current humidity reading
  String _getCurrentHumidity(int cubbyIndex) {
    if (isLoadingSensorData) return 'Loading...';
    if (sensorData == null) return 'No connection';

    final sensorKey = 'humidity${cubbyIndex + 1}';
    final humidityData = sensorData!['environment']?[sensorKey];

    if (humidityData != null && 
        humidityData['value'] != null && 
        humidityData['value'] != 0) {
      final humidityValue = humidityData['value'].toDouble();
      final category = _getHumidityCategory(humidityValue);
      return '${humidityValue.toStringAsFixed(1)}% ($category)';
    }
    return 'No data';
  }

  // Determine temperature category based on Fahrenheit value
  String _getTemperatureCategory(double fahrenheitValue) {
    if (fahrenheitValue >= temperatureRanges['hot']!['lower']!) {
      return 'hot';
    } else if (fahrenheitValue >= temperatureRanges['warm']!['lower']!) {
      return 'warm';
    } else {
      return 'cold';
    }
  }

  // Determine humidity category based on percentage value
  String _getHumidityCategory(double humidityValue) {
    if (humidityValue >= humidityRanges['humid']!['lower']!) {
      return 'humid';
    } else if (humidityValue >= humidityRanges['normal']!['lower']!) {
      return 'normal';
    } else {
      return 'dry';
    }
  }

  // Get temperature GIF path
  String _getTemperatureGifPath(int cubbyIndex) {
    final cubbyNum = cubbyIndex + 1;
    
    // Check if data is loading or unavailable
    if (isLoadingSensorData || sensorData == null) {
      return 'assets/images/gifsEnvironments/tempPlusHumid/loadingTemp$cubbyNum.gif';
    }

    // Get current temperature data
    final sensorKey = 'temperature${cubbyIndex + 1}';
    final tempData = sensorData!['environment']?[sensorKey];

    if (tempData == null || 
        tempData['value'] == null || 
        tempData['value'] == 0) {
      return 'assets/images/gifsEnvironments/tempPlusHumid/loadingTemp$cubbyNum.gif';
    }
    
    final celsiusValue = tempData['value'].toDouble();
    final fahrenheitValue = _celsiusToFahrenheit(celsiusValue);
    final category = _getTemperatureCategory(fahrenheitValue);
    
    return 'assets/images/gifsEnvironments/tempPlusHumid/$category$cubbyNum.gif';
  }

  // Get humidity GIF path
  String _getHumidityGifPath(int cubbyIndex) {
    final cubbyNum = cubbyIndex + 1;
    
    // Check if data is loading or unavailable
    if (isLoadingSensorData || sensorData == null) {
      return 'assets/images/gifsEnvironments/tempPlusHumid/loadingHumidity$cubbyNum.gif';
    }

    // Get current humidity data
    final sensorKey = 'humidity${cubbyIndex + 1}';
    final humidityData = sensorData!['environment']?[sensorKey];

    if (humidityData == null || 
        humidityData['value'] == null || 
        humidityData['value'] == 0) {
      return 'assets/images/gifsEnvironments/tempPlusHumid/loadingHumidity$cubbyNum.gif';
    }
    
    final humidityValue = humidityData['value'].toDouble();
    final category = _getHumidityCategory(humidityValue);
    
    // Handle special case for 'humid' category (no 'Humidity' suffix)
    if (category == 'humid') {
      return 'assets/images/gifsEnvironments/tempPlusHumid/humid$cubbyNum.gif';
    } else {
      return 'assets/images/gifsEnvironments/tempPlusHumid/${category}Humidity$cubbyNum.gif';
    }
  }

  void _onCubbyTapped(int cubbyIndex) {
    setState(() {
      selectedCubby = selectedCubby == cubbyIndex ? null : cubbyIndex;
    });
    
    // Trigger immediate sensor data refresh when a cubby is tapped
    _fetchSensorData();
    
    // Show climate details for the selected cubby
    _showClimateDetails(cubbyIndex);
  }

  void _showClimateDetails(int cubbyIndex) {
    final plantKey = cubbyBox.get(cubbyIndex);
    final plant = plantKey != null ? plantsBox.get(plantKey) : null;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Cubby ${cubbyIndex + 1} Climate'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (plant != null) ...[
              Text(
                'Plant: ${plant.commonName}',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              SizedBox(height: 12),
            ],
            _buildClimateDataRow(Icons.thermostat, 'Temperature', _getCurrentTemperature(cubbyIndex), const Color.fromARGB(255, 237, 152, 223)),
            SizedBox(height: 8),
            _buildClimateDataRow(Icons.opacity, 'Humidity', _getCurrentHumidity(cubbyIndex), const Color.fromARGB(255, 35, 49, 245)),
            if (plant == null) ...[
              SizedBox(height: 12),
              Text(
                'No plant assigned to this cubby',
                style: TextStyle(color: Colors.grey[600], fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildClimateDataRow(IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            '$label: $value',
            style: TextStyle(fontSize: 16),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Climate Monitor'),
        backgroundColor: Color(0xFF408661),
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(
              icon: Icon(Icons.thermostat),
              text: 'Temperature',
            ),
            Tab(
              icon: Icon(Icons.opacity),
              text: 'Humidity',
            ),
          ],
        ),
      ),
      body: Container(
        child: TabBarView(
          controller: _tabController,
          children: [
            // Temperature Tab
            _buildClimateTab(
              title: 'See how temperature is affecting your environment!',
              isTemperature: true,
              primaryColor: Colors.orange,
              accentColor: Color(0xFFFF5722),
            ),
            // Humidity Tab
            _buildClimateTab(
              title: 'Monitor humidity levels in your environment!',
              isTemperature: false,
              primaryColor: Colors.blue,
              accentColor: Color(0xFF1976D2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClimateTab({
    required String title,
    required bool isTemperature,
    required Color primaryColor,
    required Color accentColor,
  }) {
    return SingleChildScrollView(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[700],
              ),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(height: 20),
          // Climate Shelf3D with GIFs
          ClimateShelf3D(
            selectedCubby: selectedCubby,
            onCubbyTapped: _onCubbyTapped,
            sensorData: sensorData,
            isLoadingSensorData: isLoadingSensorData,
            getCurrentTemperature: _getCurrentTemperature,
            getCurrentHumidity: _getCurrentHumidity,
            getTemperatureGifPath: _getTemperatureGifPath,
            getHumidityGifPath: _getHumidityGifPath,
            isTemperature: isTemperature,
            primaryColor: primaryColor,
            accentColor: accentColor,
          ),
          SizedBox(height: 20),
          // Climate information below the shelf
          _buildClimateInfo(isTemperature, primaryColor),
          SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildClimateInfo(bool isTemperature, Color primaryColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        children: [
          for (int i = 0; i < 3; i++) ...[
            Container(
              margin: EdgeInsets.only(bottom: 12),
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: selectedCubby == i 
                    ? primaryColor.withOpacity(0.1) 
                    : Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selectedCubby == i 
                      ? primaryColor 
                      : Colors.grey[300]!,
                  width: selectedCubby == i ? 2 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cubby ${i + 1}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: primaryColor,
                    ),
                  ),
                  SizedBox(height: 8),
                  if (isTemperature) ...[
                    _buildClimateDataRow(
                      Icons.thermostat,
                      'Temperature',
                      _getCurrentTemperature(i),
                      primaryColor,
                    ),
                  ] else ...[
                    _buildClimateDataRow(
                      Icons.opacity,
                      'Humidity',
                      _getCurrentHumidity(i),
                      primaryColor,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// Climate-specific Shelf3D class
class ClimateShelf3D extends StatelessWidget {
  final int? selectedCubby;
  final Function(int) onCubbyTapped;
  final Map<String, dynamic>? sensorData;
  final bool isLoadingSensorData;
  final String Function(int) getCurrentTemperature;
  final String Function(int) getCurrentHumidity;
  final String Function(int) getTemperatureGifPath;
  final String Function(int) getHumidityGifPath;
  final bool isTemperature;
  final Color primaryColor;
  final Color accentColor;

  const ClimateShelf3D({
    Key? key,
    this.selectedCubby,
    required this.onCubbyTapped,
    this.sensorData,
    this.isLoadingSensorData = false,
    required this.getCurrentTemperature,
    required this.getCurrentHumidity,
    required this.getTemperatureGifPath,
    required this.getHumidityGifPath,
    required this.isTemperature,
    required this.primaryColor,
    required this.accentColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;

        double baseWidth = 500;
        double baseHeight = 200;

        double scaleFactor = (screenWidth / baseWidth).clamp(0.3, 2.0);

        if (screenWidth < 400) {
          scaleFactor = (screenWidth * 0.9) / baseWidth;
        }

        if (scaleFactor < 0.6) {
          scaleFactor = 0.6;
        }

        double shelfWidth = baseWidth * scaleFactor;
        double shelfHeight = baseHeight * scaleFactor;

        if (shelfWidth > screenWidth * 0.95) {
          scaleFactor = (screenWidth * 0.95) / baseWidth;
          shelfWidth = baseWidth * scaleFactor;
          shelfHeight = baseHeight * scaleFactor;
        }

        return Center(
          child: SingleChildScrollView(
            child: Container(
              width: shelfWidth,
              height: shelfHeight,
              child: Stack(
                children: [
                  _buildShelfStructure(scaleFactor),
                  _buildCubby(0, 15 * scaleFactor, 10 * scaleFactor, scaleFactor),
                  _buildCubby(1, 175 * scaleFactor, 10 * scaleFactor, scaleFactor),
                  _buildCubby(2, 330 * scaleFactor, 10 * scaleFactor, scaleFactor),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildShelfStructure(double scaleFactor) {
    return Container(
      width: 500 * scaleFactor,
      height: 200 * scaleFactor,
      child: CustomPaint(painter: ClimateShelfPainter(
        scaleFactor: scaleFactor,
        primaryColor: primaryColor,
        accentColor: accentColor,
      )),
    );
  }

  Widget _buildCubby(int index, double left, double top, double scaleFactor) {
    bool isSelected = selectedCubby == index;

    double cubbyWidth = 130 * scaleFactor;
    double cubbyHeight = 150 * scaleFactor;

    return Positioned(
      left: left + (20 * scaleFactor),
      top: top + (20 * scaleFactor),
      child: GestureDetector(
        onTap: () => onCubbyTapped(index),
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.002)
            ..rotateY(0.05)
            ..rotateX(-0.02),
          child: Container(
            width: cubbyWidth,
            height: cubbyHeight,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isSelected
                    ? [
                        primaryColor.withOpacity(0.9),
                        accentColor.withOpacity(0.95),
                        accentColor.withOpacity(0.9),
                      ]
                    : [
                        primaryColor.withOpacity(0.3),
                        primaryColor.withOpacity(0.5),
                        accentColor.withOpacity(0.3),
                      ],
                stops: [0.0, 0.5, 1.0],
              ),
              borderRadius: BorderRadius.circular(4 * scaleFactor),
              border: Border.all(
                color: isSelected
                    ? accentColor.withOpacity(0.8)
                    : primaryColor.withOpacity(0.4),
                width: 1 * scaleFactor,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 6 * scaleFactor,
                  offset: Offset(2 * scaleFactor, 3 * scaleFactor),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 3 * scaleFactor,
                  offset: Offset(1 * scaleFactor, 1 * scaleFactor),
                ),
              ],
            ),
            child: Stack(
              children: [
                // GIF Container
                Container(
                  margin: EdgeInsets.all(8 * scaleFactor),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4 * scaleFactor),
                    border: Border.all(
                      color: isSelected
                          ? accentColor.withOpacity(0.6)
                          : primaryColor.withOpacity(0.3),
                      width: 1 * scaleFactor,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3 * scaleFactor),
                    child: Container(
                      width: double.infinity,
                      height: double.infinity,
                      child: Image.asset(
                        isTemperature 
                            ? getTemperatureGifPath(index)
                            : getHumidityGifPath(index),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          // Fallback if GIF doesn't load
                          return Container(
                            color: primaryColor.withOpacity(0.1),
                            child: Center(
                              child: Icon(
                                isTemperature ? Icons.thermostat : Icons.opacity,
                                size: 20 * scaleFactor,
                                color: primaryColor,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                // Selection overlay
                if (isSelected)
                  Container(
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4 * scaleFactor),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Climate-themed shelf painter
class ClimateShelfPainter extends CustomPainter {
  final double scaleFactor;
  final Color primaryColor;
  final Color accentColor;

  ClimateShelfPainter({
    required this.scaleFactor,
    required this.primaryColor,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.fill;

    final darkPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;

    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.25)
      ..style = PaintingStyle.fill;

    final highlightPaint = Paint()
      ..color = primaryColor.withOpacity(0.7)
      ..style = PaintingStyle.fill;

    _drawShelfShadow(canvas, size, shadowPaint);
    _drawShelfStructure(canvas, size, paint, darkPaint, highlightPaint);
  }

  void _drawShelfShadow(Canvas canvas, Size size, Paint shadowPaint) {
    final shadowOffset = 8.0 * scaleFactor;

    final topShelfShadow = Path()
      ..moveTo(15.0 * scaleFactor, 15.0 * scaleFactor)
      ..lineTo(485.0 * scaleFactor, 15.0 * scaleFactor)
      ..lineTo(485.0 * scaleFactor + shadowOffset, 15.0 * scaleFactor + shadowOffset)
      ..lineTo(15.0 * scaleFactor + shadowOffset, 15.0 * scaleFactor + shadowOffset)
      ..close();
    canvas.drawPath(topShelfShadow, shadowPaint);

    final bottomShelfShadow = Path()
      ..moveTo(15.0 * scaleFactor, 185.0 * scaleFactor)
      ..lineTo(485.0 * scaleFactor, 185.0 * scaleFactor)
      ..lineTo(485.0 * scaleFactor + shadowOffset, 185.0 * scaleFactor + shadowOffset)
      ..lineTo(15.0 * scaleFactor + shadowOffset, 185.0 * scaleFactor + shadowOffset)
      ..close();
    canvas.drawPath(bottomShelfShadow, shadowPaint);

    for (int i = 1; i < 3; i++) {
      final x = (15.0 + (i * 160.0)) * scaleFactor;
      final dividerShadow = Path()
        ..moveTo(x, 15.0 * scaleFactor)
        ..lineTo(x + (10.0 * scaleFactor), 15.0 * scaleFactor)
        ..lineTo(x + (10.0 * scaleFactor) + shadowOffset, 15.0 * scaleFactor + shadowOffset)
        ..lineTo(x + shadowOffset, 15.0 * scaleFactor + shadowOffset)
        ..lineTo(x + shadowOffset, 185.0 * scaleFactor + shadowOffset)
        ..lineTo(x, 185.0 * scaleFactor)
        ..close();
      canvas.drawPath(dividerShadow, shadowPaint);
    }

    final leftSupportShadow = Path()
      ..moveTo(15.0 * scaleFactor, 15.0 * scaleFactor)
      ..lineTo(25.0 * scaleFactor, 15.0 * scaleFactor)
      ..lineTo(25.0 * scaleFactor + shadowOffset, 15.0 * scaleFactor + shadowOffset)
      ..lineTo(15.0 * scaleFactor + shadowOffset, 15.0 * scaleFactor + shadowOffset)
      ..lineTo(15.0 * scaleFactor + shadowOffset, 185.0 * scaleFactor + shadowOffset)
      ..lineTo(15.0 * scaleFactor, 185.0 * scaleFactor)
      ..close();
    canvas.drawPath(leftSupportShadow, shadowPaint);

    final rightSupportShadow = Path()
      ..moveTo(485.0 * scaleFactor, 15.0 * scaleFactor)
      ..lineTo(495.0 * scaleFactor, 15.0 * scaleFactor)
      ..lineTo(495.0 * scaleFactor + shadowOffset, 15.0 * scaleFactor + shadowOffset)
      ..lineTo(485.0 * scaleFactor + shadowOffset, 15.0 * scaleFactor + shadowOffset)
      ..lineTo(485.0 * scaleFactor + shadowOffset, 185.0 * scaleFactor + shadowOffset)
      ..lineTo(485.0 * scaleFactor, 185.0 * scaleFactor)
      ..close();
    canvas.drawPath(rightSupportShadow, shadowPaint);
  }

  void _drawShelfStructure(Canvas canvas, Size size, Paint paint, Paint darkPaint, Paint highlightPaint) {
    _drawBeveledRect(canvas, Rect.fromLTWH(15.0 * scaleFactor, 15.0 * scaleFactor, 470.0 * scaleFactor, 10.0 * scaleFactor), paint, darkPaint, highlightPaint);
    _drawBeveledRect(canvas, Rect.fromLTWH(15.0 * scaleFactor, 185.0 * scaleFactor, 470.0 * scaleFactor, 10.0 * scaleFactor), paint, darkPaint, highlightPaint);
    _drawBeveledRect(canvas, Rect.fromLTWH(15.0 * scaleFactor, 15.0 * scaleFactor, 10.0 * scaleFactor, 180.0 * scaleFactor), paint, darkPaint, highlightPaint);
    _drawBeveledRect(canvas, Rect.fromLTWH(485.0 * scaleFactor, 15.0 * scaleFactor, 10.0 * scaleFactor, 180.0 * scaleFactor), paint, darkPaint, highlightPaint);
    _drawBeveledRect(canvas, Rect.fromLTWH(175.0 * scaleFactor, 15.0 * scaleFactor, 10.0 * scaleFactor, 180.0 * scaleFactor), paint, darkPaint, highlightPaint);
    _drawBeveledRect(canvas, Rect.fromLTWH(335.0 * scaleFactor, 15.0 * scaleFactor, 10.0 * scaleFactor, 180.0 * scaleFactor), paint, darkPaint, highlightPaint);
  }

  void _drawBeveledRect(Canvas canvas, Rect rect, Paint mainPaint, Paint darkPaint, Paint lightPaint) {
    canvas.drawRect(rect, mainPaint);
    canvas.drawRect(Rect.fromLTWH(rect.left, rect.top, rect.width, 2 * scaleFactor), lightPaint);
    canvas.drawRect(Rect.fromLTWH(rect.left, rect.top, 2 * scaleFactor, rect.height), lightPaint);
    canvas.drawRect(Rect.fromLTWH(rect.left, rect.bottom - (2 * scaleFactor), rect.width, 2 * scaleFactor), darkPaint);
    canvas.drawRect(Rect.fromLTWH(rect.right - (2 * scaleFactor), rect.top, 2 * scaleFactor, rect.height), darkPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return oldDelegate is ClimateShelfPainter && 
           (oldDelegate.scaleFactor != scaleFactor ||
            oldDelegate.primaryColor != primaryColor ||
            oldDelegate.accentColor != accentColor);
  }
}