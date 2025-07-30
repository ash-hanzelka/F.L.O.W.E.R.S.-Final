import 'package:flutter/material.dart';

// connect to all screens for functionality
import 'screens/home_screen.dart';
import 'screens/plants_screen.dart';
// import 'screens/stats_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/environment_screen.dart';

// implementing local storage
import 'package:hive_flutter/hive_flutter.dart';
import 'dataModels/plant.dart';
import 'dataModels/esp32_connect.dart';
import 'dataModels/user_info.dart';

// void main() {
//   runApp(MyApp());
// }

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  Hive.registerAdapter(PlantAdapter());
  await Hive.openBox<Plant>('plantsBox');
  // runApp(MyApp());
  await Hive.openBox<int>('cubbyAssignments'); // This box will map cubbyIndex (0, 1, 2) ➝ plant index in 'plantsBox'
  Hive.registerAdapter(ESP32ConnectionAdapter());

  await Hive.openBox<ESP32Connection>('esp32Box');

  Hive.registerAdapter(UserInfoAdapter()); 
  await Hive.openBox<UserInfo>('userBox');

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Garden',
      theme: ThemeData(
        primaryColor: Color(0xFF408661), // Green theme color from your design
        scaffoldBackgroundColor: Colors.white,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        // bottomNavigationBarTheme: BottomNavigationBarThemeData(
        //   backgroundColor: Color(0xFF408661),
        //   selectedItemColor: Colors.white,
        //   unselectedItemColor: Colors.white.withOpacity(0.7),
        //   type: BottomNavigationBarType.fixed,
        // ),
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF408661),
          selectedItemColor: Colors.white,
          unselectedItemColor: Colors.white.withOpacity(0.7),
          type: BottomNavigationBarType.fixed,
          selectedLabelStyle: TextStyle(fontSize: 11),
          unselectedLabelStyle: TextStyle(fontSize: 10),
        ),
      ),
      home: MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    HomeScreen(),
    PlantsScreen(),
    EnvironmentScreen(),
    // StatsScreen(),
    SettingsScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  void initState() {
    super.initState();
     _checkAndPromptUserName();
    // WidgetsBinding.instance.addPostFrameCallback((_) {
    //   _checkAndPromptUserName();
    // });
  }

  Future<void> _checkAndPromptUserName() async {
    final userBox = Hive.box<UserInfo>('userBox');

    if (userBox.isEmpty || userBox.get('info')?.userFirstName == null || userBox.get('info')!.userFirstName!.isEmpty) {
      await Future.delayed(Duration.zero); // ensures context is available
      _showNameDialog();
    }
  }

  void _showNameDialog() {
    final TextEditingController _nameController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false, // force user to enter a name
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
                  userBox.put('info', UserInfo(userFirstName: _nameController.text.trim()));
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


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Color(0xFF408661),
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(
            icon: Icon(Icons.local_florist),
            label: 'Plants',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.shelves), label: 'Environment'),
          // BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Stats'),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
      ),
    );
  }
}
