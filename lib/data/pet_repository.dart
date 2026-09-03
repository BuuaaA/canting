import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../pet/pet_data.dart';

/// Reads and writes the single-row [PetData] table.
///
/// The pet is stored as one JSON blob: `PetData` carries ~22 evolving fields
/// (vitality decay, evolution history, streaks), and explicit columns would
/// need a schema migration for every new field.
class PetRepository {
  PetRepository({required Database Function() database})
    : _databaseGetter = database;

  final Database Function() _databaseGetter;

  Database get _database => _databaseGetter();

  Future<PetData?> getPet() async {
    final rows = await _database.query('pet_states', limit: 1);
    if (rows.isEmpty) {
      return null;
    }
    return PetData.fromJson(
      (jsonDecode(rows.single['json_data']! as String) as Map)
          .cast<String, dynamic>(),
    );
  }

  Future<void> savePet(PetData pet) async {
    await _database.insert(
      'pet_states',
      {
        'id': 1,
        'json_data': jsonEncode(pet.toJson()),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
