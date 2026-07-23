import 'package:hive/hive.dart';

enum CallDirection { incoming, outgoing, missed, rejected }

class CallLogEntry {
  CallLogEntry({
    required this.id,
    required this.number,
    required this.direction,
    required this.timestamp,
    this.displayName,
    this.durationSeconds = 0,
  });

  final String id;
  final String number;
  final String? displayName;
  final CallDirection direction;
  final DateTime timestamp;
  final int durationSeconds;

  String get title => (displayName != null && displayName!.trim().isNotEmpty)
      ? displayName!
      : number;
}

class CallLogEntryAdapter extends TypeAdapter<CallLogEntry> {
  @override
  final int typeId = 0;

  @override
  CallLogEntry read(BinaryReader reader) {
    final fieldCount = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < fieldCount; i++) reader.readByte(): reader.read(),
    };
    return CallLogEntry(
      id: fields[0] as String,
      number: fields[1] as String,
      displayName: fields[2] as String?,
      direction: CallDirection.values[fields[3] as int],
      timestamp: DateTime.fromMillisecondsSinceEpoch(fields[4] as int),
      durationSeconds: fields[5] as int,
    );
  }

  @override
  void write(BinaryWriter writer, CallLogEntry obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.number)
      ..writeByte(2)
      ..write(obj.displayName)
      ..writeByte(3)
      ..write(obj.direction.index)
      ..writeByte(4)
      ..write(obj.timestamp.millisecondsSinceEpoch)
      ..writeByte(5)
      ..write(obj.durationSeconds);
  }
}
