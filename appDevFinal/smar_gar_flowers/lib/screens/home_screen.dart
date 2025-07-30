import '../dataModels/esp32_connect.dart';
import '../dataModels/user_info.dart';
import '../dataModels/plant.dart';
import 'hotkeys/climate_hotkey_screen.dart';
import 'hotkeys/water_hotkey_screen.dart';
import 'hotkeys/light_hotkey_screen.dart';

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'dart:io';
import 'package:image_picker/image_picker.dart';

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ESP32Connection? esp32Connection;
  bool isCheckingConnection = false;
  String connectionStatus = 'Unknown';
  Timer? connectionTimer;
  Map<String, dynamic>? sensorData;
  String? userName;
  late Box<UserInfo> userBox;
  late Box<Plant> plantsBox;
  late Box<int> cubbyBox;
  late StreamSubscription<BoxEvent> userBoxSubscription;
  late StreamSubscription<BoxEvent> plantsBoxSubscription;
  late StreamSubscription<BoxEvent> cubbyBoxSubscription;
  bool _isSensorDataExpanded = false;

  PageController _plantPageController = PageController();
  int _currentPlantIndex = 0;

  // Add Plant Dialog variables
  final ImagePicker _picker = ImagePicker();
  String? _selectedImageFileName;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _sciNameController = TextEditingController();
  final TextEditingController _minTempController = TextEditingController();
  final TextEditingController _maxTempController = TextEditingController();
  String _soilType = 'Normal';
  String _humidity = 'Moist';
  String _lighting = 'Bright';
  double _soilMoisture = 0.5;

  // Soil moisture calibration data
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
    _loadESP32Connection();
    _startPeriodicConnectionCheck();
    _initializeBoxes();
  }

  @override
  void dispose() {
    connectionTimer?.cancel();
    userBoxSubscription.cancel();
    plantsBoxSubscription.cancel();
    cubbyBoxSubscription.cancel();
    _plantPageController.dispose();
    _nameController.dispose();
    _sciNameController.dispose();
    _minTempController.dispose();
    _maxTempController.dispose();
    super.dispose();
  }

  // Helper method to determine current moisture level based on calibration
  String _getCurrentMoistureLevel(int sensorValue, int cubbyIndex, String soilType) {
    final soilTypeKey = soilType.toLowerCase();
    final ranges = cubbyMoistureRanges[cubbyIndex]?[soilTypeKey];
    
    if (ranges == null) return 'unknown';
    
    for (final entry in ranges.entries) {
      final level = entry.key;
      final range = entry.value;
      if (sensorValue >= range['lower']! && sensorValue <= range['upper']!) {
        return level;
      }
    }
    
    return 'unknown';
  }

  // Helper method to check if moisture levels are compatible
  bool _areMoistureLevelsCompatible(String currentLevel, String idealLevel) {
    // Define moisture level hierarchy
    const moistureLevels = ['dry', 'moist', 'wet', 'drenched'];
    
    final currentIndex = moistureLevels.indexOf(currentLevel.toLowerCase());
    final idealIndex = moistureLevels.indexOf(idealLevel.toLowerCase());
    
    if (currentIndex == -1 || idealIndex == -1) return true; // Unknown levels, assume compatible
    
    // Allow one level difference in either direction
    return (currentIndex - idealIndex).abs() <= 1;
  }

  // Get the plant images directory
  Future<String> _getPlantImagesDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final plantsDir = Directory(path.join(appDir.path, 'plant_images'));

    if (!await plantsDir.exists()) {
      await plantsDir.create(recursive: true);
    }

    return plantsDir.path;
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

  // Save image and return filename only
  Future<String?> _saveImagePermanently(String tempPath) async {
    try {
      final tempFile = File(tempPath);
      if (!await tempFile.exists()) {
        print('Source file does not exist: $tempPath');
        return null;
      }

      final plantsDir = await _getPlantImagesDirectory();

      // Generate a unique filename with proper extension
      final extension = path.extension(tempPath).toLowerCase();
      final fileName = '${DateTime.now().millisecondsSinceEpoch}$extension';
      final permanentPath = path.join(plantsDir, fileName);

      // Copy the file to permanent storage
      await tempFile.copy(permanentPath);

      // Verify the file was copied successfully
      final newFile = File(permanentPath);
      if (await newFile.exists()) {
        final fileSize = await newFile.length();
        if (fileSize > 0) {
          print('Image saved successfully: $permanentPath (${fileSize} bytes)');
          return fileName; // Return only the filename
        }
      }

      print('Failed to save image or file is corrupted');
      return null;
    } catch (e) {
      print('Error saving image permanently: $e');
      return null;
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );

      if (image != null) {
        // Save the image permanently and get the filename
        final fileName = await _saveImagePermanently(image.path);

        if (fileName != null) {
          setState(() {
            _selectedImageFileName = fileName;
          });
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error saving image')));
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error picking image: $e')));
    }
  }

  Future<void> _takePhoto() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );

      if (image != null) {
        // Save the image permanently and get the filename
        final fileName = await _saveImagePermanently(image.path);

        if (fileName != null) {
          setState(() {
            _selectedImageFileName = fileName;
          });
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error saving image')));
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error taking photo: $e')));
    }
  }

  void _showImageSourceDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Select Image Source'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.photo_library),
                title: Text('Gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage();
                },
              ),
              ListTile(
                leading: Icon(Icons.camera_alt),
                title: Text('Camera'),
                onTap: () {
                  Navigator.pop(context);
                  _takePhoto();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // Build dialog image widget
  Widget _buildDialogImage() {
    if (_selectedImageFileName == null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.camera_alt, size: 40, color: Colors.grey),
          SizedBox(height: 10),
          Text('Tap to upload a photo'),
        ],
      );
    }

    return FutureBuilder<String?>(
      future: _getFullImagePath(_selectedImageFileName),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(
              File(snapshot.data!),
              fit: BoxFit.cover,
              width: double.infinity,
              height: 150,
            ),
          );
        }
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error, size: 40, color: Colors.red),
            SizedBox(height: 10),
            Text('Error loading image'),
          ],
        );
      },
    );
  }

  void _showAddPlantDialog() {
    // Reset form state
    _selectedImageFileName = null;
    _nameController.clear();
    _sciNameController.clear();
    _minTempController.clear();
    _maxTempController.clear();
    _soilType = 'Normal';
    _humidity = 'Moist';
    _lighting = 'Bright';
    _soilMoisture = 0.5;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Container(
                padding: EdgeInsets.all(20),
                width: MediaQuery.of(context).size.width * 0.9,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Add Plant',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.close),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      TextField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: 'Common Name *',
                          hintText: 'Enter common name',
                        ),
                      ),
                      SizedBox(height: 15),
                      TextField(
                        controller: _sciNameController,
                        decoration: InputDecoration(
                          labelText: 'Scientific Name (Optional)',
                          hintText: 'Enter scientific name',
                        ),
                      ),
                      SizedBox(height: 15),
                      InkWell(
                        onTap: () {
                          _showImageSourceDialog();
                        },
                        child: Container(
                          height: 150,
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey[300]!),
                          ),
                          child: _buildDialogImage(),
                        ),
                      ),
                      if (_selectedImageFileName != null) ...[
                        SizedBox(height: 10),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _selectedImageFileName = null;
                            });
                          },
                          child: Text(
                            'Remove Image',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                      SizedBox(height: 20),
                      Text(
                        'Soil Texture',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 10),
                      Row(
                        children: [
                          _buildSoilTypeOption('Coarse', setState),
                          SizedBox(width: 5),
                          _buildSoilTypeOption('Rough', setState),
                          SizedBox(width: 5),
                          _buildSoilTypeOption('Normal', setState),
                          SizedBox(width: 5),
                          _buildSoilTypeOption('Fine', setState),
                        ],
                      ),

                      SizedBox(height: 20),
                      Text(
                        'Water Needs',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 4,
                          activeTrackColor: Color(0xFF408661),
                          inactiveTrackColor: Colors.grey[300],
                          thumbColor: Color(0xFF408661),
                          thumbShape: RoundSliderThumbShape(
                            enabledThumbRadius: 10,
                          ),
                          overlayColor: Color(0xFF408661).withOpacity(0.2),
                          tickMarkShape: RoundSliderTickMarkShape(
                            tickMarkRadius: 4,
                          ),
                          activeTickMarkColor: Color(0xFF408661),
                          inactiveTickMarkColor: Colors.grey[400],
                        ),
                        child: Slider(
                          value: _soilMoisture,
                          min: 0.0,
                          max: 1.0,
                          divisions: 3,
                          onChanged: (value) {
                            setState(() {
                              _soilMoisture = value;
                            });
                          },
                        ),
                      ),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Dry', style: TextStyle(fontSize: 12)),
                          Text('Moist', style: TextStyle(fontSize: 12)),
                          Text('Wet', style: TextStyle(fontSize: 12)),
                          Text('Drenched', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                      SizedBox(height: 20),
                      Text(
                        'Humidity',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 10),
                      Row(
                        children: [
                          _buildHumidityOption('Humid', setState),
                          SizedBox(width: 10),
                          _buildHumidityOption('Normal', setState),
                          SizedBox(width: 10),
                          _buildHumidityOption('Dry', setState),
                        ],
                      ),
                      SizedBox(height: 20),
                      Text(
                        'Lighting',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 10),
                      Row(
                        children: [
                          _buildLightingTypeOption('Dim', setState),
                          SizedBox(width: 5),
                          _buildLightingTypeOption('Neutral', setState),
                          SizedBox(width: 5),
                          _buildLightingTypeOption('Bright', setState),
                        ],
                      ),
                      SizedBox(height: 20),
                      Text(
                        'Temperature Range',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _minTempController,
                              decoration: InputDecoration(
                                labelText: 'Min °F',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          SizedBox(width: 10),
                          Text('to'),
                          SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _maxTempController,
                              decoration: InputDecoration(
                                labelText: 'Max °F',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 30),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFF408661),
                          padding: EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () {
                          final name = _nameController.text.trim();
                          final sciName = _sciNameController.text.trim();
                          final tempMin = _minTempController.text.trim();
                          final tempMax = _maxTempController.text.trim();

                          if (name.isNotEmpty) {
                            final newPlant = Plant(
                              commonName: name,
                              scientificName: sciName.isEmpty
                                  ? 'Unknown'
                                  : sciName,
                              idealTemp:
                                  tempMin.isNotEmpty && tempMax.isNotEmpty
                                  ? '$tempMin–$tempMax°F'
                                  : 'Not specified',
                              idealHumidity: _humidity,
                              idealLighting: _lighting,
                              idealMoisture: _waterNeedsToSoilMoisture(
                                _soilMoisture,
                              ),
                              soilType: _soilType,
                              photoPath:
                                  _selectedImageFileName ??
                                  '', // Store filename only
                            );

                            plantsBox.add(newPlant);

                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Plant "$name" added successfully!',
                                ),
                                backgroundColor: Color(0xFF408661),
                              ),
                            );
                          }
                          Navigator.pop(context);
                        },
                        child: Text(
                          'Add Plant',
                          style: TextStyle(fontSize: 18, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _waterNeedsToSoilMoisture(double value) {
    if (value == 0.0) return 'Dry';
    if (value <= 0.33) return 'Moist';
    if (value <= 0.66) return 'Wet';
    return 'Drenched';
  }

  Widget _buildSoilTypeOption(String type, StateSetter setState) {
    bool isSelected = _soilType == type;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _soilType = type;
          });
        },
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(
              color: isSelected ? Color(0xFF408661) : Colors.grey[300]!,
              width: 2,
            ),
            borderRadius: BorderRadius.circular(8),
            color: isSelected
                ? Color(0xFF408661).withOpacity(0.1)
                : Colors.white,
          ),
          child: Center(
            child: Text(
              type,
              style: TextStyle(
                color: isSelected ? Color(0xFF408661) : Colors.black,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHumidityOption(String moisture, StateSetter setState) {
    bool isSelected = _humidity == moisture;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _humidity = moisture;
          });
        },
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(
              color: isSelected ? Color(0xFF408661) : Colors.grey[300]!,
              width: 2,
            ),
            borderRadius: BorderRadius.circular(8),
            color: isSelected
                ? Color(0xFF408661).withOpacity(0.1)
                : Colors.white,
          ),
          child: Center(
            child: Text(
              moisture,
              style: TextStyle(
                color: isSelected ? Color(0xFF408661) : Colors.black,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLightingTypeOption(String lighting, StateSetter setState) {
    bool isSelected = _lighting == lighting;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _lighting = lighting;
          });
        },
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(
              color: isSelected ? Color(0xFF408661) : Colors.grey[300]!,
              width: 2,
            ),
            borderRadius: BorderRadius.circular(8),
            color: isSelected
                ? Color(0xFF408661).withOpacity(0.1)
                : Colors.white,
          ),
          child: Center(
            child: Text(
              lighting,
              style: TextStyle(
                color: isSelected ? Color(0xFF408661) : Colors.black,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _navigateToWaterHotkeys() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => WaterHotkeyScreen()),
    );
  }

  void _navigateToLightingHotkeys() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => LightingHotkeyScreen()),
    );
  }

  void _navigateToClimateHotkeys() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ClimateHotkeyScreen()),
    );
  }

  Future<void> _initializeBoxes() async {
    userBox = Hive.box<UserInfo>('userBox');
    plantsBox = await Hive.openBox<Plant>('plantsBox');
    cubbyBox = await Hive.openBox<int>('cubbyAssignments');

    _loadUserName();

    userBoxSubscription = userBox.watch(key: 'info').listen((event) {
      final info = userBox.get('info');
      setState(() {
        userName = info?.userFirstName;
      });
    });

    plantsBoxSubscription = plantsBox.watch().listen((event) {
      setState(() {});
    });

    cubbyBoxSubscription = cubbyBox.watch().listen((event) {
      setState(() {});
    });
  }

  void _loadUserName() {
    final info = userBox.get('info');
    setState(() {
      userName = info?.userFirstName;
    });
  }

  List<Plant?> _getPlantsByCubby() {
    List<Plant?> plantsByCubby = [null, null, null];

    for (int i = 0; i < 3; i++) {
      final plantKey = cubbyBox.get(i);
      if (plantKey != null) {
        final plant = plantsBox.get(plantKey);
        plantsByCubby[i] = plant;
      }
    }

    return plantsByCubby;
  }

  List<Plant> _getAssignedPlants() {
    List<Plant> assignedPlants = [];

    for (int i = 0; i < 3; i++) {
      final plantKey = cubbyBox.get(i);
      if (plantKey != null) {
        final plant = plantsBox.get(plantKey);
        if (plant != null) {
          assignedPlants.add(plant);
        }
      }
    }

    return assignedPlants;
  }

  bool _plantNeedsAttention(Plant plant, int cubbyIndex) {
    if (sensorData == null || connectionStatus != 'Connected') return false;

    final issues = _getPlantIssues(plant, cubbyIndex);
    return issues.isNotEmpty;
  }

  List<String> _getPlantIssues(Plant plant, int cubbyIndex) {
    if (sensorData == null || connectionStatus != 'Connected') return [];

    List<String> issues = [];

    // Soil moisture check using calibration ranges
    final soilSensorKey = 'sensor${cubbyIndex + 1}';
    final soilData = sensorData!['soil']?[soilSensorKey];

    if (soilData != null && soilData['value'] != null) {
      final currentMoisture = soilData['value'] as int;
      final soilType = plant.soilType ?? 'normal';
      final idealMoistureLevel = plant.idealMoisture ?? 'moist';
      
      final currentMoistureLevel = _getCurrentMoistureLevel(currentMoisture, cubbyIndex, soilType);
      
      if (currentMoistureLevel != 'unknown') {
        if (!_areMoistureLevelsCompatible(currentMoistureLevel, idealMoistureLevel)) {
          // Determine if it's too wet or too dry
          const moistureLevels = ['dry', 'moist', 'wet', 'drenched'];
          final currentIndex = moistureLevels.indexOf(currentMoistureLevel.toLowerCase());
          final idealIndex = moistureLevels.indexOf(idealMoistureLevel.toLowerCase());
          
          if (currentIndex > idealIndex + 1) {
            issues.add('Soil too wet');
          } else if (currentIndex < idealIndex - 1) {
            issues.add('Soil too dry');
          }
        }
      }
    }

    // Temperature check (keep existing logic)
    final tempSensorKey = 'temperature${cubbyIndex + 1}';
    final tempData = sensorData!['environment']?[tempSensorKey];

    if (tempData != null &&
        tempData['value'] != null &&
        tempData['value'] != 0) {
      final currentTemp = tempData['value'] as num;
      final idealTemp = _parseTemperatureToInt(plant.idealTemp ?? '22°C');

      if (currentTemp < idealTemp - 3) {
        // issues.add('Too cold');
      } else if (currentTemp > idealTemp + 3) {
        issues.add('Too hot');
      }
    }

    // Humidity check (keep existing logic)
    final humiditySensorKey = 'humidity${cubbyIndex + 1}';
    final humidityData = sensorData!['environment']?[humiditySensorKey];

    if (humidityData != null &&
        humidityData['value'] != null &&
        humidityData['value'] != 0) {
      final currentHumidity = humidityData['value'] as num;
      final idealHumidity = _parseHumidityToInt(plant.idealHumidity ?? '50%');

      if (currentHumidity < idealHumidity - 10) {
        issues.add('Too dry air');
      } else if (currentHumidity > idealHumidity + 10) {
        issues.add('Too humid');
      }
    }

    // Light check (keep existing logic)
    final lightSensorKey = 'light${cubbyIndex + 1}';
    final lightData = sensorData!['environment']?[lightSensorKey];

    if (lightData != null &&
        lightData['value'] != null &&
        lightData['value'] != 0) {
      final currentLight = lightData['value'] as num;
      final idealLight = _parseLightToInt(plant.idealLighting ?? 'medium');

      if (currentLight < idealLight - 200) {
        // issues.add('Too dim');
      } else if (currentLight > idealLight + 200) {
        // issues.add('Too bright');
      }
    }

    return issues;
  }

  String _getPlantStatus(Plant plant, int cubbyIndex) {
    if (sensorData == null || connectionStatus != 'Connected') {
      return 'Condition unknown; F.L.O.W.E.R.S. is not connected';
    }

    final issues = _getPlantIssues(plant, cubbyIndex);

    if (issues.isEmpty) {
      return 'Healthy condition';
    } else if (issues.length == 1) {
      return issues.first;
    } else {
      return '${issues.length} issues detected';
    }
  }

  int _parseLightToInt(String light) {
    light = light.toLowerCase().trim();
    if (light.contains('dim') || light.contains('low')) return 200;
    if (light.contains('neutral') ||
        light.contains('medium') ||
        light.contains('moderate'))
      return 500;
    if (light.contains('bright') || light.contains('high')) return 1000;
    return 500;
  }

  int _parseMoistureToInt(String moisture) {
    moisture = moisture.toLowerCase().trim();
    if (moisture.contains('dry') || moisture.contains('low')) return 30;
    if (moisture.contains('moist') ||
        moisture.contains('medium') ||
        moisture.contains('moderate'))
      return 60;
    if (moisture.contains('wet') || moisture.contains('high')) return 80;
    if (moisture.contains('drenched') || moisture.contains('very wet'))
      return 95;
    return 60;
  }

  int _parseHumidityToInt(String humidity) {
    humidity = humidity.toLowerCase().trim();
    if (humidity.contains('dry') || humidity.contains('low')) return 40;
    if (humidity.contains('normal') ||
        humidity.contains('medium') ||
        humidity.contains('moderate'))
      return 60;
    if (humidity.contains('humid') || humidity.contains('high')) return 80;
    final regex = RegExp(r'(\d+)%?');
    final match = regex.firstMatch(humidity);
    if (match != null) {
      return int.parse(match.group(1)!);
    }
    return 60;
  }

  int _parseTemperatureToInt(String temp) {
    temp = temp.trim();

    if (temp.contains('-') || temp.contains('–')) {
      final parts = temp.split(RegExp(r'[-–]'));
      if (parts.length == 2) {
        try {
          final min = int.parse(parts[0].trim());
          final max = int.parse(
            parts[1].replaceAll(RegExp(r'[°CF]'), '').trim(),
          );
          return ((min + max) / 2).round();
        } catch (e) {
          // Continue to single value parsing
        }
      }
    }

    final regex = RegExp(r'(\d+)');
    final match = regex.firstMatch(temp);
    if (match != null) {
      return int.parse(match.group(1)!);
    }

    return 22;
  }

  Future<void> _loadESP32Connection() async {
    // _checkAndPromptUserName();
    try {
      final box = await Hive.openBox<ESP32Connection>('esp32_connection');
      if (box.isNotEmpty) {
        setState(() {
          esp32Connection = box.getAt(0);
        });
        await _checkESP32Connection();
      } else {
        setState(() {
          connectionStatus = 'No device configured';
        });
      }
    } catch (e) {
      print('Error loading ESP32 connection: $e');
      setState(() {
        connectionStatus = 'Error loading config';
      });
    }
  }

  Future<void> _checkAndPromptUserName() async {
    final userBox = Hive.box<UserInfo>('userBox');

    if (userBox.isEmpty ||
        userBox.get('info')?.userFirstName == null ||
        userBox.get('info')!.userFirstName!.isEmpty) {
      await Future.delayed(Duration.zero);
      _showNameDialog();
    }
  }

  void _showNameDialog() {
    final TextEditingController _nameController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Welcome!'),
          content: TextField(
            controller: _nameController,
            decoration: InputDecoration(hintText: 'Enter your name'),
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (_nameController.text.trim().isNotEmpty) {
                  final userBox = Hive.box<UserInfo>('userBox');
                  userBox.put(
                    'info',
                    UserInfo(userFirstName: _nameController.text.trim()),
                  );
                  Navigator.of(context).pop();
                }
              },
              child: Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _startPeriodicConnectionCheck() {
    connectionTimer = Timer.periodic(Duration(seconds: 30), (timer) {
      if (esp32Connection?.ipAddress != null) {
        _checkESP32Connection();
      }
    });
  }

  Future<void> _checkESP32Connection() async {
    if (esp32Connection?.ipAddress == null) {
      setState(() {
        connectionStatus = 'No IP configured';
      });
      return;
    }

    setState(() {
      isCheckingConnection = true;
    });

    try {
      final url = 'http://${esp32Connection!.ipAddress}/sensors';

      final response = await http
          .get(Uri.parse(url), headers: {'Content-Type': 'application/json'})
          .timeout(Duration(seconds: 8));

      if (response.statusCode == 200) {
        try {
          final jsonData = json.decode(response.body);
          setState(() {
            connectionStatus = 'Connected';
            sensorData = jsonData;
          });

          esp32Connection?.updateConnection(connected: true);
        } catch (e) {
          setState(() {
            connectionStatus = 'Invalid JSON response';
          });
          esp32Connection?.updateConnection(connected: false);
        }
      } else {
        setState(() {
          connectionStatus = 'HTTP Error: ${response.statusCode}';
        });
        esp32Connection?.updateConnection(connected: false);
      }
    } on TimeoutException {
      setState(() {
        connectionStatus = 'Connection timeout';
      });
      esp32Connection?.updateConnection(connected: false);
    } catch (e) {
      setState(() {
        connectionStatus = 'Connection failed';
      });
      esp32Connection?.updateConnection(connected: false);
    } finally {
      setState(() {
        isCheckingConnection = false;
      });
    }
  }

  Widget _buildConnectionStatus() {
    Color statusColor;
    IconData statusIcon;

    switch (connectionStatus) {
      case 'Connected':
        statusColor = Colors.green;
        statusIcon = Icons.wifi;
        break;
      case 'Connection timeout':
      case 'Connection failed':
      case 'Invalid JSON response':
      case 'HTTP Error: 404':
      case 'HTTP Error: 500':
        statusColor = Colors.red;
        statusIcon = Icons.wifi_off;
        break;
      case 'No IP configured':
        statusColor = Colors.grey;
        statusIcon = Icons.settings;
        break;
      default:
        statusColor = Colors.orange;
        statusIcon = Icons.wifi_find;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: statusColor.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isCheckingConnection)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                  ),
                )
              else
                Icon(statusIcon, color: statusColor, size: 16),
              SizedBox(width: 8),
              Text(
                connectionStatus,
                style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        if (esp32Connection?.ipAddress != null)
          Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'IP: ${esp32Connection!.ipAddress}',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSwipeablePlantDisplay() {
    final plantsByCubby = _getPlantsByCubby();
    final assignedPlants = plantsByCubby
        .where((plant) => plant != null)
        .toList();

    if (assignedPlants.isEmpty) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.eco_outlined, size: 48, color: Colors.grey[400]),
                  SizedBox(height: 16),
                  Text(
                    'No plants assigned',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[600],
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Assign plants in the Environment tab',
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      height: 200,
      child: Stack(
        children: [
          PageView.builder(
            controller: _plantPageController,
            onPageChanged: (index) {
              setState(() {
                _currentPlantIndex = index;
              });
            },
            itemCount: assignedPlants.length,
            itemBuilder: (context, index) {
              final plant = assignedPlants[index];

              int? cubbyIndex;
              for (int i = 0; i < 3; i++) {
                if (plantsByCubby[i] == plant) {
                  cubbyIndex = i;
                  break;
                }
              }

              final needsAttention =
                  cubbyIndex != null && connectionStatus == 'Connected'
                  ? _plantNeedsAttention(plant!, cubbyIndex)
                  : false;

              String status;
              if (cubbyIndex != null) {
                status = _getPlantStatus(plant!, cubbyIndex);
              } else {
                status = connectionStatus == 'Connected'
                    ? 'Healthy condition'
                    : 'Condition unknown; F.L.O.W.E.R.S. is not connected';
              }

              String displayName =
                  (plant!.scientificName.isNotEmpty &&
                      plant.scientificName != 'Unknown')
                  ? plant.scientificName
                  : plant.commonName;

              return Container(
                margin: EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: FutureBuilder<String?>(
                  future: _getFullImagePath(plant.photoPath),
                  builder: (context, snapshot) {
                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(20),
                        image: snapshot.hasData && snapshot.data != null
                            ? DecorationImage(
                                image: FileImage(File(snapshot.data!)),
                                fit: BoxFit.cover,
                                colorFilter: ColorFilter.mode(
                                  Colors.black.withOpacity(0.3),
                                  BlendMode.darken,
                                ),
                              )
                            : null,
                      ),
                      child: Stack(
                        children: [
                          if (!snapshot.hasData || snapshot.data == null)
                            Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFF408661),
                                    Color(0xFF2E6B47),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                          Positioned(
                            bottom: 20,
                            left: 20,
                            right: 20,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        displayName,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (connectionStatus != 'Connected')
                                      Container(
                                        padding: EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.withOpacity(0.9),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          Icons.help_outline,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      )
                                    else if (needsAttention)
                                      Container(
                                        padding: EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.withOpacity(0.9),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          Icons.warning,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      ),
                                  ],
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Cubby ${(cubbyIndex ?? 0) + 1}',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.8),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  status,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          ),
          if (assignedPlants.length > 1)
            Positioned(
              bottom: 8,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  assignedPlants.length,
                  (index) => Container(
                    margin: EdgeInsets.symmetric(horizontal: 4),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _currentPlantIndex == index
                          ? Colors.white
                          : Colors.white.withOpacity(0.4),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSensorDataCard() {
    if (sensorData == null || connectionStatus != 'Connected') {
      return SizedBox.shrink();
    }

    return Container(
      margin: EdgeInsets.only(top: 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Collapsible header
          GestureDetector(
            onTap: () {
              setState(() {
                _isSensorDataExpanded = !_isSensorDataExpanded;
              });
            },
            child: Container(
              padding: EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Row(
                children: [
                  Icon(Icons.sensors, color: Color(0xFF408661)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Live Sensor Data',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _isSensorDataExpanded ? 0.5 : 0.0,
                    duration: Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      color: Color(0xFF408661),
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Collapsible content
          AnimatedCrossFade(
            firstChild: SizedBox.shrink(),
            secondChild: Container(
              padding: EdgeInsets.only(left: 15, right: 15, bottom: 15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Divider(color: Colors.grey[200], thickness: 1, height: 1),
                  SizedBox(height: 15),
                  ...sensorData!.entries
                      .map(
                        (categoryEntry) => _buildCategorySection(
                          categoryEntry.key,
                          categoryEntry.value,
                        ),
                      )
                      .toList(),
                ],
              ),
            ),
            crossFadeState: _isSensorDataExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: Duration(milliseconds: 300),
          ),
        ],
      ),
    );
  }

  Widget _buildCategorySection(String categoryName, dynamic categoryData) {
    if (categoryData is! Map<String, dynamic>) return SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          margin: EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Color(0xFF408661).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            _formatCategoryName(categoryName),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF408661),
            ),
          ),
        ),
        ...categoryData.entries
            .map(
              (sensorEntry) =>
                  _buildSensorRow(sensorEntry.key, sensorEntry.value),
            )
            .toList(),
        SizedBox(height: 15),
      ],
    );
  }

  Widget _buildSensorRow(String sensorName, dynamic sensorData) {
    String displayValue = 'N/A';
    String status = 'unknown';
    Color statusColor = Colors.grey;

    if (sensorData is Map<String, dynamic>) {
      var value = sensorData['value'];
      status = sensorData['status']?.toString() ?? 'unknown';

      if (value != null) {
        displayValue = _formatSensorValue(sensorName, value);
      }
    } else {
      displayValue = _formatSensorValue(sensorName, sensorData);
    }

    statusColor = _getStatusColor(status);

    return Container(
      margin: EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(8),
                  bottomLeft: Radius.circular(8),
                ),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatSensorLabel(sensorName),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 4),
                  Text(
                    displayValue,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.only(
                  topRight: Radius.circular(8),
                  bottomRight: Radius.circular(8),
                ),
                border: Border(
                  top: BorderSide(color: Colors.grey[200]!),
                  right: BorderSide(color: Colors.grey[200]!),
                  bottom: BorderSide(color: Colors.grey[200]!),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    status.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatCategoryName(String categoryName) {
    return categoryName
        .split('_')
        .map(
          (word) =>
              word.isNotEmpty ? word[0].toUpperCase() + word.substring(1) : '',
        )
        .join(' ');
  }

  String _formatSensorLabel(String sensorName) {
    String formatted = sensorName.replaceAll(RegExp(r'\d+'), '');
    return formatted
        .split('_')
        .map(
          (word) =>
              word.isNotEmpty ? word[0].toUpperCase() + word.substring(1) : '',
        )
        .join(' ');
  }

  String _formatSensorValue(String sensorName, dynamic value) {
    if (value == null) return 'N/A';

    String lowerName = sensorName.toLowerCase();

    if (lowerName.contains('temp')) {
      return '${value}°F';
    } else if (lowerName.contains('humid')) {
      return '${value}%';
    } else if (lowerName.contains('light')) {
      return '${value} lux';
    } else if (lowerName.contains('soil') || lowerName.contains('sensor')) {
      return '${value}';
    }

    return value.toString();
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'normal':
      case 'wet':
        return Colors.green;
      case 'hot':
      case 'dry':
        return Colors.red;
      case 'cold':
      case 'dim':
        return Colors.blue;
      case 'warm':
        return Colors.orange;
      case 'humid':
        return Colors.teal;
      case 'bright':
        return Colors.yellow[700]!;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final assignedPlants = _getAssignedPlants();

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hi, ${userName ?? ''}',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          assignedPlants.isNotEmpty
                              ? 'Your garden needs attention'
                              : 'No plants assigned yet',
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                      ],
                    ),
                    CircleAvatar(
                      backgroundColor: Color(0xFF408661),
                      radius: 30,
                      child: Icon(Icons.eco, color: Colors.white),
                    ),
                  ],
                ),
                SizedBox(height: 15),

                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildConnectionStatus(),
                        if (esp32Connection?.ipAddress != null)
                          TextButton.icon(
                            onPressed: isCheckingConnection
                                ? null
                                : _checkESP32Connection,
                            icon: Icon(Icons.refresh, size: 16),
                            label: Text('Refresh'),
                            style: TextButton.styleFrom(
                              foregroundColor: Color(0xFF408661),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                SizedBox(height: 20),

                _buildSwipeablePlantDisplay(),
                SizedBox(height: 20),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildActionButton(
                      Icons.add,
                      'Add Plant',
                      Color(0xFF408661),
                      _showAddPlantDialog,
                    ),
                    _buildActionButton(
                      Icons.water_drop,
                      'Water',
                      Color(0xFF408661),
                      _navigateToWaterHotkeys,
                    ),
                    _buildActionButton(
                      Icons.wb_sunny,
                      'Light',
                      Color(0xFF408661),
                      _navigateToLightingHotkeys,
                    ),
                    _buildActionButton(
                      Icons.eco,
                      'Climate',
                      Color(0xFF408661),
                      _navigateToClimateHotkeys,
                    ),
                  ],
                ),
                SizedBox(height: 30),

                Text(
                  'Your Plants',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 15),

                if (assignedPlants.isEmpty) ...[
                  Container(
                    padding: EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.eco_outlined,
                            size: 48,
                            color: Colors.grey[400],
                          ),
                          SizedBox(height: 16),
                          Text(
                            'No plants assigned yet',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[600],
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Go to the Environment tab to assign plants to cubbies',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[500],
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else ...[
                  ...assignedPlants.asMap().entries.map((entry) {
                    final index = entry.key;
                    final plant = entry.value;

                    int? cubbyIndex;
                    for (int i = 0; i < 3; i++) {
                      final plantKey = cubbyBox.get(i);
                      if (plantKey != null &&
                          plantsBox.get(plantKey) == plant) {
                        cubbyIndex = i;
                        break;
                      }
                    }

                    final needsAttention =
                        cubbyIndex != null && connectionStatus == 'Connected'
                        ? _plantNeedsAttention(plant, cubbyIndex)
                        : false;

                    String status;
                    if (cubbyIndex != null) {
                      if (connectionStatus != 'Connected') {
                        status =
                            'Condition unknown; F.L.O.W.E.R.S. is not connected';
                      } else {
                        final issues = _getPlantIssues(plant, cubbyIndex);
                        if (issues.isEmpty) {
                          status = 'Healthy condition';
                        } else if (issues.length == 1) {
                          status = issues.first;
                        } else {
                          status =
                              '${issues.length} issues: ${issues.take(2).join(', ')}${issues.length > 2 ? '...' : ''}';
                        }
                      }
                    } else {
                      status = connectionStatus == 'Connected'
                          ? 'Healthy condition'
                          : 'Condition unknown; F.L.O.W.E.R.S. is not connected';
                    }

                    return _buildPlantCard(
                      plant.commonName,
                      status,
                      needsAttention,
                      plant.photoPath,
                    );
                  }).toList(),
                ],

                _buildSensorDataCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(
    IconData icon,
    String label,
    Color color,
    VoidCallback onPressed,
  ) {
    return GestureDetector(
      onTap: onPressed,
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          SizedBox(height: 8),
          Text(label, style: TextStyle(fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildPlantCard(
    String name,
    String status,
    bool needsAttention,
    String? photoPath,
  ) {
    return Container(
      margin: EdgeInsets.only(bottom: 15),
      padding: EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 10,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.green[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: FutureBuilder<String?>(
              future: _getFullImagePath(photoPath),
              builder: (context, snapshot) {
                if (snapshot.hasData && snapshot.data != null) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      File(snapshot.data!),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Icon(Icons.eco, color: Color(0xFF408661));
                      },
                    ),
                  );
                }
                return Icon(Icons.eco, color: Color(0xFF408661));
              },
            ),
          ),
          SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  status,
                  style: TextStyle(color: Colors.grey, fontSize: 14),
                ),
              ],
            ),
          ),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: connectionStatus != 'Connected'
                  ? Colors.grey[100]
                  : needsAttention
                  ? Colors.orange[100]
                  : Color(0xFF408661).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              connectionStatus != 'Connected'
                  ? Icons.help_outline
                  : needsAttention
                  ? Icons.warning
                  : Icons.check,
              color: connectionStatus != 'Connected'
                  ? Colors.grey
                  : needsAttention
                  ? Colors.orange
                  : Color(0xFF408661),
            ),
          ),
        ],
      ),
    );
  }
}