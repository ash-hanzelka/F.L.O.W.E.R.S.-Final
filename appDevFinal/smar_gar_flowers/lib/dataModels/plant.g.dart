// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'plant.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PlantAdapter extends TypeAdapter<Plant> {
  @override
  final int typeId = 0;

  @override
  Plant read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Plant(
      commonName: fields[0] as String,
      scientificName: fields[1] as String,
      idealTemp: fields[2] as String,
      idealHumidity: fields[3] as String,
      idealMoisture: fields[4] as String,
      soilType: fields[5] as String,
      photoPath: fields[6] as String,
      idealLighting: fields[7] as String,
    );
  }

  @override
  void write(BinaryWriter writer, Plant obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.commonName)
      ..writeByte(1)
      ..write(obj.scientificName)
      ..writeByte(2)
      ..write(obj.idealTemp)
      ..writeByte(3)
      ..write(obj.idealHumidity)
      ..writeByte(4)
      ..write(obj.idealMoisture)
      ..writeByte(5)
      ..write(obj.soilType)
      ..writeByte(6)
      ..write(obj.photoPath)
      ..writeByte(7)
      ..write(obj.idealLighting);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlantAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
