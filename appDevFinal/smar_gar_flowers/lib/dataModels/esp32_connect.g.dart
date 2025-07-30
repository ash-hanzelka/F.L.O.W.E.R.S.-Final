// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'esp32_connect.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ESP32ConnectionAdapter extends TypeAdapter<ESP32Connection> {
  @override
  final int typeId = 1;

  @override
  ESP32Connection read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ESP32Connection(
      ipAddress: fields[0] as String?,
      ssid: fields[1] as String?,
      lastConnected: fields[2] as DateTime?,
      isConnected: fields[3] as bool,
      deviceName: fields[4] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, ESP32Connection obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.ipAddress)
      ..writeByte(1)
      ..write(obj.ssid)
      ..writeByte(2)
      ..write(obj.lastConnected)
      ..writeByte(3)
      ..write(obj.isConnected)
      ..writeByte(4)
      ..write(obj.deviceName);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ESP32ConnectionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
