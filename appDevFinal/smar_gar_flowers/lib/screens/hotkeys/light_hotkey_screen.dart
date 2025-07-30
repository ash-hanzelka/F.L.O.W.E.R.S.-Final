import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../../dataModels/esp32_connect.dart';
import '../../dataModels/plant.dart';

class LightingHotkeyScreen extends StatefulWidget {
  const LightingHotkeyScreen({Key? key}) : super(key: key);

  @override
  State<LightingHotkeyScreen> createState() => _LightingHotkeyScreenState();
}

class _LightingHotkeyScreenState extends State<LightingHotkeyScreen> {
  int? selectedCubby;
  late Box<ESP32Connection> esp32Box;
  late Box<Plant> plantsBox;
  late Box<int> cubbyBox;
  Map<String, dynamic>? sensorData;
  Timer? sensorDataTimer;
  bool isLoadingSensorData = false;
  bool isInitialized = false;

  // Lighting level ranges (in lux)
  final Map<String, Map<String, int>> lightingRanges = {
    'dim': {'lower': 0, 'upper': 230},
    'neutral': {'lower': 230, 'upper': 370},
    'bright': {'lower': 370, 'upper': 10000}, // High upper limit for bright
  };

  @override
  void initState() {
    super.initState();
    _initializeBoxes();
  }

  @override
  void dispose() {
    sensorDataTimer?.cancel();
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

  // Get current light intensity reading
  String _getCurrentLightIntensity(int cubbyIndex) {
    if (isLoadingSensorData) return 'Loading...';
    if (sensorData == null) return 'No connection';

    final sensorKey = 'light${cubbyIndex + 1}';
    final lightData = sensorData!['environment']?[sensorKey];

    if (lightData != null && 
        lightData['value'] != null && 
        lightData['value'] != 0) {
      final luxValue = lightData['value'];
      final category = _getLightingCategory(luxValue.toDouble());
      return '$luxValue lux ($category)';
    }
    return 'No data';
  }

  // Get brightness percentage
  String _getBrightness(int cubbyIndex) {
    if (isLoadingSensorData) return 'Loading...';
    if (sensorData == null) return 'No connection';

    final sensorKey = 'light${cubbyIndex + 1}';
    final lightData = sensorData!['environment']?[sensorKey];

    if (lightData != null && lightData['brightness'] != null) {
      final brightness = lightData['brightness'];
      return '$brightness%';
    } else if (lightData != null && lightData['value'] != null) {
      // If no brightness field, calculate percentage based on lux value
      final luxValue = lightData['value'];
      final percentage = ((luxValue / 1000.0) * 100).clamp(0, 100).round();
      return '$percentage%';
    }
    return 'No data';
  }

  // Get color temperature (always warm white for now)
  String _getColorTemperature(int cubbyIndex) {
    return 'Warm White';
  }

  // Determine lighting category based on lux value
  String _getLightingCategory(double luxValue) {
    if (luxValue >= lightingRanges['bright']!['lower']!) {
      return 'bright';
    } else if (luxValue >= lightingRanges['neutral']!['lower']!) {
      return 'neutral';
    } else {
      return 'dim';
    }
  }

  // Determine which GIF to show based on lighting conditions
  String _getGifPath(int cubbyIndex) {
    final cubbyNum = cubbyIndex + 1;
    
    // Check if data is loading or unavailable
    if (isLoadingSensorData || sensorData == null) {
      return 'assets/images/gifsEnvironments/lighting/loading${cubbyNum}light.gif';
    }

    // Get current light data directly from sensor data
    final sensorKey = 'light${cubbyIndex + 1}';
    final lightData = sensorData!['environment']?[sensorKey];

    if (lightData == null || 
        lightData['value'] == null || 
        lightData['value'] == 0) {
      return 'assets/images/gifsEnvironments/lighting/loading${cubbyNum}light.gif';
    }
    
    final luxValue = lightData['value'].toDouble();

    // Determine lighting category and return appropriate GIF
    final category = _getLightingCategory(luxValue);
    
    switch (category) {
      case 'dim':
        // For dim lighting, use dark gifs
        return 'assets/images/gifsEnvironments/lighting/dark$cubbyNum.gif';
      case 'neutral':
        return 'assets/images/gifsEnvironments/lighting/neutral$cubbyNum.gif';
      case 'bright':
        // For bright lighting, use bright gifs
        return 'assets/images/gifsEnvironments/lighting/bright$cubbyNum.gif';
      default:
        return 'assets/images/gifsEnvironments/lighting/loading${cubbyNum}light.gif';
    }
  }

  void _onCubbyTapped(int cubbyIndex) {
    setState(() {
      selectedCubby = selectedCubby == cubbyIndex ? null : cubbyIndex;
    });
    
    // Trigger immediate sensor data refresh when a cubby is tapped
    _fetchSensorData();
    
    // Show lighting details for the selected cubby
    _showLightingDetails(cubbyIndex);
  }

  void _showLightingDetails(int cubbyIndex) {
    final plantKey = cubbyBox.get(cubbyIndex);
    final plant = plantKey != null ? plantsBox.get(plantKey) : null;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Cubby ${cubbyIndex + 1} Lighting'),
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
            _buildLightingDataRow(Icons.lightbulb, 'Light Intensity', _getCurrentLightIntensity(cubbyIndex)),
            SizedBox(height: 8),
            _buildLightingDataRow(Icons.brightness_6, 'Brightness', _getBrightness(cubbyIndex)),
            SizedBox(height: 8),
            _buildLightingDataRow(Icons.palette, 'Color Temperature', _getColorTemperature(cubbyIndex)),
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

  Widget _buildLightingDataRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: Color(0xFFFF9800), size: 20),
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
        title: Text('Lighting Monitor'),
        backgroundColor: Color(0xFFFF9800),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Container(
        child: SingleChildScrollView(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'See how lighting is helping your environment grow!',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[700],
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              SizedBox(height: 20),
              // Shelf3D with Lighting GIFs
              LightingShelf3D(
                selectedCubby: selectedCubby,
                onCubbyTapped: _onCubbyTapped,
                sensorData: sensorData,
                isLoadingSensorData: isLoadingSensorData,
                getCurrentLightIntensity: _getCurrentLightIntensity,
                getBrightness: _getBrightness,
                getColorTemperature: _getColorTemperature,
                getGifPath: _getGifPath,
              ),
              SizedBox(height: 20),
              // Text information below the shelf
              _buildLightingInfo(),
              SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLightingInfo() {
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
                    ? Color(0xFFFF9800).withOpacity(0.1) 
                    : Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selectedCubby == i 
                      ? Color(0xFFFF9800) 
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
                      color: Color(0xFFFF9800),
                    ),
                  ),
                  SizedBox(height: 8),
                  _buildLightingDataRow(
                    Icons.lightbulb,
                    'Light Intensity',
                    _getCurrentLightIntensity(i),
                  ),
                  SizedBox(height: 4),
                  _buildLightingDataRow(
                    Icons.brightness_6,
                    'Brightness',
                    _getBrightness(i),
                  ),
                  SizedBox(height: 4),
                  _buildLightingDataRow(
                    Icons.palette,
                    'Color Temperature',
                    _getColorTemperature(i),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// Lighting-specific Shelf3D class
class LightingShelf3D extends StatelessWidget {
  final int? selectedCubby;
  final Function(int) onCubbyTapped;
  final Map<String, dynamic>? sensorData;
  final bool isLoadingSensorData;
  final String Function(int) getCurrentLightIntensity;
  final String Function(int) getBrightness;
  final String Function(int) getColorTemperature;
  final String Function(int) getGifPath;

  const LightingShelf3D({
    Key? key,
    this.selectedCubby,
    required this.onCubbyTapped,
    this.sensorData,
    this.isLoadingSensorData = false,
    required this.getCurrentLightIntensity,
    required this.getBrightness,
    required this.getColorTemperature,
    required this.getGifPath,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final screenHeight = constraints.maxHeight;

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
      child: CustomPaint(painter: LightingShelfPainter(scaleFactor: scaleFactor)),
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
                        Color(0xFFFFE0B2).withOpacity(0.9),
                        Color(0xFFFFCC02).withOpacity(0.95),
                        Color(0xFFFF9800).withOpacity(0.9),
                      ]
                    : [
                        Color(0xFFFFF3E0).withOpacity(0.8),
                        Color(0xFFFFE0B2).withOpacity(0.9),
                        Color(0xFFFFCC02).withOpacity(0.8),
                      ],
                stops: [0.0, 0.5, 1.0],
              ),
              borderRadius: BorderRadius.circular(4 * scaleFactor),
              border: Border.all(
                color: isSelected
                    ? Color(0xFFE65100).withOpacity(0.8)
                    : Color(0xFFFF9800).withOpacity(0.4),
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
                          ? Color(0xFFE65100).withOpacity(0.6)
                          : Color(0xFFFF9800).withOpacity(0.3),
                      width: 1 * scaleFactor,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3 * scaleFactor),
                    child: Container(
                      width: double.infinity,
                      height: double.infinity,
                      child: Image.asset(
                        getGifPath(index),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          // Fallback if GIF doesn't load
                          return Container(
                            color: Color(0xFFFF9800).withOpacity(0.1),
                            child: Center(
                              child: Icon(
                                Icons.lightbulb,
                                size: 20 * scaleFactor,
                                color: Color(0xFFFF9800),
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
                      color: Color(0xFFE65100).withOpacity(0.1),
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

// Lighting-themed shelf painter
class LightingShelfPainter extends CustomPainter {
  final double scaleFactor;

  LightingShelfPainter({required this.scaleFactor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Color(0xFFFF9800)
      ..style = PaintingStyle.fill;

    final darkPaint = Paint()
      ..color = Color(0xFFE65100)
      ..style = PaintingStyle.fill;

    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.25)
      ..style = PaintingStyle.fill;

    final highlightPaint = Paint()
      ..color = Color(0xFFFFD54F)
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

    final glowPaint = Paint()
      ..color = Color(0xFFFFD54F)
      ..strokeWidth = 0.8 * scaleFactor;

    final lightGlowPaint = Paint()
      ..color = Color(0xFFFFF176)
      ..strokeWidth = 0.5 * scaleFactor;

    // Add light glow effects to simulate lighting
    for (double x = 20.0 * scaleFactor; x < 480.0 * scaleFactor; x += 12.0 * scaleFactor) {
      canvas.drawLine(Offset(x, 17.0 * scaleFactor), Offset(x, 23.0 * scaleFactor), glowPaint);
      canvas.drawLine(Offset(x + scaleFactor, 17.0 * scaleFactor), Offset(x + scaleFactor, 23.0 * scaleFactor), lightGlowPaint);
      
      canvas.drawLine(Offset(x, 187.0 * scaleFactor), Offset(x, 193.0 * scaleFactor), glowPaint);
      canvas.drawLine(Offset(x + scaleFactor, 187.0 * scaleFactor), Offset(x + scaleFactor, 193.0 * scaleFactor), lightGlowPaint);
    }

    for (double y = 20.0 * scaleFactor; y < 190.0 * scaleFactor; y += 15.0 * scaleFactor) {
      canvas.drawLine(Offset(17.0 * scaleFactor, y), Offset(23.0 * scaleFactor, y), lightGlowPaint);
      canvas.drawLine(Offset(487.0 * scaleFactor, y), Offset(493.0 * scaleFactor, y), lightGlowPaint);
      canvas.drawLine(Offset(177.0 * scaleFactor, y), Offset(183.0 * scaleFactor, y), lightGlowPaint);
      canvas.drawLine(Offset(337.0 * scaleFactor, y), Offset(343.0 * scaleFactor, y), lightGlowPaint);
    }
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
    return oldDelegate is LightingShelfPainter && oldDelegate.scaleFactor != scaleFactor;
  }
}