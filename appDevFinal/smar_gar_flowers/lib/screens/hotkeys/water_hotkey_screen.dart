import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../../dataModels/esp32_connect.dart';
import '../../dataModels/plant.dart';

class WaterHotkeyScreen extends StatefulWidget {
  const WaterHotkeyScreen({Key? key}) : super(key: key);

  @override
  State<WaterHotkeyScreen> createState() => _WaterHotkeyScreenState();
}

class _WaterHotkeyScreenState extends State<WaterHotkeyScreen> {
  int? selectedCubby;
  late Box<ESP32Connection> esp32Box;
  late Box<Plant> plantsBox;
  late Box<int> cubbyBox;
  Map<String, dynamic>? sensorData;
  Timer? sensorDataTimer;
  bool isLoadingSensorData = false;
  bool isInitialized = false;

  // Cubby-specific soil moisture calibration ranges by soil type (copied from environment screen)
  final Map<int, Map<String, Map<String, Map<String, int>>>> cubbyMoistureRanges = {
    0: { // Cubby 1 (left)
      'coarse': {
        'drenched': {'lower': 0, 'upper': 1614},
        'wet': {'lower': 1615, 'upper': 1925},
        'moist': {'lower': 1926, 'upper': 2235},
        'dry': {'lower': 2236, 'upper': 4095},
      },
      'rough': {
        'drenched': {'lower': 0, 'upper': 1534},
        'wet': {'lower': 1535, 'upper': 1819},
        'moist': {'lower': 1820, 'upper': 2099},
        'dry': {'lower': 2100, 'upper': 4095},
      },
      'normal': {
        'drenched': {'lower': 0, 'upper': 1524},
        'wet': {'lower': 1525, 'upper': 1680},
        'moist': {'lower': 1681, 'upper': 1839},
        'dry': {'lower': 1840, 'upper': 4095},
      },
      'fine': {
        'drenched': {'lower': 0, 'upper': 1519},
        'wet': {'lower': 1520, 'upper': 1764},
        'moist': {'lower': 1765, 'upper': 2004},
        'dry': {'lower': 2005, 'upper': 4095},
      },
    },
    1: { // Cubby 2 (middle)
      'coarse': {
        'drenched': {'lower': 0, 'upper': 574},
        'wet': {'lower': 575, 'upper': 900},
        'moist': {'lower': 901, 'upper': 1475},
        'dry': {'lower': 1476, 'upper': 4095},
      },
      'rough': {
        'drenched': {'lower': 0, 'upper': 456},
        'wet': {'lower': 457, 'upper': 710},
        'moist': {'lower': 711, 'upper': 954},
        'dry': {'lower': 955, 'upper': 4095},
      },
      'normal': {
        'drenched': {'lower': 0, 'upper': 464},
        'wet': {'lower': 465, 'upper': 715},
        'moist': {'lower': 716, 'upper': 959},
        'dry': {'lower': 960, 'upper': 4095},
      },
      'fine': {
        'drenched': {'lower': 0, 'upper': 464},
        'wet': {'lower': 465, 'upper': 635},
        'moist': {'lower': 636, 'upper': 799},
        'dry': {'lower': 800, 'upper': 4095},
      },
    },
    2: { // Cubby 3 (right)
      'coarse': {
        'drenched': {'lower': 0, 'upper': 1711},
        'wet': {'lower': 1712, 'upper': 2040},
        'moist': {'lower': 2041, 'upper': 2364},
        'dry': {'lower': 2365, 'upper': 4095},
      },
      'rough': {
        'drenched': {'lower': 0, 'upper': 764},
        'wet': {'lower': 765, 'upper': 1440},
        'moist': {'lower': 1441, 'upper': 2109},
        'dry': {'lower': 2110, 'upper': 4095},
      },
      'normal': {
        'drenched': {'lower': 0, 'upper': 1614},
        'wet': {'lower': 1615, 'upper': 1830},
        'moist': {'lower': 1831, 'upper': 2039},
        'dry': {'lower': 2040, 'upper': 4095},
      },
      'fine': {
        'drenched': {'lower': 0, 'upper': 1654},
        'wet': {'lower': 1655, 'upper': 1885},
        'moist': {'lower': 1886, 'upper': 2114},
        'dry': {'lower': 2115, 'upper': 4095},
      },
    },
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

  // Use the same soil moisture reading logic as environment screen
  String _getCurrentSoilMoisture(int cubbyIndex) {
    if (isLoadingSensorData) return 'Loading...';
    if (sensorData == null) return 'No connection';

    final sensorKey = 'sensor${cubbyIndex + 1}';
    final soilData = sensorData!['soil']?[sensorKey];

    if (soilData != null && soilData['value'] != null) {
      final status = soilData['status']?.toString() ?? 'Unknown';
      final value = soilData['value'];
      return '$status ($value)';
    }
    return 'No data';
  }

  // Get desired soil moisture range for the assigned plant
  String _getDesiredSoilMoisture(int cubbyIndex) {
    final plantKey = cubbyBox.get(cubbyIndex);
    if (plantKey == null) return 'No plant assigned';
    
    final plant = plantsBox.get(plantKey);
    if (plant == null) return 'Plant not found';
    
    if (plant.idealMoisture == null) return 'Unknown';
    
    final range = _parseMoistureToRange(plant.idealMoisture!, cubbyIndex, plant.soilType ?? 'normal');
    return '${plant.idealMoisture} (${range['lower']}-${range['upper']})';
  }

  // Copy moisture parsing logic from environment screen
  Map<String, int> _parseMoistureToRange(String moisture, int cubbyIndex, [String soilType = 'normal']) {
    moisture = moisture.toLowerCase().trim();
    soilType = soilType.toLowerCase().trim();

    final cubbyRanges = cubbyMoistureRanges[cubbyIndex];
    if (cubbyRanges == null) {
      return _parseMoistureToRange(moisture, 1, soilType);
    }

    final soilTypeRanges = cubbyRanges[soilType];
    if (soilTypeRanges == null) {
      final normalSoilRanges = cubbyRanges['normal'];
      if (normalSoilRanges == null) {
        return _parseMoistureToRange(moisture, 1, 'normal');
      }
      return _getMoistureRangeFromSoilData(moisture, normalSoilRanges, cubbyIndex, 'normal');
    }

    return _getMoistureRangeFromSoilData(moisture, soilTypeRanges, cubbyIndex, soilType);
  }

  Map<String, int> _getMoistureRangeFromSoilData(
    String moisture, 
    Map<String, Map<String, int>> soilData, 
    int cubbyIndex, 
    String soilType
  ) {
    if (moisture.contains('drenched')) {
      return soilData['drenched']!;
    }
    if (moisture.contains('wet')) {
      return soilData['wet']!;
    }
    if (moisture.contains('moist')) {
      return soilData['moist']!;
    }
    if (moisture.contains('dry')) {
      return soilData['dry']!;
    }
    if (moisture.contains('normal')) {
      return soilData['moist']!;
    }

    return soilData['moist']!;
  }

  // Determine the actual moisture category based on current value and calibration ranges
  String _getActualMoistureCategory(int currentValue, int cubbyIndex, String soilType) {
    final cubbyRanges = cubbyMoistureRanges[cubbyIndex];
    if (cubbyRanges == null) return 'dry';
    
    final soilTypeRanges = cubbyRanges[soilType.toLowerCase().trim()];
    if (soilTypeRanges == null) {
      final normalRanges = cubbyRanges['normal'];
      if (normalRanges == null) return 'dry';
      return _determineCategoryFromRanges(currentValue, normalRanges);
    }
    
    return _determineCategoryFromRanges(currentValue, soilTypeRanges);
  }
  
  String _determineCategoryFromRanges(int currentValue, Map<String, Map<String, int>> ranges) {
    for (final entry in ranges.entries) {
      final category = entry.key;
      final range = entry.value;
      final lower = range['lower'] ?? 0;
      final upper = range['upper'] ?? 4095;
      
      if (currentValue >= lower && currentValue <= upper) {
        return category;
      }
    }
    return 'dry'; // fallback
  }

  // Determine which GIF to show based on soil moisture conditions
  String _getGifPath(int cubbyIndex) {
    final cubbyNum = cubbyIndex + 1;
    
    // Get the current moisture reading
    final currentMoisture = _getCurrentSoilMoisture(cubbyIndex);
    
    // Check if data is actually loading or unavailable
    if (currentMoisture == 'Loading...' || 
        currentMoisture == 'No connection' || 
        currentMoisture == 'No data') {
      return 'assets/images/gifsEnvironments/soilMoist/loading$cubbyNum.gif';
    }

    // Extract current moisture value from the reading (e.g., "2373" from "normal (2373)")
    final currentValueMatch = RegExp(r'\((\d+)\)').firstMatch(currentMoisture);
    if (currentValueMatch == null) {
      return 'assets/images/gifsEnvironments/soilMoist/loading$cubbyNum.gif';
    }
    
    final currentValue = int.tryParse(currentValueMatch.group(1)!);
    if (currentValue == null) {
      return 'assets/images/gifsEnvironments/soilMoist/loading$cubbyNum.gif';
    }

    // Get plant data to determine soil type
    final plantKey = cubbyBox.get(cubbyIndex);
    if (plantKey == null) {
      return 'assets/images/gifsEnvironments/soilMoist/loading$cubbyNum.gif';
    }
    
    final plant = plantsBox.get(plantKey);
    if (plant == null) {
      return 'assets/images/gifsEnvironments/soilMoist/loading$cubbyNum.gif';
    }
    
    final soilType = plant.soilType ?? 'normal';
    
    // Determine actual moisture category based on current value and calibration ranges
    final actualCategory = _getActualMoistureCategory(currentValue, cubbyIndex, soilType);
    
    // Show appropriate GIF based on moisture category
    // drenched, wet, moist = wet gif
    // dry = dry gif
    if (actualCategory == 'drenched' || 
        actualCategory == 'wet' || 
        actualCategory == 'moist') {
      return 'assets/images/gifsEnvironments/soilMoist/wet$cubbyNum.gif';
    } else if (actualCategory == 'dry') {
      return 'assets/images/gifsEnvironments/soilMoist/dry$cubbyNum.gif';
    } else {
      // Fallback for any unknown category
      return 'assets/images/gifsEnvironments/soilMoist/loading$cubbyNum.gif';
    }
  }

  void _onCubbyTapped(int cubbyIndex) {
    setState(() {
      selectedCubby = selectedCubby == cubbyIndex ? null : cubbyIndex;
    });
    
    // Trigger immediate sensor data refresh when a cubby is tapped
    _fetchSensorData();
    
    // Show soil moisture details for the selected cubby
    _showSoilMoistureDetails(cubbyIndex);
  }

  void _showSoilMoistureDetails(int cubbyIndex) {
    final plantKey = cubbyBox.get(cubbyIndex);
    final plant = plantKey != null ? plantsBox.get(plantKey) : null;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Cubby ${cubbyIndex + 1} Soil Moisture'),
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
            _buildSoilDataRow(Icons.water_drop, 'Current Soil Moisture', _getCurrentSoilMoisture(cubbyIndex)),
            SizedBox(height: 12),
            _buildSoilDataRow(Icons.eco, 'Desired Soil Moisture', _getDesiredSoilMoisture(cubbyIndex)),
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

  Widget _buildSoilDataRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: Color(0xFF1976D2), size: 20),
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
        title: Text('Soil Moisture Monitor'),
        backgroundColor: Color(0xFF1976D2),
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
                  'See how moisture is helping your environment thrive!',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[700],
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              SizedBox(height: 20),
              // Updated Shelf3D with GIFs
              Shelf3D(
                selectedCubby: selectedCubby,
                onCubbyTapped: _onCubbyTapped,
                sensorData: sensorData,
                isLoadingSensorData: isLoadingSensorData,
                getCurrentSoilMoisture: _getCurrentSoilMoisture,
                getDesiredSoilMoisture: _getDesiredSoilMoisture,
                getGifPath: _getGifPath,
              ),
              SizedBox(height: 20),
              // Text information below the shelf
              _buildSoilMoistureInfo(),
              SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSoilMoistureInfo() {
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
                    ? Color(0xFF1976D2).withOpacity(0.1) 
                    : Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selectedCubby == i 
                      ? Color(0xFF1976D2) 
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
                      color: Color(0xFF1976D2),
                    ),
                  ),
                  SizedBox(height: 8),
                  _buildSoilDataRow(
                    Icons.water_drop,
                    'Current Moisture',
                    _getCurrentSoilMoisture(i),
                  ),
                  SizedBox(height: 4),
                  _buildSoilDataRow(
                    Icons.eco,
                    'Desired Moisture',
                    _getDesiredSoilMoisture(i),
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

// Updated Shelf3D class to display GIFs instead of text
class Shelf3D extends StatelessWidget {
  final int? selectedCubby;
  final Function(int) onCubbyTapped;
  final Map<String, dynamic>? sensorData;
  final bool isLoadingSensorData;
  final String Function(int) getCurrentSoilMoisture;
  final String Function(int) getDesiredSoilMoisture;
  final String Function(int) getGifPath;

  const Shelf3D({
    Key? key,
    this.selectedCubby,
    required this.onCubbyTapped,
    this.sensorData,
    this.isLoadingSensorData = false,
    required this.getCurrentSoilMoisture,
    required this.getDesiredSoilMoisture,
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
      child: CustomPaint(painter: ShelfPainter(scaleFactor: scaleFactor)),
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
                        Color(0xFFB3E5FC).withOpacity(0.9),
                        Color(0xFF81D4FA).withOpacity(0.95),
                        Color(0xFF4FC3F7).withOpacity(0.9),
                      ]
                    : [
                        Color(0xFFE1F5FE).withOpacity(0.8),
                        Color(0xFFB3E5FC).withOpacity(0.9),
                        Color(0xFF81D4FA).withOpacity(0.8),
                      ],
                stops: [0.0, 0.5, 1.0],
              ),
              borderRadius: BorderRadius.circular(4 * scaleFactor),
              border: Border.all(
                color: isSelected
                    ? Color(0xFF0277BD).withOpacity(0.8)
                    : Color(0xFF0288D1).withOpacity(0.4),
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
                // GIF Container (replaces the blue inner box)
                Container(
                  margin: EdgeInsets.all(8 * scaleFactor),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4 * scaleFactor),
                    border: Border.all(
                      color: isSelected
                          ? Color(0xFF0277BD).withOpacity(0.6)
                          : Color(0xFF0288D1).withOpacity(0.3),
                      width: 1 * scaleFactor,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3 * scaleFactor),
                    child: Container(
                      width: double.infinity,
                      height: double.infinity,
                      child: getGifPath(index).endsWith('wet1.gif')
                          ? Align(
                              alignment: Alignment(-4.0, 0.0), // Far left alignment so right edge aligns with left side of box
                              child: Image.asset(
                                getGifPath(index),
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  // Fallback if GIF doesn't load
                                  return Container(
                                    color: Color(0xFF1976D2).withOpacity(0.1),
                                    child: Center(
                                      child: Icon(
                                        Icons.water_drop,
                                        size: 20 * scaleFactor,
                                        color: Color(0xFF1976D2),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            )
                          : Image.asset(
                              getGifPath(index),
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                // Fallback if GIF doesn't load
                                return Container(
                                  color: Color(0xFF1976D2).withOpacity(0.1),
                                  child: Center(
                                    child: Icon(
                                      Icons.water_drop,
                                      size: 20 * scaleFactor,
                                      color: Color(0xFF1976D2),
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
                      color: Color(0xFF0277BD).withOpacity(0.1),
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

// Keep the same painters as before
class ShelfPainter extends CustomPainter {
  final double scaleFactor;

  ShelfPainter({required this.scaleFactor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Color(0xFF0288D1)
      ..style = PaintingStyle.fill;

    final darkPaint = Paint()
      ..color = Color(0xFF0277BD)
      ..style = PaintingStyle.fill;

    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.25)
      ..style = PaintingStyle.fill;

    final highlightPaint = Paint()
      ..color = Color(0xFF03DAC6)
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

    final flowPaint = Paint()
      ..color = Color(0xFF0277BD)
      ..strokeWidth = 0.8 * scaleFactor;

    final lightFlowPaint = Paint()
      ..color = Color(0xFF03DAC6)
      ..strokeWidth = 0.5 * scaleFactor;

    for (double x = 20.0 * scaleFactor; x < 480.0 * scaleFactor; x += 12.0 * scaleFactor) {
      canvas.drawLine(Offset(x, 17.0 * scaleFactor), Offset(x, 23.0 * scaleFactor), flowPaint);
      canvas.drawLine(Offset(x + scaleFactor, 17.0 * scaleFactor), Offset(x + scaleFactor, 23.0 * scaleFactor), lightFlowPaint);
      
      canvas.drawLine(Offset(x, 187.0 * scaleFactor), Offset(x, 193.0 * scaleFactor), flowPaint);
      canvas.drawLine(Offset(x + scaleFactor, 187.0 * scaleFactor), Offset(x + scaleFactor, 193.0 * scaleFactor), lightFlowPaint);
    }

    for (double y = 20.0 * scaleFactor; y < 190.0 * scaleFactor; y += 15.0 * scaleFactor) {
      canvas.drawLine(Offset(17.0 * scaleFactor, y), Offset(23.0 * scaleFactor, y), lightFlowPaint);
      canvas.drawLine(Offset(487.0 * scaleFactor, y), Offset(493.0 * scaleFactor, y), lightFlowPaint);
      canvas.drawLine(Offset(177.0 * scaleFactor, y), Offset(183.0 * scaleFactor, y), lightFlowPaint);
      canvas.drawLine(Offset(337.0 * scaleFactor, y), Offset(343.0 * scaleFactor, y), lightFlowPaint);
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
    return oldDelegate is ShelfPainter && oldDelegate.scaleFactor != scaleFactor;
  }
}

class WaterEffectPainter extends CustomPainter {
  final double scaleFactor;

  WaterEffectPainter({required this.scaleFactor});

  @override
  void paint(Canvas canvas, Size size) {
    final waterPaint = Paint()
      ..color = Color(0xFF0288D1).withOpacity(0.3)
      ..strokeWidth = 0.5 * scaleFactor;

    final lightWaterPaint = Paint()
      ..color = Color(0xFF03DAC6).withOpacity(0.2)
      ..strokeWidth = 0.3 * scaleFactor;

    for (double y = 5 * scaleFactor; y < size.height - (5 * scaleFactor); y += 8 * scaleFactor) {
      canvas.drawLine(Offset(5 * scaleFactor, y), Offset(size.width - (5 * scaleFactor), y), waterPaint);
      canvas.drawLine(Offset(5 * scaleFactor, y + scaleFactor), Offset(size.width - (5 * scaleFactor), y + scaleFactor), lightWaterPaint);
    }

    for (double x = 10 * scaleFactor; x < size.width - (10 * scaleFactor); x += 40 * scaleFactor) {
      canvas.drawLine(Offset(x, 5 * scaleFactor), Offset(x, size.height - (5 * scaleFactor)), waterPaint);
    }

    final dropletPaint = Paint()
      ..color = Color(0xFF0288D1).withOpacity(0.4)
      ..style = PaintingStyle.fill;

    for (double x = 15 * scaleFactor; x < size.width - (15 * scaleFactor); x += 25 * scaleFactor) {
      for (double y = 15 * scaleFactor; y < size.height - (15 * scaleFactor); y += 30 * scaleFactor) {
        canvas.drawCircle(Offset(x, y), 1.5 * scaleFactor, dropletPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return oldDelegate is WaterEffectPainter && oldDelegate.scaleFactor != scaleFactor;
  }
}