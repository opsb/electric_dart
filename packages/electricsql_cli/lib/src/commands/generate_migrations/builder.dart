import 'dart:convert';
import 'dart:io';

import 'package:code_builder/code_builder.dart';
import 'package:dart_style/dart_style.dart';
import 'package:electricsql/migrators.dart';
import 'package:electricsql_cli/src/commands/generate_migrations/prisma.dart';
import 'package:path/path.dart' as path;

Future<void> buildMigrations(
  Directory migrationsFolder,
  File migrationsFile,
) async {
  final migrations = await loadMigrations(migrationsFolder);

  final outParent = migrationsFile.parent;
  if (!outParent.existsSync()) {
    await outParent.create(recursive: true);
  }

  final contents = generateMigrationsDartCode(migrations);

  // Update the configuration file
  await migrationsFile.writeAsString(contents);
}

Future<List<Migration>> loadMigrations(Directory migrationsFolder) async {
  final migrationDirNames = await getMigrationNames(migrationsFolder);
  final migrationFiles = migrationDirNames.map(
    (dirName) =>
        File(path.join(migrationsFolder.path, dirName, 'metadata.json')),
  );
  final migrationsMetadatas = await Future.wait(
    migrationFiles.map(_readMetadataFile),
  );
  return migrationsMetadatas.map(makeMigration).toList();
}

/// Reads the specified metadata file.
/// @param path Path to the metadata file.
/// @returns A promise that resolves with the metadata.
Future<MetaData> _readMetadataFile(File file) async {
  try {
    final data = await file.readAsString();
    final jsonData = json.decode(data);

    if (jsonData is! Map<String, Object?>) {
      throw Exception(
          'Migration file ${file.path} has wrong format, expected JSON object '
          'but found something else.');
    }

    return parseMetadata(jsonData);
  } catch (e, st) {
    throw Exception(
      'Error while parsing migration file ${file.path}. $e\n$st',
    );
  }
}

/// Reads the provided `migrationsFolder` and returns an array
/// of all the migrations that are present in that folder.
/// Each of those migrations are in their respective folder.
/// @param migrationsFolder
Future<List<String>> getMigrationNames(Directory migrationsFolder) async {
  final dirs = migrationsFolder.listSync().whereType<Directory>();
  // the directory names encode the order of the migrations
  // therefore we sort them by name to get them in chronological order
  final dirNames = dirs.map((dir) => dir.path).toList()..sort();
  return dirNames;
}

const kDriftImport = 'package:drift/drift.dart';
const kElectricSqlDriftImport = 'package:electricsql/drivers/drift.dart';

String generateMigrationsDartCode(List<Migration> migrations) {
  const kElectricSqlImport = 'package:electricsql/electricsql.dart';

  final migrationReference = refer('Migration', kElectricSqlImport);

  // Migrations
  final List<Expression> migrationExpressions = migrations.map((m) {
    final stmts = m.statements.map((stmt) => literal(stmt)).toList();
    final stmtsList = literalList(stmts);
    return migrationReference.newInstance([], {
      'statements': stmtsList,
      'version': literal(m.version),
    });
  }).toList();

  // UnmodifiableListView<Migration>
  final unmodifListReference = TypeReference(
    (b) => b
      ..url = 'dart:collection'
      ..symbol = 'UnmodifiableListView'
      ..types.add(migrationReference.type),
  );

  // global final immutable field for the migrations
  final electricMigrationsField = Field(
    (b) => b
      ..name = 'kElectricMigrations'
      ..modifier = FieldModifier.final$
      ..assignment = unmodifListReference.newInstance([
        literalList(migrationExpressions, migrationReference),
      ]).code,
  );

  return _buildLibCode(
    (b) => b..body.add(electricMigrationsField),
  );
}

String _buildLibCode(void Function(LibraryBuilder b) updateLib) {
  final library = Library(
    (b) {
      b
        ..comments.add('GENERATED CODE - DO NOT MODIFY BY HAND')
        ..ignoreForFile.addAll([
          'depend_on_referenced_packages',
          'prefer_double_quotes',
        ]);
      updateLib(b);
    },
  );

  final emitter = DartEmitter(
    allocator: Allocator(),
    useNullSafetySyntax: true,
  );
  final codeStr = DartFormatter().format(
    '${library.accept(emitter)}',
  );
  return codeStr;
}

Future<void> buildDriftSchemaDartFile(
  DriftSchemaInfo driftSchemaInfo,
  File driftSchemaFile,
) async {
  final outParent = driftSchemaFile.parent;
  if (!outParent.existsSync()) {
    await outParent.create(recursive: true);
  }

  final contents = generateDriftSchemaDartCode(driftSchemaInfo);

  // Update the configuration file
  await driftSchemaFile.writeAsString(contents);
}

String generateDriftSchemaDartCode(DriftSchemaInfo driftSchemaInfo) {
  final tableRef = refer('Table', kDriftImport);

  final List<Class> tableClasses = [];
  for (final tableInfo in driftSchemaInfo.tables) {
    final List<Method> methods = [];

    // Table name
    methods.add(
      Method(
        (b) => b
          ..name = 'tableName'
          ..returns = refer('String?')
          ..type = MethodType.getter
          ..body = literal(tableInfo.tableName).code
          ..annotations.add(
            const CodeExpression(Code('override')),
          ),
      ),
    );

    // Primary key
    // methods.add(
    //   Method(
    //     (b) => b
    //       ..name = 'primaryKey'
    //       ..returns = refer('Set<Column<Object>>?')
    //       ..type = MethodType.getter
    //       ..body =
    //           literalSet(tableInfo.primaryKey.map((c) => refer(c.name))).code
    //       ..annotations.add(
    //         const CodeExpression(Code('override')),
    //       ),
    //   ),
    // );

    // Fields
    for (final columnInfo in tableInfo.columns) {
      var columnBuilderExpr = _getInitialColumnBuilder(columnInfo);

      if (columnInfo.columnName != columnInfo.dartName) {
        columnBuilderExpr = columnBuilderExpr
            .property('named')
            .call([literal(columnInfo.columnName)]);
      }

      if (columnInfo.isNullable) {
        columnBuilderExpr = columnBuilderExpr.property('nullable').call([]);
      }

      final columnExpr = columnBuilderExpr.call([]);

      methods.add(
        Method(
          (b) => b
            ..name = columnInfo.dartName
            ..type = MethodType.getter
            ..returns = _getOutColumnTypeFromColumnInfo(columnInfo)
            ..body = columnExpr.code,
        ),
      );
    }

    final tableClass = Class(
      (b) => b
        ..extend = tableRef
        ..name = tableInfo.dartClassName
        ..methods.addAll(methods),
    );
    tableClasses.add(tableClass);
  }

  return _buildLibCode(
    (b) => b..body.addAll(tableClasses),
  );
}

Expression _getInitialColumnBuilder(DriftColumn columnInfo) {
  switch (columnInfo.type) {
    case DriftElectricColumnType.int2:
      return _customElectricTypeExpr('int2');
    case DriftElectricColumnType.int4:
      return _customElectricTypeExpr('int4');
    case DriftElectricColumnType.float8:
      return _customElectricTypeExpr('float8');
    case DriftElectricColumnType.string:
      return refer('text', kDriftImport).call([]);
    case DriftElectricColumnType.bool:
      return refer('boolean', kDriftImport).call([]);
    case DriftElectricColumnType.date:
      return _customElectricTypeExpr('date');
    case DriftElectricColumnType.time:
      return _customElectricTypeExpr('time');
    case DriftElectricColumnType.timeTZ:
      return _customElectricTypeExpr('timeTZ');
    case DriftElectricColumnType.timestamp:
      return _customElectricTypeExpr('timestamp');
    case DriftElectricColumnType.timestampTZ:
      return _customElectricTypeExpr('timestampTZ');
    case DriftElectricColumnType.uuid:
      return _customElectricTypeExpr('uuid');
  }
}

Expression _customElectricTypeExpr(String electricTypeName) {
  final electricTypesClass = refer('ElectricTypes', kElectricSqlDriftImport);
  return refer('customType', kDriftImport)
      .call([electricTypesClass.property(electricTypeName)]);
}

Reference _getOutColumnTypeFromColumnInfo(DriftColumn columnInfo) {
  switch (columnInfo.type) {
    case DriftElectricColumnType.int2:
    case DriftElectricColumnType.int4:
      return refer('IntColumn', kDriftImport);
    case DriftElectricColumnType.float8:
      return refer('RealColumn', kDriftImport);
    case DriftElectricColumnType.uuid:
    case DriftElectricColumnType.string:
      return refer('TextColumn', kDriftImport);
    case DriftElectricColumnType.bool:
      return refer('BoolColumn', kDriftImport);
    case DriftElectricColumnType.date:
    case DriftElectricColumnType.time:
    case DriftElectricColumnType.timeTZ:
    case DriftElectricColumnType.timestamp:
    case DriftElectricColumnType.timestampTZ:
      return refer('Column<DateTime>', kDriftImport);
  }
}


/*
class DataTypes extends Table {
  IntColumn get id => integer()();
  Column<DateTime> get date => customType(ElectricTypes.date).nullable()();
  Column<DateTime> get time => customType(ElectricTypes.time).nullable()();
  Column<DateTime> get timetz => customType(ElectricTypes.timeTZ).nullable()();
  Column<DateTime> get timestamp =>
      customType(ElectricTypes.timestamp).nullable()();
  Column<DateTime> get timestamptz =>
      customType(ElectricTypes.timestampTZ).nullable()();
  BoolColumn get boolCol => boolean().named('bool').nullable()();
  TextColumn get uuid => customType(ElectricTypes.uuid).nullable()();
  IntColumn get int2 => customType(ElectricTypes.int2).nullable()();
  IntColumn get int4 => customType(ElectricTypes.int4).nullable()();
  RealColumn get float8 => customType(ElectricTypes.float8).nullable()();

  IntColumn get relatedId =>
      integer().nullable().named('relatedId').references(Dummy, #id)();

  @override
  String? get tableName => 'DataTypes';

  @override
  Set<Column<Object>>? get primaryKey => {id};
}
*/
