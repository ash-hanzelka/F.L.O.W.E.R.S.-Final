import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'dart:io';
import '../../dataModels/plant.dart';
import '../../dataModels/esp32_connect.dart';

class EnvironmentScreen extends StatefulWidget {
  const EnvironmentScreen({Key? key}) : super(key: key);

  @override
  _EnvironmentScreenState createState() => _EnvironmentScreenState();
}

class _EnvironmentScreenState extends State<EnvironmentScreen>
    with TickerProviderStateMixin {
  final Box<Plant> plantsBox = Hive.box<Plant>('plantsBox');
  final Box<int> cubbyBox = Hive.box<int>('cubbyAssignments');
  late Box<ESP32Connection> esp32Box;
  int? selectedCubby;
  Map<String, dynamic>? sensorData;
  Timer? sensorDataTimer;
  bool isLoadingSensorData = false;

  // Animation controllers for instruction text
  late AnimationController _instructionController;
  late Animation<double> _instructionOpacity;
  Timer? _instructionTimer;
  bool _showTapInstruction = true;

  // Cubby-specific soil moisture calibration ranges by soil type
  final Map<int, Map<String, Map<String, Map<String, int>>>>
  cubbyMoistureRanges = {
    0: {
      // Cubby 1 (left)
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
    1: {
      // Cubby 2 (middle)
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
    2: {
      // Cubby 3 (right)
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
    _initializeESP32Box();

    // Initialize animation controller for instruction text
    _instructionController = AnimationController(
      duration: Duration(milliseconds: 1000),
      vsync: this,
    );

    _instructionOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _instructionController, curve: Curves.easeInOut),
    );

    _startInstructionCycle();
  }

  void _startInstructionCycle() {
    _instructionController.forward();
    _instructionTimer = Timer.periodic(Duration(seconds: 3), (timer) {
      _instructionController.reverse().then((_) {
        setState(() {
          _showTapInstruction = !_showTapInstruction;
        });
        _instructionController.forward();
      });
    });
  }

  // Get full path from filename
  Future<String?> _getFullImagePath(String? fileName) async {
    if (fileName == null || fileName.isEmpty) return null;

    final appDir = await getApplicationDocumentsDirectory();
    final imageDir = path.join(appDir.path, 'plant_images');
    final fullPath = path.join(imageDir, fileName);

    if (await File(fullPath).exists()) {
      return fullPath;
    }

    return null;
  }

  Future<void> _initializeESP32Box() async {
    try {
      esp32Box = await Hive.openBox<ESP32Connection>('esp32_connection');
      await _fetchSensorData();
      _startPeriodicSensorDataUpdate();
    } catch (e) {
      print('Error initializing ESP32 box: $e');
    }
  }

  @override
  void dispose() {
    sensorDataTimer?.cancel();
    _instructionTimer?.cancel();
    _instructionController.dispose();
    super.dispose();
  }

  void _startPeriodicSensorDataUpdate() {
    sensorDataTimer = Timer.periodic(Duration(seconds: 10), (timer) {
      if (selectedCubby != null) {
        _fetchSensorData();
      }
    });
  }

  Future<void> _fetchSensorData() async {
    if (esp32Box.isEmpty) {
      print('ESP32 box is empty');
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

  Future<void> _sendCubbyDataToESP32() async {
    if (esp32Box.isEmpty) {
      print('ESP32 box is empty');
      return;
    }

    final esp32 = esp32Box.getAt(0);
    if (esp32 == null || esp32.ipAddress == null || esp32.ipAddress!.isEmpty) {
      print('No ESP32 device configured or no IP address');
      return;
    }

    final url = Uri.parse('http://${esp32.ipAddress}/cubbies');

    try {
      final cubbyData = {
        'cubby1': _getCubbyDataForESP32(0),
        'cubby2': _getCubbyDataForESP32(1),
        'cubby3': _getCubbyDataForESP32(2),
      };

      print('Sending cubby data to ESP32: ${jsonEncode(cubbyData)}');

      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(cubbyData),
          )
          .timeout(Duration(seconds: 5));

      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        print('Successfully updated cubby data on ESP32');
        await _verifyCubbyData();
      } else {
        print('Failed to update cubby data. Status: ${response.statusCode}');
      }
    } catch (e) {
      print('Error sending cubby data to ESP32: $e');
    }
  }

  Future<void> _verifyCubbyData() async {
    if (esp32Box.isEmpty) return;

    final esp32 = esp32Box.getAt(0);
    if (esp32 == null || esp32.ipAddress == null) return;

    final url = Uri.parse('http://${esp32.ipAddress}/cubbies');

    try {
      final response = await http.get(url).timeout(Duration(seconds: 3));
      print('Current cubby data on ESP32: ${response.body}');
    } catch (e) {
      print('Error verifying cubby data: $e');
    }
  }

  // Updated method to return the new format with separate lower/upper values
  Map<String, dynamic> _getCubbyDataForESP32(int cubbyIndex) {
    final plantKey = cubbyBox.get(cubbyIndex);
    if (plantKey == null) {
      return {
        'lightLower': 0,
        'lightUpper': 0,
        'soilLower': 0,
        'soilUpper': 0,
        'humidityLower': 0,
        'humidityUpper': 0,
        'temperatureLower': 0,
        'temperatureUpper': 0,
      };
    }

    final plant = plantsBox.get(plantKey);
    if (plant == null) {
      return {
        'lightLower': 0,
        'lightUpper': 0,
        'soilLower': 0,
        'soilUpper': 0,
        'humidityLower': 0,
        'humidityUpper': 0,
        'temperatureLower': 0,
        'temperatureUpper': 0,
      };
    }

    Map<String, int> lightRange = _parseLightToRange(
      plant.idealLighting ?? 'neutral',
    );
    // Updated to use cubby-specific soil moisture ranges with soil type
    // You can get soil type from plant data if available, otherwise defaults to 'normal'
    String soilType =
        plant.soilType ??
        'normal'; // Assuming you have a soilType field in Plant model
    Map<String, int> soilRange = _parseMoistureToRange(
      plant.idealMoisture ?? 'moist',
      cubbyIndex, // Pass the cubby index for calibration
      soilType, // Pass the soil type for specific calibration
    );
    Map<String, int> humidityRange = _parseHumidityToRange(
      plant.idealHumidity ?? '60%',
    );
    Map<String, int> tempRange = _parseTemperatureToRange(
      plant.idealTemp ?? '70°F',
    );

    return {
      'lightLower': lightRange['lower']!,
      'lightUpper': lightRange['upper']!,
      'soilLower': soilRange['lower']!,
      'soilUpper': soilRange['upper']!,
      'humidityLower': humidityRange['lower']!,
      'humidityUpper': humidityRange['upper']!,
      'temperatureLower': tempRange['lower']!,
      'temperatureUpper': tempRange['upper']!,
    };
  }

  Map<String, int> _parseLightToRange(String light) {
    light = light.toLowerCase().trim();
    print('Parsing light: "$light"');

    // dim: < 230 lux, neutral: 230-370 lux, bright: > 370 lux
    if (light.contains('dim')) {
      return {'lower': 100, 'upper': 230}; // 0-230 range
    }
    if (light.contains('neutral') || light.contains('medium')) {
      return {'lower': 230, 'upper': 370}; // 230-370 range
    }
    if (light.contains('bright')) {
      return {'lower': 370, 'upper': 1000}; // 370-1000+ range
    }

    print('Unknown light value: "$light", using default neutral range 230-370');
    return {'lower': 230, 'upper': 370};
  }

  // Updated to use cubby-specific calibrated ranges with soil type
  Map<String, int> _parseMoistureToRange(
    String moisture,
    int cubbyIndex, [
    String soilType = 'normal',
  ]) {
    moisture = moisture.toLowerCase().trim();
    soilType = soilType.toLowerCase().trim();
    print(
      'Parsing moisture: "$moisture" for cubby $cubbyIndex with soil type "$soilType"',
    );

    // Get the calibrated ranges for this specific cubby
    final cubbyRanges = cubbyMoistureRanges[cubbyIndex];
    if (cubbyRanges == null) {
      print('No calibration data for cubby $cubbyIndex, using default ranges');
      // Fallback to cubby 1 ranges if no calibration data exists
      return _parseMoistureToRange(moisture, 1, soilType);
    }

    // Get the soil type ranges for this cubby
    final soilTypeRanges = cubbyRanges[soilType];
    if (soilTypeRanges == null) {
      print(
        'No calibration data for soil type "$soilType" in cubby $cubbyIndex, using normal soil',
      );
      final normalSoilRanges = cubbyRanges['normal'];
      if (normalSoilRanges == null) {
        print('No normal soil data for cubby $cubbyIndex, using cubby 1');
        return _parseMoistureToRange(moisture, 1, 'normal');
      }
      return _getMoistureRangeFromSoilData(
        moisture,
        normalSoilRanges,
        cubbyIndex,
        'normal',
      );
    }

    return _getMoistureRangeFromSoilData(
      moisture,
      soilTypeRanges,
      cubbyIndex,
      soilType,
    );
  }

  // Helper method to extract moisture range from soil data
  Map<String, int> _getMoistureRangeFromSoilData(
    String moisture,
    Map<String, Map<String, int>> soilData,
    int cubbyIndex,
    String soilType,
  ) {
    // Match moisture level to calibrated range
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

    // Handle generic terms
    if (moisture.contains('normal')) {
      return soilData['moist']!; // Default to moist range
    }

    print(
      'Unknown moisture value: "$moisture", using default moist range for cubby $cubbyIndex with $soilType soil',
    );
    return soilData['moist']!;
  }

  Map<String, int> _parseHumidityToRange(String humidity) {
    humidity = humidity.toLowerCase().trim();
    print('Parsing humidity: "$humidity"');

    // Parse percentage if present
    final regex = RegExp(r'(\d+)%?');
    final match = regex.firstMatch(humidity);

    if (match != null) {
      final value = int.parse(match.group(1)!);
      // Create a range of ±10% around the target value
      final lower = (value - 10).clamp(0, 100);
      final upper = (value + 10).clamp(0, 100);
      return {'lower': lower, 'upper': upper};
    }

    // Handle descriptive terms
    // dry: 0-35%, normal: 35-70%, humid: 70-100%
    if (humidity.contains('dry')) {
      return {'lower': 0, 'upper': 35}; // 0-35 range
    }
    if (humidity.contains('normal') || humidity.contains('medium')) {
      return {'lower': 35, 'upper': 70}; // 35-70 range
    }
    if (humidity.contains('humid') || humidity.contains('high')) {
      return {'lower': 70, 'upper': 100}; // 70-100 range
    }

    print(
      'Unknown humidity value: "$humidity", using default normal range 35-70',
    );
    return {'lower': 35, 'upper': 70};
  }

  // Updated to return a range instead of single value
  Map<String, int> _parseTemperatureToRange(String temp) {
    temp = temp.trim();
    print('Parsing temperature: "$temp"');

    // Handle explicit ranges first
    if (temp.contains('-')) {
      final parts = temp.split('-');
      if (parts.length == 2) {
        try {
          // Convert Fahrenheit to Celsius for the ESP32
          final minF = double.parse(parts[0].trim());
          final maxF = double.parse(parts[1].trim());
          final minC = ((minF - 32) * 5 / 9).round();
          final maxC = ((maxF - 32) * 5 / 9).round();
          print('Temperature range $minF-$maxF°F ($minC-$maxC°C)');
          return {'lower': minC, 'upper': maxC};
        } catch (e) {
          print('Error parsing temperature range: $e');
        }
      }
    }

    // Parse descriptive temperature terms
    if (temp.toLowerCase().contains('cold')) {
      // ~60-69°F (15.5-20.5°C)
      return {'lower': 15, 'upper': 20};
    }
    if (temp.toLowerCase().contains('warm')) {
      // ~70-80°F (21-26.5°C)
      return {'lower': 21, 'upper': 26};
    }
    if (temp.toLowerCase().contains('hot')) {
      // ~81-90°F (27-32°C)
      return {'lower': 27, 'upper': 32};
    }

    // Parse numeric temperature (assumed to be Fahrenheit)
    final regex = RegExp(r'(\d+)');
    final match = regex.firstMatch(temp);
    if (match != null) {
      final valueF = int.parse(match.group(1)!);
      // Convert to Celsius and create range ±2°F (~±1°C)
      final valueC = ((valueF - 32) * 5 / 9).round();
      print(
        'Parsed single temperature: $valueF°F ($valueC°C), creating range ±1°C',
      );
      return {'lower': valueC - 1, 'upper': valueC + 1};
    }

    print(
      'Unknown temperature format: "$temp", using default range 70-80°F (21-26°C)',
    );
    return {'lower': 21, 'upper': 26}; // Default warm range in Celsius
  }

  void _assignPlantToCubby(int cubbyIndex, int plantKey) async {
    await cubbyBox.put(cubbyIndex, plantKey);
    setState(() {});
    await Future.delayed(Duration(milliseconds: 100));
    await _sendCubbyDataToESP32();
  }

  void _clearCubby(int cubbyIndex) {
    cubbyBox.delete(cubbyIndex);
    setState(() {});
    _sendCubbyDataToESP32();
  }

  void _onCubbyTapped(int cubbyIndex) {
    setState(() {
      selectedCubby = selectedCubby == cubbyIndex ? null : cubbyIndex;
    });
    if (selectedCubby == cubbyIndex) {
      _fetchSensorData();
    }
  }

  void _showPlantAssignmentDialog(int cubbyIndex) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Assign Plant to Cubby ${cubbyIndex + 1}'),
          content: Container(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (cubbyBox.get(cubbyIndex) != null) ...[
                  Text('Currently assigned:'),
                  Text(
                    plantsBox.get(cubbyBox.get(cubbyIndex)!)?.commonName ??
                        'Unknown',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      _clearCubby(cubbyIndex);
                      Navigator.pop(context);
                    },
                    child: Text('Clear Assignment'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  SizedBox(height: 16),
                  Text('Or choose a different plant:'),
                ],
                Container(
                  height: 200,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: plantsBox.keys.length,
                    itemBuilder: (context, index) {
                      final plantKey = plantsBox.keys.elementAt(index);
                      final plant = plantsBox.get(plantKey);

                      return ListTile(
                        title: Text(plant?.commonName ?? 'Unknown'),
                        subtitle: Text(plant?.scientificName ?? ''),
                        onTap: () {
                          _assignPlantToCubby(cubbyIndex, plantKey);
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

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

  String _getCurrentTemperature(int cubbyIndex) {
    if (isLoadingSensorData) return 'Loading...';
    if (sensorData == null) return 'No connection';

    final sensorKey = 'temperature${cubbyIndex + 1}';
    final tempData = sensorData!['environment']?[sensorKey];

    if (tempData != null &&
        tempData['value'] != null &&
        tempData['value'] != 0) {
      // Convert Celsius to Fahrenheit and round to 2 decimal places
      final celsius = tempData['value'].toDouble();
      final fahrenheit = (celsius * 9 / 5) + 32;
      return '${fahrenheit.toStringAsFixed(2)}°F';
    }
    return 'No data';
  }

  String _getCurrentHumidity(int cubbyIndex) {
    if (isLoadingSensorData) return 'Loading...';
    if (sensorData == null) return 'No connection';

    final sensorKey = 'humidity${cubbyIndex + 1}';
    final humidityData = sensorData!['environment']?[sensorKey];

    if (humidityData != null &&
        humidityData['value'] != null &&
        humidityData['value'] != 0) {
      // Round humidity to 2 decimal places
      return '${humidityData['value'].toStringAsFixed(2)}%';
    }
    return 'No data';
  }

  String _getCurrentLight(int cubbyIndex) {
    if (isLoadingSensorData) return 'Loading...';
    if (sensorData == null) return 'No connection';

    final sensorKey = 'light${cubbyIndex + 1}';
    final lightData = sensorData!['environment']?[sensorKey];

    if (lightData != null &&
        lightData['value'] != null &&
        lightData['value'] != 0) {
      return '${lightData['value']} lux';
    }
    return 'No data';
  }

  // Helper method to get ideal ranges for display - updated to use cubby-specific ranges
  String _getIdealSoilRange(
    String? idealMoisture,
    int cubbyIndex, [
    String? soilType,
  ]) {
    if (idealMoisture == null) return 'Unknown';
    final range = _parseMoistureToRange(
      idealMoisture,
      cubbyIndex,
      soilType ?? 'normal',
    );
    return '${range['lower']}-${range['upper']}';
  }

  String _getIdealTempRange(String? idealTemp) {
    if (idealTemp == null) return 'Unknown';
    final range = _parseTemperatureToRange(idealTemp);
    // Convert Celsius back to Fahrenheit for display
    final lowerF = (range['lower']! * 9 / 5) + 32;
    final upperF = (range['upper']! * 9 / 5) + 32;
    return '${lowerF.toStringAsFixed(0)}-${upperF.toStringAsFixed(0)}°F';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Your Environment'),
        backgroundColor: Color(0xFF408661),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF5F5F5), Color(0xFFE0E0E0)],
          ),
        ),
        child: Stack(
          children: [
            // Instruction text overlay
            AnimatedBuilder(
              animation: _instructionOpacity,
              builder: (context, child) {
                return Positioned(
                  top: 20,
                  left: 0,
                  right: 0,
                  child: Opacity(
                    opacity: _instructionOpacity.value,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        _showTapInstruction
                            ? 'Single tap to view details'
                            : 'Double tap to reassign plants',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF408661),
                          shadows: [
                            Shadow(
                              offset: Offset(0, 1),
                              blurRadius: 2,
                              color: Colors.white.withOpacity(0.8),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),

            AnimatedPositioned(
              duration: Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              top: selectedCubby != null
                  ? 10
                  : 60, // Adjusted to account for instruction text
              left: 0,
              right: 0,
              bottom: selectedCubby != null ? 350 : 0,
              child: Shelf3D(
                selectedCubby: selectedCubby,
                onCubbyTapped: _onCubbyTapped,
                onCubbyDoubleTapped: _showPlantAssignmentDialog,
                plantsBox: plantsBox,
                cubbyBox: cubbyBox,
                getFullImagePath:
                    _getFullImagePath, // Pass the image path function
              ),
            ),

            if (selectedCubby != null) ...[
              AnimatedPositioned(
                duration: Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                bottom: 0,
                left: 0,
                right: 0,
                height: 350,
                child: PlantCard(
                  cubbyIndex: selectedCubby!,
                  plantsBox: plantsBox,
                  cubbyBox: cubbyBox,
                  getCurrentSoilMoisture: _getCurrentSoilMoisture,
                  getCurrentTemperature: _getCurrentTemperature,
                  getCurrentHumidity: _getCurrentHumidity,
                  getCurrentLight: _getCurrentLight,
                  getIdealSoilRange: _getIdealSoilRange,
                  getIdealTempRange: _getIdealTempRange,
                  onClose: () => setState(() => selectedCubby = null),
                  getFullImagePath: _getFullImagePath,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class PlantCard extends StatelessWidget {
  final int cubbyIndex;
  final Box<Plant> plantsBox;
  final Box<int> cubbyBox;
  final String Function(int) getCurrentSoilMoisture;
  final String Function(int) getCurrentTemperature;
  final String Function(int) getCurrentHumidity;
  final String Function(int) getCurrentLight;
  final String Function(String?, int, [String?])
  getIdealSoilRange; // Updated signature
  final String Function(String?) getIdealTempRange;
  final VoidCallback onClose;
  final Future<String?> Function(String?) getFullImagePath;

  const PlantCard({
    Key? key,
    required this.cubbyIndex,
    required this.plantsBox,
    required this.cubbyBox,
    required this.getCurrentSoilMoisture,
    required this.getCurrentTemperature,
    required this.getCurrentHumidity,
    required this.getCurrentLight,
    required this.getIdealSoilRange,
    required this.getIdealTempRange,
    required this.onClose,
    required this.getFullImagePath,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final plantKey = cubbyBox.get(cubbyIndex);
    final plant = plantKey != null ? plantsBox.get(plantKey) : null;

    if (plant == null) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: Offset(0, -5),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 5,
              margin: EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2.5),
              ),
            ),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Cubby ${cubbyIndex + 1}',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[600],
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'No plant assigned',
                      style: TextStyle(fontSize: 16, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 5,
            margin: EdgeInsets.only(top: 10),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2.5),
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: Colors.grey[200],
                        ),
                        child: FutureBuilder<String?>(
                          future: getFullImagePath(plant.photoPath),
                          builder: (context, snapshot) {
                            if (snapshot.hasData && snapshot.data != null) {
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.file(
                                  File(snapshot.data!),
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Icon(
                                      Icons.local_florist,
                                      color: Colors.green[400],
                                      size: 30,
                                    );
                                  },
                                ),
                              );
                            }
                            return Icon(
                              Icons.local_florist,
                              color: Colors.green[400],
                              size: 30,
                            );
                          },
                        ),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              plant.commonName,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (plant.scientificName.isNotEmpty)
                              Text(
                                plant.scientificName,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                  fontStyle: FontStyle.italic,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  SizedBox(height: 24),

                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildParameterRow(
                        'Soil Moisture',
                        getIdealSoilRange(
                          plant.idealMoisture,
                          cubbyIndex,
                          plant.soilType,
                        ), // Pass soil type if available
                        getCurrentSoilMoisture(cubbyIndex),
                        Icons.water_drop,
                        Colors.blue,
                      ),
                      SizedBox(height: 16),
                      _buildParameterRow(
                        'Temperature',
                        getIdealTempRange(plant.idealTemp),
                        getCurrentTemperature(cubbyIndex),
                        Icons.thermostat,
                        Colors.orange,
                      ),
                      SizedBox(height: 16),
                      _buildParameterRow(
                        'Humidity',
                        plant.idealHumidity ?? 'Unknown',
                        getCurrentHumidity(cubbyIndex),
                        Icons.opacity,
                        Colors.cyan,
                      ),
                      SizedBox(height: 16),
                      _buildParameterRow(
                        'Light',
                        plant.idealLighting ?? 'Unknown',
                        getCurrentLight(cubbyIndex),
                        Icons.wb_sunny,
                        Colors.amber,
                      ),
                      SizedBox(height: 20),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParameterRow(
    String label,
    String desired,
    String current,
    IconData icon,
    Color color,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: 4),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Desired: $desired',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Current: $current',
                    style: TextStyle(
                      fontSize: 12,
                      color: current == 'Loading...' || current == 'No data'
                          ? Colors.grey[500]
                          : Colors.green[600],
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Updated Shelf3D class with full-size plant images and text overlays
class Shelf3D extends StatelessWidget {
  final int? selectedCubby;
  final Function(int) onCubbyTapped;
  final Function(int) onCubbyDoubleTapped;
  final Box<Plant> plantsBox;
  final Box<int> cubbyBox;
  final Future<String?> Function(String?) getFullImagePath;

  const Shelf3D({
    Key? key,
    required this.selectedCubby,
    required this.onCubbyTapped,
    required this.onCubbyDoubleTapped,
    required this.plantsBox,
    required this.cubbyBox,
    required this.getFullImagePath,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final screenHeight = constraints.maxHeight;

        double baseWidth = 510;
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
                  _buildCubby(
                    0,
                    15 * scaleFactor,
                    10 * scaleFactor,
                    scaleFactor,
                  ),
                  _buildCubby(
                    1,
                    175 * scaleFactor,
                    10 * scaleFactor,
                    scaleFactor,
                  ),
                  _buildCubby(
                    2,
                    330 * scaleFactor,
                    10 * scaleFactor,
                    scaleFactor,
                  ),
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

    int? plantKey = cubbyBox.get(index);
    Plant? assignedPlant = (plantKey != null) ? plantsBox.get(plantKey) : null;

    double cubbyWidth = 130 * scaleFactor;
    double cubbyHeight = 150 * scaleFactor;

    double fontSize = (12 * scaleFactor).clamp(8, 18);
    double subtitleSize = (10 * scaleFactor).clamp(6, 14);

    return Positioned(
      left: left + (20 * scaleFactor),
      top: top + (20 * scaleFactor),
      child: GestureDetector(
        onTap: () => onCubbyTapped(index),
        onDoubleTap: () => onCubbyDoubleTapped(index),
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
                        Color(0xFFD7CCC8).withOpacity(0.9),
                        Color(0xFFBCAAA4).withOpacity(0.95),
                        Color(0xFFA1887F).withOpacity(0.9),
                      ]
                    : [
                        Color(0xFFEFEBE9).withOpacity(0.8),
                        Color(0xFFD7CCC8).withOpacity(0.9),
                        Color(0xFFBCAAA4).withOpacity(0.8),
                      ],
                stops: [0.0, 0.5, 1.0],
              ),
              borderRadius: BorderRadius.circular(4 * scaleFactor),
              border: Border.all(
                color: isSelected
                    ? Color(0xFF8D6E63).withOpacity(0.8)
                    : Color(0xFF8D6E63).withOpacity(0.4),
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
                // Full-size plant image or empty state
                if (assignedPlant != null)
                  FutureBuilder<String?>(
                    future: getFullImagePath(assignedPlant.photoPath),
                    builder: (context, snapshot) {
                      if (snapshot.hasData && snapshot.data != null) {
                        return Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                              4 * scaleFactor,
                            ),
                          ),
                          child: Stack(
                            children: [
                              // Full-size image
                              ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  4 * scaleFactor,
                                ),
                                child: Container(
                                  width: cubbyWidth,
                                  height: cubbyHeight,
                                  child: Image.file(
                                    File(snapshot.data!),
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return _buildEmptyState(
                                        index,
                                        scaleFactor,
                                        fontSize,
                                        subtitleSize,
                                        isSelected,
                                      );
                                    },
                                  ),
                                ),
                              ),
                              // Gradient overlay for text readability
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(
                                    4 * scaleFactor,
                                  ),
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.black.withOpacity(0.6),
                                      Colors.transparent,
                                      Colors.transparent,
                                      Colors.black.withOpacity(0.8),
                                    ],
                                    stops: [0.0, 0.3, 0.7, 1.0],
                                  ),
                                ),
                              ),
                              // Plant name overlay
                              Positioned(
                                top: 8 * scaleFactor,
                                left: 8 * scaleFactor,
                                right: 8 * scaleFactor,
                                child: Text(
                                  assignedPlant.commonName,
                                  style: TextStyle(
                                    fontSize: fontSize,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    shadows: [
                                      Shadow(
                                        offset: Offset(0, 1),
                                        blurRadius: 2,
                                        color: Colors.black.withOpacity(0.8),
                                      ),
                                    ],
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              // Cubby number and instruction text at bottom
                              Positioned(
                                bottom: 8 * scaleFactor,
                                left: 8 * scaleFactor,
                                right: 8 * scaleFactor,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Cubby ${index + 1}',
                                      style: TextStyle(
                                        fontSize: subtitleSize,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                        shadows: [
                                          Shadow(
                                            offset: Offset(0, 1),
                                            blurRadius: 2,
                                            color: Colors.black.withOpacity(
                                              0.8,
                                            ),
                                          ),
                                        ],
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      return _buildEmptyState(
                        index,
                        scaleFactor,
                        fontSize,
                        subtitleSize,
                        isSelected,
                      );
                    },
                  )
                else
                  _buildEmptyState(
                    index,
                    scaleFactor,
                    fontSize,
                    subtitleSize,
                    isSelected,
                  ),

                // Selection highlight overlay
                if (isSelected)
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4 * scaleFactor),
                      border: Border.all(
                        color: Color(0xFF408661),
                        width: 2 * scaleFactor,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(
    int index,
    double scaleFactor,
    double fontSize,
    double subtitleSize,
    bool isSelected,
  ) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4 * scaleFactor),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.black.withOpacity(0.05),
            Colors.transparent,
            Colors.transparent,
            Colors.black.withOpacity(0.02),
          ],
          stops: [0.0, 0.1, 0.9, 1.0],
        ),
      ),
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        padding: EdgeInsets.all(8 * scaleFactor),
        decoration: BoxDecoration(
          color: isSelected
              ? Color(0xFF8D6E63).withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4 * scaleFactor),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.inventory_2_outlined,
                size: (32 * scaleFactor).clamp(16, 48),
                color: isSelected
                    ? Color(0xFF5D4037)
                    : Color(0xFF8D6E63).withOpacity(0.7),
              ),
              SizedBox(height: 4 * scaleFactor),
              Text(
                'Cubby ${index + 1}',
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? Color(0xFF5D4037)
                      : Color(0xFF8D6E63).withOpacity(0.8),
                ),
              ),
              SizedBox(height: 2 * scaleFactor),
              Text(
                'Empty',
                style: TextStyle(
                  fontSize: subtitleSize,
                  color: isSelected
                      ? Color(0xFF5D4037).withOpacity(0.7)
                      : Color(0xFF8D6E63).withOpacity(0.6),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ShelfPainter extends CustomPainter {
  final double scaleFactor;

  ShelfPainter({required this.scaleFactor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Color(0xFF8D6E63)
      ..style = PaintingStyle.fill;

    final darkWoodPaint = Paint()
      ..color = Color(0xFF6D4C41)
      ..style = PaintingStyle.fill;

    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.25)
      ..style = PaintingStyle.fill;

    final highlightPaint = Paint()
      ..color = Color(0xFFA1887F)
      ..style = PaintingStyle.fill;

    _drawShelfShadow(canvas, size, shadowPaint);
    _drawShelfStructure(canvas, size, paint, darkWoodPaint, highlightPaint);
  }

  void _drawShelfShadow(Canvas canvas, Size size, Paint shadowPaint) {
    final shadowOffset = 8.0 * scaleFactor;

    final topShelfShadow = Path()
      ..moveTo(15.0 * scaleFactor, 15.0 * scaleFactor)
      ..lineTo(485.0 * scaleFactor, 15.0 * scaleFactor)
      ..lineTo(
        485.0 * scaleFactor + shadowOffset,
        15.0 * scaleFactor + shadowOffset,
      )
      ..lineTo(
        15.0 * scaleFactor + shadowOffset,
        15.0 * scaleFactor + shadowOffset,
      )
      ..close();
    canvas.drawPath(topShelfShadow, shadowPaint);

    final bottomShelfShadow = Path()
      ..moveTo(15.0 * scaleFactor, 185.0 * scaleFactor)
      ..lineTo(485.0 * scaleFactor, 185.0 * scaleFactor)
      ..lineTo(
        485.0 * scaleFactor + shadowOffset,
        185.0 * scaleFactor + shadowOffset,
      )
      ..lineTo(
        15.0 * scaleFactor + shadowOffset,
        185.0 * scaleFactor + shadowOffset,
      )
      ..close();
    canvas.drawPath(bottomShelfShadow, shadowPaint);

    for (int i = 1; i < 3; i++) {
      final x = (15.0 + (i * 160.0)) * scaleFactor;
      final dividerShadow = Path()
        ..moveTo(x, 15.0 * scaleFactor)
        ..lineTo(x + (10.0 * scaleFactor), 15.0 * scaleFactor)
        ..lineTo(
          x + (10.0 * scaleFactor) + shadowOffset,
          15.0 * scaleFactor + shadowOffset,
        )
        ..lineTo(x + shadowOffset, 15.0 * scaleFactor + shadowOffset)
        ..lineTo(x + shadowOffset, 185.0 * scaleFactor + shadowOffset)
        ..lineTo(x, 185.0 * scaleFactor)
        ..close();
      canvas.drawPath(dividerShadow, shadowPaint);
    }

    final leftSupportShadow = Path()
      ..moveTo(15.0 * scaleFactor, 15.0 * scaleFactor)
      ..lineTo(25.0 * scaleFactor, 15.0 * scaleFactor)
      ..lineTo(
        25.0 * scaleFactor + shadowOffset,
        15.0 * scaleFactor + shadowOffset,
      )
      ..lineTo(
        15.0 * scaleFactor + shadowOffset,
        15.0 * scaleFactor + shadowOffset,
      )
      ..lineTo(
        15.0 * scaleFactor + shadowOffset,
        185.0 * scaleFactor + shadowOffset,
      )
      ..lineTo(15.0 * scaleFactor, 185.0 * scaleFactor)
      ..close();
    canvas.drawPath(leftSupportShadow, shadowPaint);

    final rightSupportShadow = Path()
      ..moveTo(485.0 * scaleFactor, 15.0 * scaleFactor)
      ..lineTo(495.0 * scaleFactor, 15.0 * scaleFactor)
      ..lineTo(
        495.0 * scaleFactor + shadowOffset,
        15.0 * scaleFactor + shadowOffset,
      )
      ..lineTo(
        485.0 * scaleFactor + shadowOffset,
        15.0 * scaleFactor + shadowOffset,
      )
      ..lineTo(
        485.0 * scaleFactor + shadowOffset,
        185.0 * scaleFactor + shadowOffset,
      )
      ..lineTo(485.0 * scaleFactor, 185.0 * scaleFactor)
      ..close();
    canvas.drawPath(rightSupportShadow, shadowPaint);
  }

  void _drawShelfStructure(
    Canvas canvas,
    Size size,
    Paint paint,
    Paint darkWoodPaint,
    Paint highlightPaint,
  ) {
    _drawBeveledRect(
      canvas,
      Rect.fromLTWH(
        15.0 * scaleFactor,
        15.0 * scaleFactor,
        470.0 * scaleFactor,
        10.0 * scaleFactor,
      ),
      paint,
      darkWoodPaint,
      highlightPaint,
    );
    _drawBeveledRect(
      canvas,
      Rect.fromLTWH(
        15.0 * scaleFactor,
        185.0 * scaleFactor,
        470.0 * scaleFactor,
        10.0 * scaleFactor,
      ),
      paint,
      darkWoodPaint,
      highlightPaint,
    );
    _drawBeveledRect(
      canvas,
      Rect.fromLTWH(
        15.0 * scaleFactor,
        15.0 * scaleFactor,
        10.0 * scaleFactor,
        180.0 * scaleFactor,
      ),
      paint,
      darkWoodPaint,
      highlightPaint,
    );
    _drawBeveledRect(
      canvas,
      Rect.fromLTWH(
        485.0 * scaleFactor,
        15.0 * scaleFactor,
        10.0 * scaleFactor,
        180.0 * scaleFactor,
      ),
      paint,
      darkWoodPaint,
      highlightPaint,
    );
    _drawBeveledRect(
      canvas,
      Rect.fromLTWH(
        175.0 * scaleFactor,
        15.0 * scaleFactor,
        10.0 * scaleFactor,
        180.0 * scaleFactor,
      ),
      paint,
      darkWoodPaint,
      highlightPaint,
    );
    _drawBeveledRect(
      canvas,
      Rect.fromLTWH(
        335.0 * scaleFactor,
        15.0 * scaleFactor,
        10.0 * scaleFactor,
        180.0 * scaleFactor,
      ),
      paint,
      darkWoodPaint,
      highlightPaint,
    );
  }

  void _drawBeveledRect(
    Canvas canvas,
    Rect rect,
    Paint mainPaint,
    Paint darkPaint,
    Paint lightPaint,
  ) {
    canvas.drawRect(rect, mainPaint);
    canvas.drawRect(
      Rect.fromLTWH(rect.left, rect.top, rect.width, 2 * scaleFactor),
      lightPaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(rect.left, rect.top, 2 * scaleFactor, rect.height),
      lightPaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        rect.left,
        rect.bottom - (2 * scaleFactor),
        rect.width,
        2 * scaleFactor,
      ),
      darkPaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        rect.right - (2 * scaleFactor),
        rect.top,
        2 * scaleFactor,
        rect.height,
      ),
      darkPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return oldDelegate is ShelfPainter &&
        oldDelegate.scaleFactor != scaleFactor;
  }
}
