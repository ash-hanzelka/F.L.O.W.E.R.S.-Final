// flutter pub run build_runner build
// flutter packages pub run build_runner build


import 'package:hive/hive.dart';

part 'plant.g.dart';

@HiveType(typeId: 0)
class Plant extends HiveObject {
  @HiveField(0)
  String commonName;

  @HiveField(1)
  String scientificName;

  @HiveField(2)
  String idealTemp;

  @HiveField(3)
  String idealHumidity;

  @HiveField(4)
  String idealMoisture; // <-- Add this if it's missing

  @HiveField(5)
  String soilType;

  @HiveField(6)
  String photoPath;

  @HiveField(7)
  String idealLighting;

  Plant({
    required this.commonName,
    required this.scientificName,
    required this.idealTemp,
    required this.idealHumidity,
    required this.idealMoisture, // <-- Add this if missing
    required this.soilType,
    required this.photoPath,
    required this.idealLighting,
  });
}
