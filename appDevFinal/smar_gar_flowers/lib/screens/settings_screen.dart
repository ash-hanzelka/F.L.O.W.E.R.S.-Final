import 'package:flutter/material.dart';
import 'connection_instructions_screen.dart';

import 'package:hive/hive.dart'; //
import '../dataModels/user_info.dart';


class SettingsScreen extends StatefulWidget {
  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = true;
  bool _autoWatering = false;
  double _moistureThreshold = 30.0;

  bool _justWatered = false;
  List<Map<String, dynamic>> _wateringHistory = [];
  
  // Water tank variables
  double _waterLevel = 2.0; // Current water level in gallons
  double _tankCapacity = 5.0; // Total tank capacity in gallons

  // Constants for watering
  static const double _wateringAmountOz = 3.2; // Amount in ounces
  static const double _wateringAmountGal = _wateringAmountOz / 128.0; // Convert to gallons

  Future<void> _clearUserName() async {
    final box = Hive.box<UserInfo>('userBox');
    await box.delete('info');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Name cleared. It will be asked again on Home.")),
    );
  }
  
  void _recordWatering() {
    setState(() {
      // Subtract the watering amount, but don't go below 0
      _waterLevel = (_waterLevel - _wateringAmountGal).clamp(0.0, _tankCapacity);
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Plant watered! Used ${_wateringAmountOz}oz from tank.'),
        backgroundColor: Color(0xFF408661),
      ),
    );
  }

  void _editTankCapacity() {
    final TextEditingController controller = TextEditingController(
      text: _tankCapacity.toString()
    );
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Edit Tank Capacity'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Tank Capacity (gallons)',
              suffixText: 'gal',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final double? newCapacity = double.tryParse(controller.text);
                if (newCapacity != null && newCapacity > 0) {
                  setState(() {
                    _tankCapacity = newCapacity;
                    // Ensure water level doesn't exceed new capacity
                    if (_waterLevel > _tankCapacity) {
                      _waterLevel = _tankCapacity;
                    }
                  });
                  Navigator.of(context).pop();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Please enter a valid number')),
                  );
                }
              },
              child: Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _editWaterLevel() {
    final TextEditingController controller = TextEditingController(
      text: _waterLevel.toString()
    );
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Update Water Level'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Current Water Level (gallons)',
              suffixText: 'gal',
              helperText: 'Max: ${_tankCapacity.toString()} gal',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final double? newLevel = double.tryParse(controller.text);
                if (newLevel != null && newLevel >= 0 && newLevel <= _tankCapacity) {
                  setState(() {
                    _waterLevel = newLevel;
                  });
                  Navigator.of(context).pop();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Please enter a valid number between 0 and $_tankCapacity')),
                  );
                }
              },
              child: Text('Save'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Settings'),
        backgroundColor: Color(0xFF408661),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        children: [
          SwitchListTile(
            title: Text('Enable Notifications'),
            subtitle: Text('Get alerts about plant condition'),
            value: _notificationsEnabled,
            onChanged: (value) {
              setState(() {
                _notificationsEnabled = value;
              });
            },
          ),
          Divider(),
          SwitchListTile(
            title: Text('Auto Watering'),
            subtitle: Text('Automatically water when moisture is low'),
            value: _autoWatering,
            onChanged: (value) {
              setState(() {
                _autoWatering = value;
              });
            },
          ),
          // Divider(),
          // Padding(
          //   padding: const EdgeInsets.all(16.0),
          //   child: Column(
          //     crossAxisAlignment: CrossAxisAlignment.start,
          //     children: [
          //       Text('Moisture Threshold (%)'),
          //       Slider(
          //         min: 0,
          //         max: 100,
          //         divisions: 10,
          //         label: _moistureThreshold.round().toString(),
          //         value: _moistureThreshold,
          //         onChanged: (value) {
          //           setState(() {
          //             _moistureThreshold = value;
          //           });
          //         },
          //       ),
          //     ],
          //   ),
          // ),
          // Divider(),
          ListTile(
            title: Text('Connect to ESP32 Device'),
            trailing: Icon(Icons.developer_board),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => ConnectionInstructionsScreen()),
              );
            },
          ),
          // ListTile(
          //   title: Text('Clear My Name'),
          //   trailing: Icon(Icons.clear),
          //   onTap: _clearUserName,
          // ),
          ListTile(
            title: Text('About'),
            trailing: Icon(Icons.info_outline),
            onTap: () {
              // Show about dialog
            },
          ),
          Divider(thickness: 2),
          // Water Tank Section
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Water Tank Status',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF408661),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.settings, color: Color(0xFF408661)),
                      onPressed: _editTankCapacity,
                      tooltip: 'Edit tank capacity',
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_waterLevel.toStringAsFixed(1)} / ${_tankCapacity.toStringAsFixed(1)} gal',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                    Text(
                      '${((_waterLevel / _tankCapacity) * 100).toStringAsFixed(0)}%',
                      style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                Container(
                  height: 20,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: Colors.grey[300],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: _waterLevel / _tankCapacity,
                      backgroundColor: Colors.transparent,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _waterLevel / _tankCapacity > 0.2
                            ? Colors.blue[600]!
                            : Colors.red[400]!
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _editWaterLevel,
                        icon: Icon(Icons.water_drop),
                        label: Text('Update Level'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFF408661),
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          setState(() {
                            _waterLevel = _tankCapacity;
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Tank refilled to capacity!')),
                          );
                        },
                        icon: Icon(Icons.refresh),
                        label: Text('Refill Tank'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Color(0xFF408661),
                          side: BorderSide(color: Color(0xFF408661)),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                // New Watered button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _waterLevel >= _wateringAmountGal ? _recordWatering : null,
                    icon: Icon(Icons.eco),
                    label: Text('Watered (${_wateringAmountOz}oz)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[600],
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey[300],
                      padding: EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                if (_waterLevel < _wateringAmountGal)
                  Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Not enough water in tank for watering',
                      style: TextStyle(
                        color: Colors.orange[700],
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                if (_waterLevel / _tankCapacity <= 0.2)
                  Container(
                    margin: EdgeInsets.only(top: 12),
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red[200]!),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning, color: Colors.red[600], size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Water level is low! Consider refilling soon.',
                            style: TextStyle(color: Colors.red[800]),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}