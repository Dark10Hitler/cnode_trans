import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/combination.dart';
import '../models/document.dart';
import '../models/driver_profile.dart';
import '../models/power_unit.dart';
import '../models/trailer.dart';
import '../models/trip.dart';

/// Единое локальное хранилище CargoNode.
///
/// SQLite используется полностью офлайн.
/// Все изменения структуры БД выполняются через миграции.
class DatabaseService {
  DatabaseService._internal();

  static final DatabaseService instance = DatabaseService._internal();

  Database? _db;

  /// Получение единственного экземпляра базы данных.
  Future<Database> get database async {
    if (_db != null) {
      return _db!;
    }

    _db = await _initDb();
    return _db!;
  }

  // ============================================================
  // DATABASE INITIALIZATION
  // ============================================================

  Future<Database> _initDb() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'cargonode.db');

    print('[DATABASE] Initializing database at: $path');

    return openDatabase(
      path,
      version: 8,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: _onOpen,
    );
  }

  Future<void> _onOpen(Database db) async {
    print('[DATABASE] Database opened successfully');
    print('[DATABASE] Version: ${await db.getVersion()}');

    // Включаем foreign keys
    await db.execute('PRAGMA foreign_keys = ON');

    // Автоматическая проверка структуры таблицы документов при каждом старте
    await _ensureDocumentsTableSchema(db);
  }

  // ============================================================
  // CREATE DATABASE (NEW INSTALLATION)
  // ============================================================

  Future<void> _onCreate(Database db, int version) async {
    print('[DATABASE] Creating database schema (version $version)');

    await _createAllTables(db);
  }

  // ============================================================
  // DATABASE MIGRATIONS (UPGRADES)
  // ============================================================

  Future<void> _onUpgrade(
      Database db,
      int oldVersion,
      int newVersion,
      ) async {
    print('[DATABASE] Upgrading from version $oldVersion to $newVersion');

    // CRITICAL: If oldVersion is 0, create all tables
    if (oldVersion == 0) {
      print('[DATABASE] Old version is 0 - creating all tables');
      await _createAllTables(db);
      return;
    }

    // Version 1 -> 2: Add fuel consumption columns
    if (oldVersion < 2) {
      print('[DATABASE] Migration v1->v2: Adding fuel consumption columns');
      await _addColumnIfMissing(
        db,
        'trips',
        'baseFuelConsumption',
        'REAL NOT NULL DEFAULT 18',
      );
      await _addColumnIfMissing(
        db,
        'trips',
        'fuelConsumptionPerTon',
        'REAL NOT NULL DEFAULT 0.47',
      );
      await _addColumnIfMissing(db, 'trip_legs', 'cargoWeightTons', 'REAL');
      await _addColumnIfMissing(db, 'trip_legs', 'endpointType', 'TEXT');
      await _addColumnIfMissing(db, 'trip_legs', 'endpointDistanceKm', 'REAL');
    }

    // Version 2 -> 3: Ensure columns exist (idempotent)
    if (oldVersion < 3) {
      print('[DATABASE] Migration v2->v3: Ensuring columns exist');
      await _addColumnIfMissing(
        db,
        'trips',
        'baseFuelConsumption',
        'REAL NOT NULL DEFAULT 18',
      );
      await _addColumnIfMissing(
        db,
        'trips',
        'fuelConsumptionPerTon',
        'REAL NOT NULL DEFAULT 0.47',
      );
      await _addColumnIfMissing(db, 'trip_legs', 'cargoWeightTons', 'REAL');
      await _addColumnIfMissing(db, 'trip_legs', 'endpointType', 'TEXT');
      await _addColumnIfMissing(db, 'trip_legs', 'endpointDistanceKm', 'REAL');
    }

    // Version 3 -> 4: Verify all tables exist
    if (oldVersion < 4) {
      print('[DATABASE] Migration v3->v4: Verifying all tables exist');
      final tables = await _getExistingTables(db);
      print('[DATABASE] Existing tables: $tables');

      if (!tables.contains('power_units')) {
        print('[DATABASE] Creating missing power_units table');
        await db.execute('''
          CREATE TABLE power_units (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            category TEXT NOT NULL,
            brand TEXT NOT NULL,
            model TEXT,
            year INTEGER,
            vin TEXT,
            chassisVin TEXT,
            engineType TEXT,
            grossWeight REAL,
            curbWeight REAL,
            payloadCapacity REAL,
            wheelFormula TEXT,
            cabinType TEXT,
            axleCount INTEGER,
            environmentalClass TEXT,
            weightKg REAL,
            height REAL NOT NULL,
            width REAL NOT NULL,
            length REAL NOT NULL,
            hazmat INTEGER NOT NULL DEFAULT 0,
            hazmatClass TEXT,
            isActive INTEGER NOT NULL DEFAULT 0,
            isDeleted INTEGER NOT NULL DEFAULT 0,
            createdAt TEXT NOT NULL
          )
        ''');
      }

      if (!tables.contains('trailers')) {
        print('[DATABASE] Creating missing trailers table');
        await db.execute('''
          CREATE TABLE trailers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            kind TEXT NOT NULL,
            semiTrailerType TEXT,
            lightTrailerType TEXT,
            brand TEXT,
            model TEXT,
            vin TEXT,
            axleCount INTEGER,
            axleType TEXT,
            maxAxleLoad REAL,
            payloadCapacity REAL,
            emptyWeight REAL,
            height REAL NOT NULL,
            width REAL NOT NULL,
            length REAL NOT NULL,
            hazmat INTEGER NOT NULL DEFAULT 0,
            hazmatClass TEXT,
            isDeleted INTEGER NOT NULL DEFAULT 0,
            createdAt TEXT NOT NULL
          )
        ''');
      }

      if (!tables.contains('combinations')) {
        print('[DATABASE] Creating missing combinations table');
        await db.execute('''
          CREATE TABLE combinations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            powerUnitId INTEGER NOT NULL,
            trailerId INTEGER NOT NULL,
            label TEXT,
            combinedGrossWeightOverride REAL,
            combinedAxleLoadOverride REAL,
            isActive INTEGER NOT NULL DEFAULT 0,
            isDeleted INTEGER NOT NULL DEFAULT 0,
            createdAt TEXT NOT NULL,
            FOREIGN KEY(powerUnitId) REFERENCES power_units(id),
            FOREIGN KEY(trailerId) REFERENCES trailers(id)
          )
        ''');
      }

      if (!tables.contains('documents')) {
        print('[DATABASE] Creating missing documents table');
        await db.execute('''
          CREATE TABLE documents (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ownerType TEXT NOT NULL,
            ownerId INTEGER NOT NULL,
            category TEXT NOT NULL,
            name TEXT NOT NULL,
            fileType TEXT NOT NULL,
            expiryDate TEXT,
            filePath TEXT NOT NULL,
            createdAt TEXT NOT NULL
          )
        ''');
      }

      if (!tables.contains('driver_profile')) {
        print('[DATABASE] Creating missing driver_profile table');
        await db.execute('''
          CREATE TABLE driver_profile (
            id INTEGER PRIMARY KEY,
            fullName TEXT,
            licenseNumber TEXT,
            licenseCategories TEXT,
            licenseExpiry TEXT
          )
        ''');
      }

      if (!tables.contains('hos_state')) {
        print('[DATABASE] Creating missing hos_state table');
        await db.execute('''
          CREATE TABLE hos_state (
            id INTEGER PRIMARY KEY,
            enabled INTEGER NOT NULL DEFAULT 1,
            shiftStartedAt TEXT
          )
        ''');
      }

      if (!tables.contains('trips')) {
        print('[DATABASE] Creating missing trips table');
        await db.execute('''
          CREATE TABLE trips (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            label TEXT NOT NULL,
            currency TEXT NOT NULL DEFAULT 'MDL',
            status TEXT NOT NULL,
            startOdometerKm REAL NOT NULL,
            startFuelLiters REAL NOT NULL,
            cargoWeightTons REAL NOT NULL DEFAULT 0,
            agreedRate REAL NOT NULL,
            driverPayPerKm REAL NOT NULL DEFAULT 0,
            perDiemPerDay REAL NOT NULL DEFAULT 0,
            perDiemDays REAL NOT NULL DEFAULT 0,
            depreciationPerKm REAL NOT NULL DEFAULT 0,
            baseFuelConsumption REAL NOT NULL DEFAULT 18,
            fuelConsumptionPerTon REAL NOT NULL DEFAULT 0.47,
            finishOdometerKm REAL,
            finishFuelLiters REAL,
            startedAt TEXT NOT NULL,
            finishedAt TEXT
          )
        ''');
      }

      if (!tables.contains('trip_refuels')) {
        print('[DATABASE] Creating missing trip_refuels table');
        await db.execute('''
          CREATE TABLE trip_refuels (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            tripId INTEGER NOT NULL,
            liters REAL NOT NULL,
            amount REAL NOT NULL,
            photoPath TEXT,
            note TEXT,
            createdAt TEXT NOT NULL,
            FOREIGN KEY(tripId) REFERENCES trips(id)
          )
        ''');
      }

      if (!tables.contains('trip_legs')) {
        print('[DATABASE] Creating missing trip_legs table');
        await db.execute('''
          CREATE TABLE trip_legs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            tripId INTEGER NOT NULL,
            odometerKm REAL NOT NULL,
            cargoState TEXT NOT NULL,
            cargoWeightTons REAL,
            endpointType TEXT,
            endpointDistanceKm REAL,
            note TEXT,
            createdAt TEXT NOT NULL,
            FOREIGN KEY(tripId) REFERENCES trips(id)
          )
        ''');
      }

      if (!tables.contains('trip_expenses')) {
        print('[DATABASE] Creating missing trip_expenses table');
        await db.execute('''
          CREATE TABLE trip_expenses (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            tripId INTEGER NOT NULL,
            label TEXT NOT NULL,
            amount REAL NOT NULL,
            createdAt TEXT NOT NULL,
            FOREIGN KEY(tripId) REFERENCES trips(id)
          )
        ''');
      }
    }

    if (oldVersion < 5) {
      print('[DATABASE] Migration v4->v5: ensuring document owner columns');
      await _ensureDocumentsTableSchema(db);
    }

    // Version 5 -> 6: Soft Delete columns for vehicles and combinations
    if (oldVersion < 6) {
      print('[DATABASE] Migration v5->v6: Adding isDeleted column to transport tables');
      await _addColumnIfMissing(
        db,
        'power_units',
        'isDeleted',
        'INTEGER NOT NULL DEFAULT 0',
      );
      await _addColumnIfMissing(
        db,
        'trailers',
        'isDeleted',
        'INTEGER NOT NULL DEFAULT 0',
      );
      await _addColumnIfMissing(
        db,
        'combinations',
        'isDeleted',
        'INTEGER NOT NULL DEFAULT 0',
      );
    }

    // Version 6 -> 7: Add missing axleCount column to power_units
    if (oldVersion < 7) {
      print('[DATABASE] Migration v6->v7: Adding axleCount to power_units');
      await _addColumnIfMissing(
        db,
        'power_units',
        'axleCount',
        'INTEGER',
      );
    }
    // ДОБАВЛЕНА МИГРАЦИЯ НА ВЕРСИЮ 8
    if (oldVersion < 8) {
      print('[DATABASE] Migration v7->v8: ensuring document owner columns');
      await _ensureDocumentsTableSchema(db);
    }

    print('[DATABASE] Upgrade complete');
  }

  // ============================================================
  // CREATE ALL TABLES
  // ============================================================

  // ============================================================
  // ENSURE DOCUMENTS TABLE SCHEMA
  // ============================================================

  /// Гарантирует наличие таблицы documents и совпадение её структуры с текущей моделью.
  Future<void> _ensureDocumentsTableSchema(Database db) async {
    final tables = await _getExistingTables(db);

    if (!tables.contains('documents')) {
      await db.execute('''
        CREATE TABLE documents (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          ownerType TEXT NOT NULL DEFAULT 'driver',
          ownerId INTEGER NOT NULL DEFAULT 1,
          category TEXT NOT NULL DEFAULT 'general',
          name TEXT NOT NULL DEFAULT '',
          fileType TEXT NOT NULL DEFAULT 'jpg',
          expiryDate TEXT,
          filePath TEXT NOT NULL DEFAULT '',
          createdAt TEXT NOT NULL DEFAULT ''
        )
      ''');
      print('[DATABASE] ✓ documents table created');
      return;
    }

    // Получаем текущие колонки таблицы
    final rows = await db.rawQuery('PRAGMA table_info(documents)');
    final existingColumns = rows
        .map((row) => (row['name'] as String).toLowerCase())
        .toSet();

    // Если в таблице осталась устаревшая колонка vehicleId (NOT NULL)
    if (existingColumns.contains('vehicleid')) {
      print('[DATABASE] Legacy vehicleId column found. Rebuilding documents table...');
      await db.transaction((txn) async {
        // 1. Создаем правильную таблицу во временный объект
        await txn.execute('''
          CREATE TABLE documents_new (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ownerType TEXT NOT NULL DEFAULT 'driver',
            ownerId INTEGER NOT NULL DEFAULT 1,
            category TEXT NOT NULL DEFAULT 'general',
            name TEXT NOT NULL DEFAULT '',
            fileType TEXT NOT NULL DEFAULT 'jpg',
            expiryDate TEXT,
            filePath TEXT NOT NULL DEFAULT '',
            createdAt TEXT NOT NULL DEFAULT ''
          )
        ''');

        // 2. Переносим существующие данные с безопасной подстановкой полей
        final hasOwnerType = existingColumns.contains('ownertype');
        final hasOwnerId = existingColumns.contains('ownerid');
        final hasCategory = existingColumns.contains('category');

        final ownerTypeExpr = hasOwnerType ? 'ownerType' : "'powerUnit'";
        final ownerIdExpr = hasOwnerId ? 'ownerId' : 'vehicleId';
        final categoryExpr = hasCategory ? 'category' : "'general'";

        await txn.execute('''
          INSERT INTO documents_new (id, ownerType, ownerId, category, name, fileType, expiryDate, filePath, createdAt)
          SELECT 
            id, 
            $ownerTypeExpr, 
            $ownerIdExpr, 
            $categoryExpr, 
            COALESCE(name, ''), 
            COALESCE(fileType, 'jpg'), 
            expiryDate, 
            COALESCE(filePath, ''), 
            COALESCE(createdAt, '')
          FROM documents
        ''');

        // 3. Заменяем старую таблицу новой
        await txn.execute('DROP TABLE documents');
        await txn.execute('ALTER TABLE documents_new RENAME TO documents');
      });
      print('[DATABASE] ✓ documents table successfully migrated');
      return;
    }

    // Добавляем недостающие колонки (если это новые поля)
    final Map<String, String> requiredColumns = {
      'ownertype': "ALTER TABLE documents ADD COLUMN ownerType TEXT NOT NULL DEFAULT 'driver'",
      'ownerid': "ALTER TABLE documents ADD COLUMN ownerId INTEGER NOT NULL DEFAULT 1",
      'category': "ALTER TABLE documents ADD COLUMN category TEXT NOT NULL DEFAULT 'general'",
      'name': "ALTER TABLE documents ADD COLUMN name TEXT NOT NULL DEFAULT ''",
      'filetype': "ALTER TABLE documents ADD COLUMN fileType TEXT NOT NULL DEFAULT 'jpg'",
      'expirydate': "ALTER TABLE documents ADD COLUMN expiryDate TEXT",
      'filepath': "ALTER TABLE documents ADD COLUMN filePath TEXT NOT NULL DEFAULT ''",
      'createdat': "ALTER TABLE documents ADD COLUMN createdAt TEXT NOT NULL DEFAULT ''",
    };

    for (final entry in requiredColumns.entries) {
      if (!existingColumns.contains(entry.key)) {
        print('[DATABASE] Adding missing column: documents.${entry.key}');
        try {
          await db.execute(entry.value);
        } catch (e) {
          print('[DATABASE] Error adding column ${entry.key}: $e');
        }
      }
    }
  }

  Future<void> _createAllTables(Database db) async {
    print('[DATABASE] Creating all tables...');

    // POWER UNITS
    await db.execute('''
      CREATE TABLE IF NOT EXISTS power_units (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category TEXT NOT NULL,
        brand TEXT NOT NULL,
        model TEXT,
        year INTEGER,
        vin TEXT,
        chassisVin TEXT,
        engineType TEXT,
        grossWeight REAL,
        curbWeight REAL,
        payloadCapacity REAL,
        wheelFormula TEXT,
        cabinType TEXT,
        environmentalClass TEXT,
        weightKg REAL,
        height REAL NOT NULL,
        width REAL NOT NULL,
        length REAL NOT NULL,
        hazmat INTEGER NOT NULL DEFAULT 0,
        hazmatClass TEXT,
        isActive INTEGER NOT NULL DEFAULT 0,
        isDeleted INTEGER NOT NULL DEFAULT 0,
        createdAt TEXT NOT NULL
      )
    ''');
    print('[DATABASE] ✓ power_units table created');

    // TRAILERS
    await db.execute('''
      CREATE TABLE IF NOT EXISTS trailers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        kind TEXT NOT NULL,
        semiTrailerType TEXT,
        lightTrailerType TEXT,
        brand TEXT,
        model TEXT,
        vin TEXT,
        axleCount INTEGER,
        axleType TEXT,
        maxAxleLoad REAL,
        payloadCapacity REAL,
        emptyWeight REAL,
        height REAL NOT NULL,
        width REAL NOT NULL,
        length REAL NOT NULL,
        hazmat INTEGER NOT NULL DEFAULT 0,
        hazmatClass TEXT,
        isDeleted INTEGER NOT NULL DEFAULT 0,
        createdAt TEXT NOT NULL
      )
    ''');
    print('[DATABASE] ✓ trailers table created');

    // COMBINATIONS
    await db.execute('''
      CREATE TABLE IF NOT EXISTS combinations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        powerUnitId INTEGER NOT NULL,
        trailerId INTEGER NOT NULL,
        label TEXT,
        combinedGrossWeightOverride REAL,
        combinedAxleLoadOverride REAL,
        isActive INTEGER NOT NULL DEFAULT 0,
        isDeleted INTEGER NOT NULL DEFAULT 0,
        createdAt TEXT NOT NULL,
        FOREIGN KEY(powerUnitId) REFERENCES power_units(id),
        FOREIGN KEY(trailerId) REFERENCES trailers(id)
      )
    ''');
    print('[DATABASE] ✓ combinations table created');

    // DOCUMENTS
    await db.execute('''
      CREATE TABLE IF NOT EXISTS documents (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ownerType TEXT NOT NULL,
        ownerId INTEGER NOT NULL,
        category TEXT NOT NULL,
        name TEXT NOT NULL,
        fileType TEXT NOT NULL,
        expiryDate TEXT,
        filePath TEXT NOT NULL,
        createdAt TEXT NOT NULL
      )
    ''');
    print('[DATABASE] ✓ documents table created');

    // DRIVER PROFILE
    await db.execute('''
      CREATE TABLE IF NOT EXISTS driver_profile (
        id INTEGER PRIMARY KEY,
        fullName TEXT,
        licenseNumber TEXT,
        licenseCategories TEXT,
        licenseExpiry TEXT
      )
    ''');
    print('[DATABASE] ✓ driver_profile table created');

    // HOS STATE
    await db.execute('''
      CREATE TABLE IF NOT EXISTS hos_state (
        id INTEGER PRIMARY KEY,
        enabled INTEGER NOT NULL DEFAULT 1,
        shiftStartedAt TEXT
      )
    ''');
    print('[DATABASE] ✓ hos_state table created');

    // TRIPS
    await db.execute('''
      CREATE TABLE IF NOT EXISTS trips (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        label TEXT NOT NULL,
        currency TEXT NOT NULL DEFAULT 'MDL',
        status TEXT NOT NULL,
        startOdometerKm REAL NOT NULL,
        startFuelLiters REAL NOT NULL,
        cargoWeightTons REAL NOT NULL DEFAULT 0,
        agreedRate REAL NOT NULL,
        driverPayPerKm REAL NOT NULL DEFAULT 0,
        perDiemPerDay REAL NOT NULL DEFAULT 0,
        perDiemDays REAL NOT NULL DEFAULT 0,
        depreciationPerKm REAL NOT NULL DEFAULT 0,
        baseFuelConsumption REAL NOT NULL DEFAULT 18,
        fuelConsumptionPerTon REAL NOT NULL DEFAULT 0.47,
        finishOdometerKm REAL,
        finishFuelLiters REAL,
        startedAt TEXT NOT NULL,
        finishedAt TEXT
      )
    ''');
    print('[DATABASE] ✓ trips table created');

    // TRIP REFUELS
    await db.execute('''
      CREATE TABLE IF NOT EXISTS trip_refuels (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tripId INTEGER NOT NULL,
        liters REAL NOT NULL,
        amount REAL NOT NULL,
        photoPath TEXT,
        note TEXT,
        createdAt TEXT NOT NULL,
        FOREIGN KEY(tripId) REFERENCES trips(id)
      )
    ''');
    print('[DATABASE] ✓ trip_refuels table created');

    // TRIP LEGS
    await db.execute('''
      CREATE TABLE IF NOT EXISTS trip_legs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tripId INTEGER NOT NULL,
        odometerKm REAL NOT NULL,
        cargoState TEXT NOT NULL,
        cargoWeightTons REAL,
        endpointType TEXT,
        endpointDistanceKm REAL,
        note TEXT,
        createdAt TEXT NOT NULL,
        FOREIGN KEY(tripId) REFERENCES trips(id)
      )
    ''');
    print('[DATABASE] ✓ trip_legs table created');

    // TRIP EXPENSES
    await db.execute('''
      CREATE TABLE IF NOT EXISTS trip_expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tripId INTEGER NOT NULL,
        label TEXT NOT NULL,
        amount REAL NOT NULL,
        createdAt TEXT NOT NULL,
        FOREIGN KEY(tripId) REFERENCES trips(id)
      )
    ''');
    print('[DATABASE] ✓ trip_expenses table created');

    print('[DATABASE] All tables created successfully');
  }

  // ============================================================
  // HELPER METHODS
  // ============================================================

  /// Добавляет колонку только если её ещё нет.
  Future<void> _addColumnIfMissing(
      Database db,
      String table,
      String column,
      String definition,
      ) async {
    try {
      final result = await db.rawQuery('PRAGMA table_info($table)');
      final exists = result.any(
            (row) => (row['name'] as String).toLowerCase() == column.toLowerCase(),
      );

      if (!exists) {
        print('[DATABASE] Adding column: $table.$column');
        await db.execute(
          'ALTER TABLE $table ADD COLUMN $column $definition',
        );
      }
    } catch (e) {
      print('[DATABASE] Error adding column $column to $table: $e');
    }
  }

  /// Получает список всех существующих таблиц.
  Future<List<String>> _getExistingTables(Database db) async {
    final result = await db.query(
      'sqlite_master',
      where: "type='table'",
      columns: ['name'],
    );
    return result.map((row) => row['name'] as String).toList();
  }

  // ============================================================
  // POWER UNITS
  // ============================================================

  Future<int> insertPowerUnit(PowerUnit unit) async {
    try {
      final db = await database;
      final map = Map<String, dynamic>.from(unit.toMap());
      map.remove('id');

      final id = await db.insert('power_units', map);
      print('[DATABASE] ✓ Power unit inserted with id: $id');
      return id;
    } catch (e) {
      print('[DATABASE] ✗ Error inserting power unit: $e');
      rethrow;
    }
  }

  Future<int> updatePowerUnit(PowerUnit unit) async {
    try {
      final db = await database;
      final count = await db.update(
        'power_units',
        unit.toMap(),
        where: 'id = ?',
        whereArgs: [unit.id],
      );
      print('[DATABASE] ✓ Power unit ${unit.id} updated');
      return count;
    } catch (e) {
      print('[DATABASE] ✗ Error updating power unit: $e');
      rethrow;
    }
  }

  /// Мягкое удаление тягача и всех связок с ним
  Future<int> softDeletePowerUnit(int id) async {
    try {
      final db = await database;
      final count = await db.transaction((txn) async {
        await txn.update(
          'power_units',
          {'isDeleted': 1},
          where: 'id = ?',
          whereArgs: [id],
        );
        await txn.update(
          'combinations',
          {'isDeleted': 1},
          where: 'powerUnitId = ?',
          whereArgs: [id],
        );
        return 1;
      });
      print('[DATABASE] ✓ Power unit $id soft-deleted');
      return count;
    } catch (e) {
      print('[DATABASE] ✗ Error soft deleting power unit: $e');
      rethrow;
    }
  }

  /// Совместимость с прошлым API — выполняет мягкое удаление
  Future<int> deletePowerUnit(int id) async {
    return softDeletePowerUnit(id);
  }

  Future<List<PowerUnit>> getPowerUnits() async {
    try {
      final db = await database;
      final rows = await db.query(
        'power_units',
        where: 'isDeleted = 0 OR isDeleted IS NULL',
        orderBy: 'createdAt DESC',
      );
      return rows.map(PowerUnit.fromMap).toList();
    } catch (e) {
      print('[DATABASE] ✗ Error fetching power units: $e');
      return [];
    }
  }

  Future<void> setActivePowerUnit(int id) async {
    try {
      final db = await database;
      await db.transaction((txn) async {
        await txn.update('power_units', {'isActive': 0});
        await txn.update('combinations', {'isActive': 0});
        await txn.update(
          'power_units',
          {'isActive': 1},
          where: 'id = ?',
          whereArgs: [id],
        );
      });
      print('[DATABASE] ✓ Power unit $id set as active');
    } catch (e) {
      print('[DATABASE] ✗ Error setting active power unit: $e');
      rethrow;
    }
  }

  // ============================================================
  // TRAILERS
  // ============================================================

  Future<int> insertTrailer(Trailer trailer) async {
    try {
      final db = await database;
      final map = Map<String, dynamic>.from(trailer.toMap());
      map.remove('id');

      final id = await db.insert('trailers', map);
      print('[DATABASE] ✓ Trailer inserted with id: $id');
      return id;
    } catch (e) {
      print('[DATABASE] ✗ Error inserting trailer: $e');
      rethrow;
    }
  }

  Future<int> updateTrailer(Trailer trailer) async {
    try {
      final db = await database;
      final count = await db.update(
        'trailers',
        trailer.toMap(),
        where: 'id = ?',
        whereArgs: [trailer.id],
      );
      print('[DATABASE] ✓ Trailer ${trailer.id} updated');
      return count;
    } catch (e) {
      print('[DATABASE] ✗ Error updating trailer: $e');
      rethrow;
    }
  }

  /// Мягкое удаление прицепа и всех его комбинаций
  Future<int> softDeleteTrailer(int id) async {
    try {
      final db = await database;
      final count = await db.transaction((txn) async {
        await txn.update(
          'trailers',
          {'isDeleted': 1},
          where: 'id = ?',
          whereArgs: [id],
        );
        await txn.update(
          'combinations',
          {'isDeleted': 1},
          where: 'trailerId = ?',
          whereArgs: [id],
        );
        return 1;
      });
      print('[DATABASE] ✓ Trailer $id soft-deleted');
      return count;
    } catch (e) {
      print('[DATABASE] ✗ Error soft deleting trailer: $e');
      rethrow;
    }
  }

  /// Совместимость с прошлым API — выполняет мягкое удаление
  Future<int> deleteTrailer(int id) async {
    return softDeleteTrailer(id);
  }

  Future<List<Trailer>> getTrailers() async {
    try {
      final db = await database;
      final rows = await db.query(
        'trailers',
        where: 'isDeleted = 0 OR isDeleted IS NULL',
        orderBy: 'createdAt DESC',
      );
      return rows.map(Trailer.fromMap).toList();
    } catch (e) {
      print('[DATABASE] ✗ Error fetching trailers: $e');
      return [];
    }
  }

  // ============================================================
  // COMBINATIONS
  // ============================================================

  Future<int> insertCombination(VehicleCombination combo) async {
    try {
      final db = await database;
      final map = Map<String, dynamic>.from(combo.toMap());
      map.remove('id');

      final id = await db.insert('combinations', map);
      print('[DATABASE] ✓ Combination inserted with id: $id');
      return id;
    } catch (e) {
      print('[DATABASE] ✗ Error inserting combination: $e');
      rethrow;
    }
  }

  Future<int> updateCombination(VehicleCombination combo) async {
    try {
      final db = await database;
      final count = await db.update(
        'combinations',
        combo.toMap(),
        where: 'id = ?',
        whereArgs: [combo.id],
      );
      print('[DATABASE] ✓ Combination ${combo.id} updated');
      return count;
    } catch (e) {
      print('[DATABASE] ✗ Error updating combination: $e');
      rethrow;
    }
  }

  /// Мягкое удаление связки
  Future<int> softDeleteCombination(int id) async {
    try {
      final db = await database;
      final count = await db.update(
        'combinations',
        {'isDeleted': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
      print('[DATABASE] ✓ Combination $id soft-deleted');
      return count;
    } catch (e) {
      print('[DATABASE] ✗ Error soft deleting combination: $e');
      rethrow;
    }
  }

  /// Совместимость с прошлым API — выполняет мягкое удаление
  Future<int> deleteCombination(int id) async {
    return softDeleteCombination(id);
  }

  Future<List<VehicleCombination>> getCombinations() async {
    try {
      final db = await database;
      final rows = await db.query(
        'combinations',
        where: 'isDeleted = 0 OR isDeleted IS NULL',
        orderBy: 'createdAt DESC',
      );
      return rows.map(VehicleCombination.fromMap).toList();
    } catch (e) {
      print('[DATABASE] ✗ Error fetching combinations: $e');
      return [];
    }
  }

  Future<void> setActiveCombination(int id) async {
    try {
      final db = await database;
      await db.transaction((txn) async {
        await txn.update('power_units', {'isActive': 0});
        await txn.update('combinations', {'isActive': 0});
        await txn.update(
          'combinations',
          {'isActive': 1},
          where: 'id = ?',
          whereArgs: [id],
        );
      });
      print('[DATABASE] ✓ Combination $id set as active');
    } catch (e) {
      print('[DATABASE] ✗ Error setting active combination: $e');
      rethrow;
    }
  }

  // ============================================================
  // DOCUMENTS
  // ============================================================

  Future<int> insertDocument(AppDocument doc) async {
    try {
      final db = await database;
      final map = Map<String, dynamic>.from(doc.toMap());
      map.remove('id');

      final id = await db.insert('documents', map);
      print('[DATABASE] ✓ Document inserted with id: $id');
      return id;
    } catch (e) {
      print('[DATABASE] ✗ Error inserting document: $e');
      rethrow;
    }
  }

  Future<int> updateDocument(AppDocument doc) async {
    try {
      final db = await database;
      final count = await db.update(
        'documents',
        doc.toMap(),
        where: 'id = ?',
        whereArgs: [doc.id],
      );
      print('[DATABASE] ✓ Document ${doc.id} updated');
      return count;
    } catch (e) {
      print('[DATABASE] ✗ Error updating document: $e');
      rethrow;
    }
  }

  Future<List<AppDocument>> getAllDocuments() async {
    try {
      final db = await database;
      final rows = await db.query('documents', orderBy: 'createdAt DESC');
      return rows.map(AppDocument.fromMap).toList();
    } catch (e) {
      print('[DATABASE] ✗ Error fetching all documents: $e');
      return [];
    }
  }

  Future<int> deleteDocument(int id) async {
    try {
      final db = await database;
      final count = await db.delete(
        'documents',
        where: 'id = ?',
        whereArgs: [id],
      );
      print('[DATABASE] ✓ Document $id deleted');
      return count;
    } catch (e) {
      print('[DATABASE] ✗ Error deleting document: $e');
      rethrow;
    }
  }

  Future<List<AppDocument>> getDocuments(
      DocumentOwnerType ownerType,
      int ownerId,
      ) async {
    try {
      final db = await database;
      final rows = await db.query(
        'documents',
        where: 'ownerType = ? AND ownerId = ?',
        whereArgs: [ownerType.name, ownerId],
        orderBy: 'createdAt DESC',
      );
      return rows.map(AppDocument.fromMap).toList();
    } catch (e) {
      print('[DATABASE] ✗ Error fetching documents: $e');
      return [];
    }
  }

  // ============================================================
  // DRIVER PROFILE
  // ============================================================

  Future<DriverProfile?> getDriverProfile() async {
    try {
      final db = await database;
      final rows = await db.query(
        'driver_profile',
        where: 'id = ${DriverProfile.singletonId}',
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return DriverProfile.fromMap(rows.first);
    } catch (e) {
      print('[DATABASE] ✗ Error fetching driver profile: $e');
      return null;
    }
  }

  Future<void> saveDriverProfile(DriverProfile profile) async {
    try {
      final db = await database;
      final map = Map<String, dynamic>.from(profile.toMap());
      map['id'] = DriverProfile.singletonId;

      await db.insert(
        'driver_profile',
        map,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      print('[DATABASE] ✓ Driver profile saved');
    } catch (e) {
      print('[DATABASE] ✗ Error saving driver profile: $e');
      rethrow;
    }
  }

  // ============================================================
  // HOS STATE
  // ============================================================

  Future<({bool enabled, DateTime? shiftStartedAt})> getHosState() async {
    try {
      final db = await database;
      final rows = await db.query(
        'hos_state',
        where: 'id = 1',
        limit: 1,
      );

      if (rows.isEmpty) {
        return (enabled: true, shiftStartedAt: null);
      }

      final row = rows.first;
      final enabled = (row['enabled'] as int? ?? 1) == 1;
      final startedAt = row['shiftStartedAt'] != null
          ? DateTime.parse(row['shiftStartedAt'] as String)
          : null;

      return (enabled: enabled, shiftStartedAt: startedAt);
    } catch (e) {
      print('[DATABASE] ✗ Error fetching HOS state: $e');
      return (enabled: true, shiftStartedAt: null);
    }
  }

  Future<void> saveHosState({
    required bool enabled,
    DateTime? shiftStartedAt,
  }) async {
    try {
      final db = await database;
      await db.insert(
        'hos_state',
        {
          'id': 1,
          'enabled': enabled ? 1 : 0,
          'shiftStartedAt': shiftStartedAt?.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      print('[DATABASE] ✓ HOS state saved');
    } catch (e) {
      print('[DATABASE] ✗ Error saving HOS state: $e');
      rethrow;
    }
  }

  // ============================================================
  // TRIPS
  // ============================================================

  Future<int> insertTrip(TripRecord trip) async {
    try {
      final db = await database;
      final map = Map<String, dynamic>.from(trip.toMap());
      map.remove('id');

      final id = await db.insert('trips', map);
      print('[DATABASE] ✓ Trip inserted with id: $id');
      return id;
    } catch (e) {
      print('[DATABASE] ✗ Error inserting trip: $e');
      rethrow;
    }
  }

  Future<void> updateTrip(TripRecord trip) async {
    try {
      final db = await database;
      await db.update(
        'trips',
        trip.toMap(),
        where: 'id = ?',
        whereArgs: [trip.id],
      );
      print('[DATABASE] ✓ Trip ${trip.id} updated');
    } catch (e) {
      print('[DATABASE] ✗ Error updating trip: $e');
      rethrow;
    }
  }

  Future<void> deleteTrip(int id) async {
    try {
      final db = await database;
      await db.transaction((txn) async {
        await txn.delete('trip_refuels', where: 'tripId = ?', whereArgs: [id]);
        await txn.delete('trip_legs', where: 'tripId = ?', whereArgs: [id]);
        await txn.delete('trip_expenses', where: 'tripId = ?', whereArgs: [id]);
        await txn.delete('trips', where: 'id = ?', whereArgs: [id]);
      });
      print('[DATABASE] ✓ Trip $id deleted');
    } catch (e) {
      print('[DATABASE] ✗ Error deleting trip: $e');
      rethrow;
    }
  }

  Future<List<TripRecord>> getTrips() async {
    final db = await database;
    final rows = await db.query('trips', orderBy: 'startedAt DESC');
    return rows.map(TripRecord.fromMap).toList();
  }

  Future<int> insertRefuel(TripRefuel refuel) async {
    final db = await database;
    final map = Map<String, dynamic>.from(refuel.toMap())..remove('id');
    return db.insert('trip_refuels', map);
  }

  Future<List<TripRefuel>> getRefuels(int tripId) async {
    final db = await database;
    final rows = await db.query(
      'trip_refuels',
      where: 'tripId = ?',
      whereArgs: [tripId],
      orderBy: 'createdAt ASC',
    );
    return rows.map(TripRefuel.fromMap).toList();
  }

  Future<int> insertLeg(TripLeg leg) async {
    final db = await database;
    final map = Map<String, dynamic>.from(leg.toMap())..remove('id');
    return db.insert('trip_legs', map);
  }

  Future<List<TripLeg>> getLegs(int tripId) async {
    final db = await database;
    final rows = await db.query(
      'trip_legs',
      where: 'tripId = ?',
      whereArgs: [tripId],
      orderBy: 'createdAt ASC',
    );
    return rows.map(TripLeg.fromMap).toList();
  }

  Future<int> insertExpense(TripExpense expense) async {
    final db = await database;
    final map = Map<String, dynamic>.from(expense.toMap())..remove('id');
    return db.insert('trip_expenses', map);
  }

  Future<List<TripExpense>> getExpenses(int tripId) async {
    final db = await database;
    final rows = await db.query(
      'trip_expenses',
      where: 'tripId = ?',
      whereArgs: [tripId],
      orderBy: 'createdAt ASC',
    );
    return rows.map(TripExpense.fromMap).toList();
  }
}