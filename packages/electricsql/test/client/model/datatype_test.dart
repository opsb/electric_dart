import 'package:drift/drift.dart';
import 'package:electricsql/src/util/converters/codecs/float4.dart';
import 'package:electricsql/src/util/converters/codecs/json.dart';
import 'package:test/test.dart';

import '../drift/client_test_util.dart';
import '../drift/database.dart';

void main() async {
  final db = TestsDatabase.memory();

  await electrifyTestDatabase(db);

  setUp(() async {
    await initClientTestsDb(db);
  });

  /*
 * The tests below check that advanced data types
 * can be written into the DB, thereby, testing that
 * JS objects can be transformed to SQLite compatible values on writes
 * and then be converted back to JS objects on reads.
 */

  test('support date type', () async {
    const date = '2023-08-07';
    final d = DateTime.parse('$date 23:28:35.421');
    final res = await db.into(db.dataTypes).insertReturning(
          DataTypesCompanion.insert(
            id: const Value(1),
            date: Value(d),
          ),
        );

    expect(res.date, DateTime.parse(date));

    final fetchRes = await (db.select(db.dataTypes)
          ..where((t) => t.id.equals(1)))
        .getSingleOrNull();

    expect(fetchRes?.date, DateTime.parse(date));
  });

  test('support time type', () async {
    final date = DateTime.parse('2023-08-07 18:28:35.421');

    final res = await db.into(db.dataTypes).insertReturning(
          DataTypesCompanion.insert(
            id: const Value(1),
            time: Value(date),
          ),
        );

    expect(res.time, DateTime.parse('1970-01-01 18:28:35.421'));

    final fetchRes = await (db.select(db.dataTypes)
          ..where((t) => t.id.equals(1)))
        .getSingleOrNull();

    expect(fetchRes?.time, DateTime.parse('1970-01-01 18:28:35.421'));
  });

  test('support timetz type', () async {
    // Check that we store the time without taking into account timezones
    // such that upon reading we get the same time even if we are in a different time zone
    // test with 2 different time zones such that they cannot both coincide with the machine's timezone.
    final date1 = DateTime.parse('2023-08-07 18:28:35.421+02');
    final date2 = DateTime.parse('2023-08-07 18:28:35.421+03');

    final res1 = await db.into(db.dataTypes).insertReturning(
          DataTypesCompanion.insert(
            id: const Value(1),
            timetz: Value(date1),
          ),
        );

    final res2 = await db.into(db.dataTypes).insertReturning(
          DataTypesCompanion.insert(
            id: const Value(2),
            timetz: Value(date2),
          ),
        );

    expect(res1.timetz, DateTime.parse('1970-01-01 18:28:35.421+02'));
    expect(res2.timetz, DateTime.parse('1970-01-01 18:28:35.421+03'));

    final fetchRes1 = await (db.select(db.dataTypes)
          ..where((t) => t.id.equals(1)))
        .getSingleOrNull();

    final fetchRes2 = await (db.select(db.dataTypes)
          ..where((t) => t.id.equals(2)))
        .getSingleOrNull();

    expect(fetchRes1?.timetz, DateTime.parse('1970-01-01 18:28:35.421+02'));
    expect(fetchRes2?.timetz, DateTime.parse('1970-01-01 18:28:35.421+03'));
  });

  test('support timestamp type', () async {
    final date = DateTime.parse('2023-08-07 18:28:35.421');
    expect(date.isUtc, isFalse);

    final res = await db.into(db.dataTypes).insertReturning(
          DataTypesCompanion.insert(
            id: const Value(1),
            timestamp: Value(date),
          ),
        );

    expect(res.timestamp, DateTime.parse('2023-08-07 18:28:35.421'));

    final fetchRes = await (db.select(db.dataTypes)
          ..where((t) => t.id.equals(1)))
        .getSingleOrNull();

    expect(fetchRes?.timestamp, DateTime.parse('2023-08-07 18:28:35.421'));
  });

  test('support timestamp type - input date utc', () async {
    // 2023-08-07 18:28:35.421 UTC
    final dateUTC = DateTime.utc(2023, 8, 7, 18, 28, 35, 421);
    expect(dateUTC.isUtc, isTrue);

    final res = await db.into(db.dataTypes).insertReturning(
          DataTypesCompanion.insert(
            id: const Value(1),
            timestamp: Value(dateUTC),
          ),
        );

    final expectedLocalDate = dateUTC.toLocal();

    expect(res.timestamp, expectedLocalDate);
    expect(res.timestamp!.isUtc, isFalse);

    final fetchRes = await (db.select(db.dataTypes)
          ..where((t) => t.id.equals(1)))
        .getSingleOrNull();

    expect(fetchRes?.timestamp, expectedLocalDate);
  });

  test('support timestamptz type', () async {
    // Check that we store the timestamp without taking into account timezones
    // such that upon reading we get the same timestamp even if we are in a different time zone
    // test with 2 different time zones such that they cannot both coincide with the machine's timezone.
    final date1 = DateTime.parse('2023-08-07 18:28:35.421+02');
    final date2 = DateTime.parse('2023-08-07 18:28:35.421+03');

    final res1 = await db.into(db.dataTypes).insertReturning(
          DataTypesCompanion.insert(
            id: const Value(1),
            timestamptz: Value(date1),
          ),
        );

    final res2 = await db.into(db.dataTypes).insertReturning(
          DataTypesCompanion.insert(
            id: const Value(2),
            timestamptz: Value(date2),
          ),
        );

    expect(res1.timestamptz, date1);
    expect(res2.timestamptz, date2);

    expect(res1.timestamptz!.isUtc, isTrue);
    expect(res2.timestamptz!.isUtc, isTrue);

    final fetchRes1 = await (db.select(db.dataTypes)
          ..where((t) => t.id.equals(1)))
        .getSingleOrNull();

    final fetchRes2 = await (db.select(db.dataTypes)
          ..where((t) => t.id.equals(2)))
        .getSingleOrNull();

    expect(fetchRes1?.timestamptz, date1);
    expect(fetchRes2?.timestamptz, date2);
  });

  test('support timestamptz type - local date', () async {
    final dateLocal = DateTime.parse('2023-08-07 18:28:35.421');
    expect(dateLocal.isUtc, isFalse);
    final dateUtc = dateLocal.toUtc();

    final res = await db.into(db.dataTypes).insertReturning(
          DataTypesCompanion.insert(
            id: const Value(1),
            timestamptz: Value(dateLocal),
          ),
        );

    expect(res.timestamptz, dateUtc);

    final fetchRes = await (db.select(db.dataTypes)
          ..where((t) => t.id.equals(1)))
        .getSingleOrNull();

    expect(fetchRes?.timestamptz, dateUtc);
  });

  test('support null value for timestamptz type', () async {
    final res = await db.into(db.dataTypes).insertReturning(
          DataTypesCompanion.insert(
            id: const Value(1),
            timestamptz: const Value(null),
          ),
        );

    expect(res.id, 1);
    expect(res.timestamptz, null);

    final fetchRes = await (db.select(db.dataTypes)
          ..where((t) => t.id.equals(1)))
        .getSingle();

    expect(fetchRes.id, 1);
    expect(fetchRes.timestamptz, null);
  });

  test('support boolean type', () async {
    // Check that we can store booleans
    await db.into(db.dataTypes).insert(
          DataTypesCompanion.insert(
            id: const Value(1),
            boolCol: const Value(true),
          ),
        );

    await db.into(db.dataTypes).insert(
          DataTypesCompanion.insert(
            id: const Value(2),
            boolCol: const Value(false),
          ),
        );

    final rows = await db.select(db.dataTypes).get();

    expect(rows.any((r) => r.id == 1 && r.boolCol == true), isTrue);
    expect(rows.any((r) => r.id == 2 && r.boolCol == false), isTrue);
  });

  test('support null value for boolean type', () async {
    final res = await db.into(db.dataTypes).insertReturning(
          DataTypesCompanion.insert(
            id: const Value(1),
            boolCol: const Value(null),
          ),
        );

    expect(res.id, 1);
    expect(res.boolCol, null);

    final fetchRes = await (db.select(db.dataTypes)
          ..where((t) => t.id.equals(1)))
        .getSingle();
    expect(fetchRes.boolCol, null);
  });

  test('support uuid type', () async {
    const uuid = 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11';

    final res = await db.into(db.dataTypes).insertReturning(
          DataTypesCompanion.insert(
            id: const Value(1),
            uuid: const Value(uuid),
          ),
        );

    expect(res.id, 1);
    expect(res.uuid, uuid);

    final fetchRes = await (db.select(db.dataTypes)
          ..where((t) => t.id.equals(1)))
        .getSingle();
    expect(fetchRes.uuid, uuid);

    // Check that it rejects invalid uuids
    await expectLater(
      () async => db.into(db.dataTypes).insertReturning(
            DataTypesCompanion.insert(
              id: const Value(1),
              uuid: const Value('a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a111'),
            ),
          ),
      throwsA(
        isA<FormatException>().having(
          (p0) => p0.message,
          'message',
          'The provided UUID is invalid.',
        ),
      ),
    );
  });

  test('support null value for uuid type', () async {
    final res = await db.into(db.dataTypes).insertReturning(
          DataTypesCompanion.insert(
            id: const Value(1),
            uuid: const Value(null),
          ),
        );

    expect(res.id, 1);
    expect(res.uuid, null);

    final fetchRes = await (db.select(db.dataTypes)
          ..where((t) => t.id.equals(1)))
        .getSingle();
    expect(fetchRes.uuid, null);
  });

  test('support int2 type', () async {
    const validInt1 = 32767;
    const invalidInt1 = 32768;

    const validInt2 = -32768;
    const invalidInt2 = -32769;

    await db.into(db.dataTypes).insert(
          DataTypesCompanion.insert(
            id: const Value(1),
            int2: const Value(validInt1),
          ),
        );

    await db.into(db.dataTypes).insert(
          DataTypesCompanion.insert(
            id: const Value(2),
            int2: const Value(validInt2),
          ),
        );

    // Check that it rejects invalid integers
    const invalidInts = [invalidInt1, invalidInt2];
    int id = 3;
    for (final invalidInt in invalidInts) {
      await expectLater(
        () async => db.into(db.dataTypes).insertReturning(
              DataTypesCompanion.insert(
                id: Value(id++),
                int2: Value(invalidInt),
              ),
            ),
        throwsA(
          isA<RangeError>().having(
            (p0) => p0.toString(),
            'error',
            contains(
              'Invalid value: Not in inclusive range -32768..32767: $invalidInt',
            ),
          ),
        ),
      );
    }
  });

  test('support null values for int2 type', () async {
    final res = await db.into(db.dataTypes).insertReturning(
          DataTypesCompanion.insert(
            id: const Value(1),
            int2: const Value(null),
          ),
        );

    expect(res.id, 1);
    expect(res.int2, null);

    final fetchRes = await (db.select(db.dataTypes)
          ..where((t) => t.id.equals(1)))
        .getSingle();
    expect(fetchRes.int2, null);
  });

  test('support int4 type', () async {
    const validInt1 = 2147483647;
    const invalidInt1 = 2147483648;

    const validInt2 = -2147483648;
    const invalidInt2 = -2147483649;

    await db.into(db.dataTypes).insert(
          DataTypesCompanion.insert(
            id: const Value(1),
            int4: const Value(validInt1),
          ),
        );

    await db.into(db.dataTypes).insert(
          DataTypesCompanion.insert(
            id: const Value(2),
            int4: const Value(validInt2),
          ),
        );

    // Check that it rejects invalid integers
    const invalidInts = [invalidInt1, invalidInt2];
    int id = 3;
    for (final invalidInt in invalidInts) {
      await expectLater(
        () async => db.into(db.dataTypes).insertReturning(
              DataTypesCompanion.insert(
                id: Value(id++),
                int4: Value(invalidInt),
              ),
            ),
        throwsA(
          isA<RangeError>().having(
            (p0) => p0.toString(),
            'error',
            contains(
              'Invalid value: Not in inclusive range -2147483648..2147483647: $invalidInt',
            ),
          ),
        ),
      );
    }
  });

  test('support null values for int4 type', () async {
    final res = await db.into(db.dataTypes).insertReturning(
          DataTypesCompanion.insert(
            id: const Value(1),
            int4: const Value(null),
          ),
        );

    expect(res.id, 1);
    expect(res.int4, null);

    final fetchRes = await (db.select(db.dataTypes)
          ..where((t) => t.id.equals(1)))
        .getSingle();
    expect(fetchRes.int4, null);
  });

  test('support float8 type', () async {
    const validFloat1 = 1.7976931348623157e308;
    const validFloat2 = -1.7976931348623157e308;

    const nanId = 5;

    const List<({int id, double float8})> floats = [
      (
        id: 1,
        float8: validFloat1,
      ),
      (
        id: 2,
        float8: validFloat2,
      ),
      (
        id: 3,
        float8: double.infinity,
      ),
      (
        id: 4,
        float8: double.negativeInfinity,
      ),
      (
        id: nanId,
        float8: double.nan,
      ),
    ];

    for (final floatEntry in floats) {
      await db.into(db.dataTypes).insert(
            DataTypesCompanion.insert(
              id: Value(floatEntry.id),
              float8: Value(floatEntry.float8),
            ),
          );
    }

    // Check that we can read the floats back
    final fetchRes = await db.select(db.dataTypes).get();
    final records = fetchRes.map((r) => (id: r.id, float8: r.float8)).toList();

    // NaN != NaN, so we need to filter it out and check it separately
    final recordsNoNaN = records.where((r) => r.id != nanId).toList();
    final floatsNoNaN = floats.where((r) => r.id != nanId).toList();
    expect(recordsNoNaN, floatsNoNaN);

    // Expect NaN entry
    final nanEntry = records.firstWhere((r) => r.id == nanId);
    expect(nanEntry.float8!.isNaN, isTrue);
  });

  test('support null values for float8 type', () async {
    final res = await db.into(db.dataTypes).insertReturning(
          DataTypesCompanion.insert(
            id: const Value(1),
            float8: const Value(null),
          ),
        );

    expect(res.id, 1);
    expect(res.float8, null);

    final fetchRes = await (db.select(db.dataTypes)
          ..where((t) => t.id.equals(1)))
        .getSingle();
    expect(fetchRes.float8, null);
  });

  test('support int8 type', () async {
    const validInt1 = 9223372036854775807;
    const validInt2 = -9223372036854775808;

    final List<({int id, int int8})> ints = [
      (
        id: 1,
        int8: validInt1,
      ),
      (
        id: 2,
        int8: validInt2,
      ),
    ];

    for (final entry in ints) {
      await db.into(db.dataTypes).insert(
            DataTypesCompanion.insert(
              id: Value(entry.id),
              int8: Value(entry.int8),
            ),
          );
    }

    // Check that we can read the big ints back
    final fetchRes = await db.select(db.dataTypes).get();
    final records = fetchRes.map((r) => (id: r.id, int8: r.int8)).toList();

    expect(records, ints);
  });

  test('support null values for int8 type', () async {
    final res = await db.into(db.dataTypes).insertReturning(
          DataTypesCompanion.insert(
            id: const Value(1),
            int8: const Value(null),
          ),
        );

    expect(res.id, 1);
    expect(res.int8, null);

    final fetchRes = await (db.select(db.dataTypes)
          ..where((t) => t.id.equals(1)))
        .getSingle();
    expect(fetchRes.int8, null);
  });

  test('support BigInt type', () async {
    final validBigInt1 = BigInt.parse('9223372036854775807');
    final validBigInt2 = BigInt.parse('-9223372036854775808');

    final List<({int id, BigInt int8})> bigInts = [
      (
        id: 1,
        int8: validBigInt1,
      ),
      (
        id: 2,
        int8: validBigInt2,
      ),
    ];

    for (final entry in bigInts) {
      await db.into(db.dataTypes).insert(
            DataTypesCompanion.insert(
              id: Value(entry.id),
              int8BigInt: Value(entry.int8),
            ),
          );
    }

    // Check that we can read the big ints back
    final fetchRes = await db.select(db.dataTypes).get();
    final records =
        fetchRes.map((r) => (id: r.id, int8: r.int8BigInt)).toList();

    expect(records, bigInts);
  });

  test('support null values for bigint type', () async {
    final res = await db.into(db.dataTypes).insertReturning(
          DataTypesCompanion.insert(
            id: const Value(1),
            int8BigInt: const Value(null),
          ),
        );

    expect(res.id, 1);
    expect(res.int8BigInt, null);

    final fetchRes = await (db.select(db.dataTypes)
          ..where((t) => t.id.equals(1)))
        .getSingle();
    expect(fetchRes.int8BigInt, null);
  });

  test('throw error when value is out of range for BigInt type', () async {
    final invalidBigInt1 = BigInt.parse('9223372036854775808');
    final invalidBigInt2 = BigInt.parse('-9223372036854775809');

    // Check that it rejects invalid int8
    final invalidBigInts = [invalidBigInt1, invalidBigInt2];
    int id = 1;
    for (final invalidInt in invalidBigInts) {
      await expectLater(
        () async => db.into(db.dataTypes).insertReturning(
              DataTypesCompanion.insert(
                id: Value(id++),
                int8BigInt: Value(invalidInt),
              ),
            ),
        throwsA(
          isA<Exception>().having(
            (p0) => p0.toString(),
            'error',
            contains(
              'BigInt value exceeds the range of 64 bits',
            ),
          ),
        ),
      );
    }
  });

  test('support float4 type', () async {
    const validFloat1 = 1.402823e36;
    const validFloat2 = -1.402823e36;

    const nanId = 5;

    const List<({int id, double float4})> floats = [
      (
        id: 1,
        float4: validFloat1,
      ),
      (
        id: 2,
        float4: validFloat2,
      ),
      (
        id: 3,
        float4: double.infinity,
      ),
      (
        id: 4,
        float4: double.negativeInfinity,
      ),
      (
        id: nanId,
        float4: double.nan,
      ),
    ];

    for (final floatEntry in floats) {
      await db.into(db.dataTypes).insert(
            DataTypesCompanion.insert(
              id: Value(floatEntry.id),
              float4: Value(floatEntry.float4),
            ),
          );
    }

    // Check that we can read the floats back
    final fetchRes = await db.select(db.dataTypes).get();
    final records = fetchRes.map((r) => (id: r.id, float4: r.float4)).toList();

    // NaN != NaN, so we need to filter it out and check it separately
    final recordsNoNaN = records.where((r) => r.id != nanId).toList();
    final floatsNoNaN = floats
        .where((r) => r.id != nanId)
        .map((e) => (id: e.id, float4: fround(e.float4)))
        .toList();
    expect(recordsNoNaN, floatsNoNaN);

    // Expect NaN entry
    final nanEntry = records.firstWhere((r) => r.id == nanId);
    expect(nanEntry.float4!.isNaN, isTrue);
  });

  test('converts numbers outside float4 range', () async {
    const tooPositive = 1.42724769270596e+45;
    const tooNegative = -1.42724769270596e+45;
    const tooSmallPositive = 7.006492321624085e-46;
    const tooSmallNegative = -7.006492321624085e-46;

    const floats = <({int id, double float4})>[
      (
        id: 1,
        float4: tooPositive,
      ),
      (
        id: 2,
        float4: tooNegative,
      ),
      (
        id: 3,
        float4: tooSmallPositive,
      ),
      (
        id: 4,
        float4: tooSmallNegative,
      ),
    ];

    for (final floatEntry in floats) {
      await db.into(db.dataTypes).insert(
            DataTypesCompanion.insert(
              id: Value(floatEntry.id),
              float4: Value(floatEntry.float4),
            ),
          );
    }

    // Check that we can read the floats back
    final fetchRes = await db.select(db.dataTypes).get();
    final records = fetchRes.map((r) => (id: r.id, float4: r.float4)).toList();

    expect(
      records,
      <({int id, double float4})>[
        (
          id: 1,
          float4: double.infinity,
        ),
        (
          id: 2,
          float4: double.negativeInfinity,
        ),
        (
          id: 3,
          float4: 0,
        ),
        (
          id: 4,
          float4: 0,
        ),
      ],
    );
  });

  test('support JSON type', () async {
    final json = {
      'a': 1,
      'b': true,
      'c': {'d': 'nested'},
      'e': [1, 2, 3],
      'f': null,
    };

    final res = await db.into(db.dataTypes).insertReturning(
          DataTypesCompanion.insert(
            id: const Value(1),
            json: Value(json),
          ),
        );

    expect(res.json, json);

    final fetchRes = await (db.select(db.dataTypes)
          ..where((t) => t.id.equals(1)))
        .getSingle();
    expect(fetchRes.json, json);

    // Also test that we can write the special JsonNull value
    final res2 = await db.into(db.dataTypes).insertReturning(
          DataTypesCompanion.insert(
            id: const Value(2),
            json: const Value(kJsonNull),
          ),
        );

    expect(res2.json, kJsonNull);

    final fetchRes2 = await (db.select(db.dataTypes)
          ..where((t) => t.id.equals(2)))
        .getSingle();
    expect(fetchRes2.json, kJsonNull);
  });

  test('support null values for JSON type', () async {
    final res = await db.into(db.dataTypes).insertReturning(
          DataTypesCompanion.insert(
            id: const Value(1),
            json: const Value(null),
          ),
        );

    expect(res.json, null);

    final fetchRes = await (db.select(db.dataTypes)
          ..where((t) => t.id.equals(1)))
        .getSingle();
    expect(fetchRes.json, null);
  });
}
