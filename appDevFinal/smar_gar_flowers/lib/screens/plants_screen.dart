import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'dart:io';
import '../../dataModels/plant.dart';

class PlantsScreen extends StatefulWidget {
  @override
  _PlantsScreenState createState() => _PlantsScreenState();
}

class _PlantsScreenState extends State<PlantsScreen> {
  late Box<Plant> plantsBox;
  final ImagePicker _picker = ImagePicker();
  String? _selectedImageFileName; // Store filename instead of full path

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _sciNameController = TextEditingController();
  final TextEditingController _minTempController = TextEditingController();
  final TextEditingController _maxTempController = TextEditingController();

  String _soilType = 'Normal';
  String _humidity = 'Moist';
  String _lighting = 'Bright';
  double _soilMoisture = 0.5;

  

  @override
  void initState() {
    super.initState();
    plantsBox = Hive.box<Plant>('plantsBox');
    _validateStoredImages();
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
    
    final imageDir = await _getPlantImagesDirectory();
    final fullPath = path.join(imageDir, fileName);
    
    // Verify file exists
    if (await File(fullPath).exists()) {
      return fullPath;
    }
    
    print('Image file not found: $fullPath');
    return null;
  }

  // Validate all stored images on app start
  Future<void> _validateStoredImages() async {
    final plants = plantsBox.values.toList();
    bool hasChanges = false;
    
    for (int i = 0; i < plants.length; i++) {
      final plant = plants[i];
      if (plant.photoPath.isNotEmpty) {
        // If it's a full path, extract just the filename
        if (plant.photoPath.contains('/')) {
          final fileName = path.basename(plant.photoPath);
          final fullPath = await _getFullImagePath(fileName);
          if (fullPath != null) {
            plant.photoPath = fileName; // Store only filename
            hasChanges = true;
            print('Updated plant ${plant.commonName} to use filename: $fileName');
          } else {
            plant.photoPath = '';
            hasChanges = true;
            print('Cleared invalid image for plant: ${plant.commonName}');
          }
        } else {
          // It's already a filename, check if file exists
          final fullPath = await _getFullImagePath(plant.photoPath);
          if (fullPath == null) {
            plant.photoPath = '';
            hasChanges = true;
            print('Cleared missing image for plant: ${plant.commonName}');
          }
        }
      }
    }
    
    if (hasChanges) {
      // Save the updated plants back to Hive
      for (int i = 0; i < plants.length; i++) {
        await plantsBox.putAt(i, plants[i]);
      }
    }
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

  // Build image widget with filename
  Widget _buildPlantImage(Plant plant) {
    return FutureBuilder<String?>(
      future: _getFullImagePath(plant.photoPath),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: Image.file(
              File(snapshot.data!),
              fit: BoxFit.cover,
              width: 60,
              height: 60,
              errorBuilder: (context, error, stackTrace) {
                print('Error loading image: $error');
                return _defaultPlantIcon();
              },
            ),
          );
        }
        return _defaultPlantIcon();
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

  Widget _defaultPlantIcon() {
    return CircleAvatar(
      backgroundColor: Colors.green[100],
      child: Icon(Icons.eco, color: Color(0xFF408661)),
      radius: 30,
    );
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error saving image')),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking image: $e')),
      );
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error saving image')),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error taking photo: $e')),
      );
    }
  }

  // Method to delete image file when plant is deleted
  Future<void> _deleteImageFile(String? fileName) async {
    if (fileName != null && fileName.isNotEmpty) {
      try {
        final fullPath = await _getFullImagePath(fileName);
        if (fullPath != null) {
          final file = File(fullPath);
          if (await file.exists()) {
            await file.delete();
            print('Image deleted: $fullPath');
          }
        }
      } catch (e) {
        print('Error deleting image file: $e');
      }
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

  void _showAddPlantDialog() {
    // Reset form state
    _selectedImageFileName = null;
    
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
                          Row(
                            children: [
                              IconButton(icon: Icon(Icons.edit), onPressed: () {}),
                              IconButton(icon: Icon(Icons.bookmark_border), onPressed: () {}),
                            ],
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
                          child: Text('Remove Image', style: TextStyle(color: Colors.red)),
                        ),
                      ],
                      SizedBox(height: 20),
                      Text('Soil Texture', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
                      Text('Water Needs', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 4,
                          activeTrackColor: Color(0xFF408661),
                          inactiveTrackColor: Colors.grey[300],
                          thumbColor: Color(0xFF408661),
                          thumbShape: RoundSliderThumbShape(enabledThumbRadius: 10),
                          overlayColor: Color(0xFF408661).withOpacity(0.2),
                          tickMarkShape: RoundSliderTickMarkShape(tickMarkRadius: 4),
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
                      Text('Humidity', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
                      Text('Lighting', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
                      Text('Temperature Range', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
                              scientificName: sciName.isEmpty ? 'Unknown' : sciName,
                              idealTemp: tempMin.isNotEmpty && tempMax.isNotEmpty 
                                  ? '$tempMin–$tempMax°F' 
                                  : 'Not specified',
                              idealHumidity: _humidity,
                              idealLighting: _lighting,
                              idealMoisture: _waterNeedsToSoilMoisture(_soilMoisture),
                              soilType: _soilType,
                              photoPath: _selectedImageFileName ?? '', // Store filename only
                            );

                            plantsBox.add(newPlant);
                          }

                          _nameController.clear();
                          _sciNameController.clear();
                          _minTempController.clear();
                          _maxTempController.clear();
                          _soilType = 'Normal';
                          _humidity = 'Moist';
                          _lighting = 'Bright';
                          _soilMoisture = 0.5;
                          _selectedImageFileName = null;
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
            color: isSelected ? Color(0xFF408661).withOpacity(0.1) : Colors.white,
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
            color: isSelected ? Color(0xFF408661).withOpacity(0.1) : Colors.white,
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
            color: isSelected ? Color(0xFF408661).withOpacity(0.1) : Colors.white,
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

  void _deletePlant(int index) async {
    final plant = plantsBox.getAt(index);
    
    // Delete the image file if it exists
    if (plant?.photoPath != null && plant!.photoPath.isNotEmpty) {
      await _deleteImageFile(plant.photoPath);
    }
    
    // Delete the plant from Hive
    plantsBox.deleteAt(index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('My Plants'),
        backgroundColor: Color(0xFF408661),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ValueListenableBuilder(
        valueListenable: plantsBox.listenable(),
        builder: (context, Box<Plant> box, _) {
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'Your plant library!',
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ),
                if (box.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Text(
                        'No plants added yet.\nTap the + button to add your first plant!',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                    ),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: NeverScrollableScrollPhysics(),
                    itemCount: box.length,
                    itemBuilder: (context, index) {
                      final plant = box.getAt(index);
                      return Container(
                        margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Dismissible(
                          key: Key(plant?.commonName ?? 'plant_$index'),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: EdgeInsets.symmetric(horizontal: 20),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.delete,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                          confirmDismiss: (direction) async {
                            return await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: Text('Delete Plant'),
                                content: Text('Are you sure you want to delete ${plant?.commonName ?? 'this plant'}?'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, false),
                                    child: Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, true),
                                    child: Text('Delete', style: TextStyle(color: Colors.red)),
                                  ),
                                ],
                              ),
                            );
                          },
                          onDismissed: (direction) {
                            _deletePlant(index);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('${plant?.commonName ?? 'Plant'} deleted'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          },
                          child: Card(
                            color: Colors.green[50],
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListTile(
                              contentPadding: EdgeInsets.all(16),
                              leading: Container(
                                width: 60,
                                height: 60,
                                child: _buildPlantImage(plant!),
                              ),
                              title: Text(
                                plant?.commonName ?? 'Unnamed Plant',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(height: 8),
                                  if (plant?.scientificName != null && plant!.scientificName!.isNotEmpty && plant.scientificName != 'Unknown')
                                    Text(
                                      'Scientific Name: ${plant.scientificName}',
                                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                    ),
                                  Text(
                                    'Soil Type: ${plant?.soilType ?? 'Unknown'}',
                                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                  ),
                                  Text(
                                    'Soil Moisture: ${plant?.idealMoisture ?? 'Unknown'}',
                                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                  ),
                                  Text(
                                    'Temperature: ${plant?.idealTemp ?? 'Not specified'}',
                                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                  ),
                                  Text(
                                    'Humidity: ${plant?.idealHumidity ?? 'Unknown'}',
                                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                  ),
                                  Text(
                                    'Lighting: ${plant?.idealLighting ?? 'Unknown'}',
                                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                              isThreeLine: true,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Color(0xFF408661),
        foregroundColor: Colors.white,
        onPressed: _showAddPlantDialog,
        child: Icon(Icons.add),
      ),
    );
  }
}