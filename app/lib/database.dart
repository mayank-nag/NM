import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

part 'database.g.dart';

class Messages extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get type => text().withDefault(const Constant('text'))(); // 'text', 'photo', 'share'
  TextColumn get content => text()();
  TextColumn get mediaPath => text().nullable()(); // local file path for photos
  TextColumn get shareUrl => text().nullable()(); // URL for shared content
  TextColumn get shareTitle => text().nullable()(); // title for shared content
  BoolColumn get isMe => boolean()();
  DateTimeColumn get timestamp => dateTime()();
}

class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Stores whiteboard strokes persistently so the canvas survives app restarts.
class WhiteboardStrokes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get pointsJson => text()(); // JSON-encoded list of [dx, dy] pairs
  TextColumn get color => text()(); // hex color string e.g. '#FF6B6B'
  RealColumn get width => real()(); // stroke width
  BoolColumn get isMe => boolean()(); // true = drawn by me, false = from partner
  DateTimeColumn get timestamp => dateTime()();
}

@DriftDatabase(tables: [Messages, Settings, WhiteboardStrokes])
class AppDatabase extends _$AppDatabase {
  AppDatabase._() : super(_openConnection());

  static AppDatabase? _instance;
  static AppDatabase get instance => _instance ??= AppDatabase._();

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(settings);
          }
          if (from < 3) {
            await m.addColumn(messages, messages.type);
            await m.addColumn(messages, messages.mediaPath);
          }
          if (from < 4) {
            await m.addColumn(messages, messages.shareUrl);
            await m.addColumn(messages, messages.shareTitle);
          }
          if (from < 5) {
            await m.createTable(whiteboardStrokes);
          }
        },
      );

  // ── Messages ──

  Future<int> insertMessage(String content, bool isMe, DateTime timestamp,
      {String type = 'text', String? mediaPath, String? shareUrl, String? shareTitle}) {
    return into(messages).insert(
      MessagesCompanion.insert(
        content: content,
        isMe: isMe,
        timestamp: timestamp,
        type: Value(type),
        mediaPath: Value(mediaPath),
        shareUrl: Value(shareUrl),
        shareTitle: Value(shareTitle),
      ),
    );
  }

  Stream<List<Message>> watchMessages() {
    return (select(messages)..orderBy([(m) => OrderingTerm.asc(m.timestamp)]))
        .watch();
  }

  Future<List<Message>> getAllMessages() {
    return (select(messages)..orderBy([(m) => OrderingTerm.asc(m.timestamp)]))
        .get();
  }

  // ── Settings (key-value) ──

  Future<String?> getSetting(String key) async {
    final row = await (select(settings)..where((s) => s.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> setSetting(String key, String value) async {
    await into(settings).insertOnConflictUpdate(
      SettingsCompanion.insert(key: key, value: value),
    );
  }

  Stream<String?> watchSetting(String key) {
    return (select(settings)..where((s) => s.key.equals(key)))
        .watchSingleOrNull()
        .map((row) => row?.value);
  }

  // ── Nickname helpers ──

  Future<String?> getMyName() => getSetting('my_name');
  Future<String?> getPartnerName() => getSetting('partner_name');
  Future<void> setMyName(String name) => setSetting('my_name', name);
  Future<void> setPartnerName(String name) => setSetting('partner_name', name);

  Stream<String?> watchMyName() => watchSetting('my_name');
  Stream<String?> watchPartnerName() => watchSetting('partner_name');

  // ── Whiteboard strokes ──

  Future<int> insertStroke({
    required String pointsJson,
    required String color,
    required double width,
    required bool isMe,
  }) {
    return into(whiteboardStrokes).insert(
      WhiteboardStrokesCompanion.insert(
        pointsJson: pointsJson,
        color: color,
        width: width,
        isMe: isMe,
        timestamp: DateTime.now(),
      ),
    );
  }

  Future<List<WhiteboardStroke>> getAllStrokes() {
    return (select(whiteboardStrokes)
          ..orderBy([(s) => OrderingTerm.asc(s.timestamp)]))
        .get();
  }

  Stream<List<WhiteboardStroke>> watchStrokes() {
    return (select(whiteboardStrokes)
          ..orderBy([(s) => OrderingTerm.asc(s.timestamp)]))
        .watch();
  }

  Future<void> clearAllStrokes() {
    return delete(whiteboardStrokes).go();
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'nm_chat.db'));
    return NativeDatabase.createInBackground(file);
  });
}
