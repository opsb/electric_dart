// ignore_for_file: unreachable_from_main

import 'dart:convert';

import 'package:electricsql/src/auth/auth.dart';
import 'package:electricsql/src/electric/adapter.dart';
import 'package:electricsql/src/migrators/migrators.dart';
import 'package:electricsql/src/notifiers/mock.dart';
import 'package:electricsql/src/satellite/mock.dart';
import 'package:electricsql/src/satellite/oplog.dart';
import 'package:electricsql/src/satellite/process.dart';
import 'package:electricsql/src/util/converters/helpers.dart';
import 'package:electricsql/src/util/types.dart';
import 'package:fixnum/fixnum.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../support/satellite_helpers.dart';
import 'common.dart';

late SatelliteTestContext context;

Database get db => context.db;
DatabaseAdapter get adapter => context.adapter;
Migrator get migrator => context.migrator;
MockNotifier get notifier => context.notifier;
TableInfo get tableInfo => context.tableInfo;
SatelliteProcess get satellite => context.satellite;
MockSatelliteClient get client => context.client;
String get dbName => context.dbName;
AuthState get authState => context.authState;

void main() {
  setUp(() async {
    context = await makeContext();
  });

  tearDown(() async {
    await context.cleanAndStopSatellite();
  });

  test('basic rules for setting tags', () async {
    await context.runMigrations();

    satellite.setAuthState(context.authState);
    final clientId = satellite.authState?.clientId ?? 'test_client';

    await adapter.run(
      Statement(
        "INSERT INTO parent(id, value, other) VALUES (1, 'local', null)",
      ),
    );

    final txDate1 = await satellite.performSnapshot();
    var shadow = await getMatchingShadowEntries(adapter);
    expect(shadow.length, 1);
    expect(shadow[0].tags, genEncodedTags(clientId, [txDate1]));

    await adapter.run(
      Statement(
        "UPDATE parent SET value = 'local1', other = 'other1' WHERE id = 1",
      ),
    );

    final txDate2 = await satellite.performSnapshot();
    shadow = await getMatchingShadowEntries(adapter);
    expect(shadow.length, 1);
    expect(shadow[0].tags, genEncodedTags(clientId, [txDate2]));

    await adapter.run(
      Statement(
        "UPDATE parent SET value = 'local2', other = 'other2' WHERE id = 1",
      ),
    );

    final txDate3 = await satellite.performSnapshot();
    shadow = await getMatchingShadowEntries(adapter);
    expect(shadow.length, 1);
    expect(shadow[0].tags, genEncodedTags(clientId, [txDate3]));

    await adapter.run(
      Statement(
        'DELETE FROM parent WHERE id = 1',
      ),
    );

    final txDate4 = await satellite.performSnapshot();
    shadow = await getMatchingShadowEntries(adapter);
    expect(shadow.length, 0);

    final entries = await satellite.getEntries();
    expect(entries[0].clearTags, encodeTags([]));
    expect(entries[1].clearTags, genEncodedTags(clientId, [txDate2, txDate1]));
    expect(entries[2].clearTags, genEncodedTags(clientId, [txDate3, txDate2]));
    expect(entries[3].clearTags, genEncodedTags(clientId, [txDate4, txDate3]));

    expect(txDate1, isNot(txDate2));
    expect(txDate2, isNot(txDate3));
    expect(txDate3, isNot(txDate4));
  });

  test(
      'Tags are correctly set on multiple operations within snapshot/transaction',
      () async {
    await context.runMigrations();
    const clientId = 'test_client';
    satellite.setAuthState(authState.copyWith(clientId: clientId));

    // Insert 4 items in separate snapshots
    await adapter.run(
      Statement("INSERT INTO parent (id, value) VALUES (1, 'val1')"),
    );
    final ts1 = await satellite.performSnapshot();
    await adapter.run(
      Statement("INSERT INTO parent (id, value) VALUES (2, 'val2')"),
    );
    final ts2 = await satellite.performSnapshot();
    await adapter.run(
      Statement("INSERT INTO parent (id, value) VALUES (3, 'val3')"),
    );
    final ts3 = await satellite.performSnapshot();
    await adapter.run(
      Statement("INSERT INTO parent (id, value) VALUES (4, 'val4')"),
    );
    final ts4 = await satellite.performSnapshot();

    // Now delete them all in a single snapshot
    await adapter.run(Statement('DELETE FROM parent'));
    final ts5 = await satellite.performSnapshot();

    // Now check that each delete clears the correct tag
    final entries = await satellite.getEntries(since: 4);
    expect(entries.map((x) => x.clearTags).toList(), [
      genEncodedTags(clientId, [ts5, ts1]),
      genEncodedTags(clientId, [ts5, ts2]),
      genEncodedTags(clientId, [ts5, ts3]),
      genEncodedTags(clientId, [ts5, ts4]),
    ]);
  });

  test('Tags are correctly set on subsequent operations in a TX', () async {
    await context.runMigrations();

    await adapter.run(
      Statement(
        "INSERT INTO parent(id, value) VALUES (1,'val1')",
      ),
    );

    // Since no snapshot was made yet
    // the timestamp in the oplog is not yet set
    final insertEntry = await adapter.query(
      Statement(
        'SELECT timestamp, clearTags FROM _electric_oplog WHERE rowid = 1',
      ),
    );
    expect(insertEntry[0]['timestamp'], null);
    expect(json.decode(insertEntry[0]['clearTags']! as String), <Object?>[]);

    satellite.setAuthState(authState);
    await satellite.performSnapshot();

    DateTime parseDate(String date) => DateTime.parse(date);

    // Now the timestamp is set
    final insertEntryAfterSnapshot = await adapter.query(
      Statement(
        'SELECT timestamp, clearTags FROM _electric_oplog WHERE rowid = 1',
      ),
    );
    expect(insertEntryAfterSnapshot[0]['timestamp'] != null, isTrue);
    final insertTimestamp =
        parseDate(insertEntryAfterSnapshot[0]['timestamp']! as String);
    expect(
      json.decode(insertEntryAfterSnapshot[0]['clearTags']! as String),
      <Object?>[],
    );

    // Now update the entry, then delete it, and then insert it again
    await adapter.run(
      Statement(
        "UPDATE parent SET value = 'val2' WHERE id=1",
      ),
    );

    await adapter.run(
      Statement(
        'DELETE FROM parent WHERE id=1',
      ),
    );

    await adapter.run(
      Statement(
        "INSERT INTO parent(id, value) VALUES (1,'val3')",
      ),
    );

    // Since no snapshot has been taken for these operations
    // their timestamp and clearTags should not be set
    final updateEntry = await adapter.query(
      Statement(
        'SELECT timestamp, clearTags FROM _electric_oplog WHERE rowid = 2',
      ),
    );

    expect(updateEntry[0]['timestamp'], null);
    expect(json.decode(updateEntry[0]['clearTags']! as String), <Object?>[]);

    final deleteEntry = await adapter.query(
      Statement(
        'SELECT timestamp, clearTags FROM _electric_oplog WHERE rowid = 3',
      ),
    );

    expect(deleteEntry[0]['timestamp'], null);
    expect(json.decode(deleteEntry[0]['clearTags']! as String), <Object?>[]);

    final reinsertEntry = await adapter.query(
      Statement(
        'SELECT timestamp, clearTags FROM _electric_oplog WHERE rowid = 4',
      ),
    );

    expect(reinsertEntry[0]['timestamp'], null);
    expect(json.decode(reinsertEntry[0]['clearTags']! as String), <Object?>[]);

    // Now take a snapshot for these operations
    await satellite.performSnapshot();

    // Now the timestamps should be set
    // The first operation (update) should override
    // the original insert (i.e. clearTags must contain the timestamp of the insert)
    final updateEntryAfterSnapshot = await adapter.query(
      Statement(
        'SELECT timestamp, clearTags FROM _electric_oplog WHERE rowid = 2',
      ),
    );

    final rawTimestampTx2 = updateEntryAfterSnapshot[0]['timestamp']! as String;
    expect(rawTimestampTx2, isNotNull);
    final timestampTx2 = parseDate(rawTimestampTx2);

    expect(
      updateEntryAfterSnapshot[0]['clearTags'],
      genEncodedTags(authState.clientId, [timestampTx2, insertTimestamp]),
    );

    // The second operation (delete) should have the same timestamp
    // and should contain the tag of the TX in its clearTags
    final deleteEntryAfterSnapshot = await adapter.query(
      Statement(
        'SELECT timestamp, clearTags FROM _electric_oplog WHERE rowid = 3',
      ),
    );

    expect(deleteEntryAfterSnapshot[0]['timestamp'], rawTimestampTx2);
    expect(
      deleteEntryAfterSnapshot[0]['clearTags'],
      genEncodedTags(authState.clientId, [timestampTx2, insertTimestamp]),
    );

    // The third operation (reinsert) should have the same timestamp
    // and should contain the tag of the TX in its clearTags
    final reinsertEntryAfterSnapshot = await adapter.query(
      Statement(
        'SELECT timestamp, clearTags FROM _electric_oplog WHERE rowid = 4',
      ),
    );

    expect(reinsertEntryAfterSnapshot[0]['timestamp'], rawTimestampTx2);
    expect(
      reinsertEntryAfterSnapshot[0]['clearTags'],
      genEncodedTags(authState.clientId, [timestampTx2, insertTimestamp]),
    );
  });

  test('TX1=INSERT, TX2=DELETE, TX3=INSERT, ack TX1', () async {
    await context.runMigrations();
    satellite.setAuthState(context.authState);

    final clientId = satellite.authState?.clientId ?? 'test_id';

    // Local INSERT
    final stmts1 = Statement(
      'INSERT INTO parent (id, value, other) VALUES (?, ?, ?)',
      <Object?>['1', 'local', null],
    );
    await adapter.runInTransaction([stmts1]);
    final txDate1 = await satellite.performSnapshot();

    final localEntries1 = await satellite.getEntries();
    final shadowEntry1 =
        await getMatchingShadowEntries(adapter, oplog: localEntries1[0]);

    // shadow tag is time of snapshot
    final tag1 = genEncodedTags(clientId, [txDate1]);
    expect(tag1, shadowEntry1[0].tags);
    // clearTag is empty
    final localEntries10 = localEntries1[0];
    expect(localEntries10.clearTags, json.encode([]));
    expect(localEntries10.timestamp, txDate1.toISOStringUTC());

    // Local DELETE
    final stmts2 = Statement(
      'DELETE FROM parent WHERE id=?',
      ['1'],
    );
    await adapter.runInTransaction([stmts2]);
    final txDate2 = await satellite.performSnapshot();

    final localEntries2 = await satellite.getEntries();
    final shadowEntry2 =
        await getMatchingShadowEntries(adapter, oplog: localEntries2[1]);

    // shadowTag is empty
    expect(0, shadowEntry2.length);
    // clearTags contains previous shadowTag
    final localEntry21 = localEntries2[1];

    expect(
      localEntry21.clearTags,
      genEncodedTags(clientId, [txDate2, txDate1]),
    );
    expect(localEntry21.timestamp, txDate2.toISOStringUTC());

    // Local INSERT
    final stmts3 = Statement(
      'INSERT INTO parent (id, value, other) VALUES (?, ?, ?)',
      <Object?>['1', 'local', null],
    );
    await adapter.runInTransaction([stmts3]);
    final txDate3 = await satellite.performSnapshot();

    final localEntries3 = await satellite.getEntries();
    final shadowEntry3 =
        await getMatchingShadowEntries(adapter, oplog: localEntries3[1]);

    final tag3 = genEncodedTags(clientId, [txDate3]);
    // shadow tag is tag3
    expect(tag3, shadowEntry3[0].tags);

    // clearTags is empty after a DELETE
    final localEntry32 = localEntries3[2];

    expect(localEntry32.clearTags, json.encode([]));
    expect(localEntry32.timestamp, txDate3.toISOStringUTC());

    // apply incomig operation (local operation ack)
    final ackEntry = generateRemoteOplogEntry(
      tableInfo,
      'main',
      'parent',
      OpType.insert,
      txDate1.millisecondsSinceEpoch,
      tag1,
      newValues: {
        'id': 1,
        'value': 'local',
        'other': null,
      },
      oldValues: {},
    );

    final ackDataChange = opLogEntryToChange(ackEntry, kTestRelations);

    // satellite must be aware of the relations in order to turn the `ackDataChange` DataChange into an OpLogEntry
    satellite.relations = kTestRelations;
    final tx = Transaction(
      origin: clientId,
      commitTimestamp: Int64(txDate1.millisecondsSinceEpoch),
      changes: [ackDataChange],
      lsn: [],
    );
    await satellite.applyTransaction(tx);

    // validate that garbage collection has been triggered
    expect(2, (await satellite.getEntries()).length);

    final shadow = await getMatchingShadowEntries(adapter);
    expect(
      shadow[0].tags,
      genEncodedTags(clientId, [txDate3]),
      reason: 'error: tag1 was reintroduced after merging acked operation',
    );
  });

  test('remote tx (INSERT) concurrently with local tx (INSERT -> DELETE)',
      () async {
    await context.runMigrations();
    satellite.setAuthState(context.authState);

    final List<Statement> stmts = [];

    // For this key we will choose remote Tx, such that: Local TM > Remote TX
    stmts.add(
      Statement(
        'INSERT INTO parent (id, value, other) VALUES (?, ?, ?);',
        ['1', 'local', null],
      ),
    );
    stmts.add(Statement('DELETE FROM parent WHERE id = 1'));
    // For this key we will choose remote Tx, such that: Local TM < Remote TX
    stmts.add(
      Statement(
        'INSERT INTO parent (id, value, other) VALUES (?, ?, ?);',
        ['2', 'local', null],
      ),
    );
    stmts.add(Statement('DELETE FROM parent WHERE id = 2'));
    await adapter.runInTransaction(stmts);

    final txDate1 = await satellite.performSnapshot();

    final prevTs = txDate1.millisecondsSinceEpoch - 1;
    final nextTs = txDate1.millisecondsSinceEpoch + 1;

    final prevEntry = generateRemoteOplogEntry(
      tableInfo,
      'main',
      'parent',
      OpType.insert,
      prevTs,
      genEncodedTags('remote', [DateTime.fromMillisecondsSinceEpoch(prevTs)]),
      newValues: {
        'id': 1,
        'value': 'remote',
        'other': 1,
      },
      oldValues: {},
    );
    final nextEntry = generateRemoteOplogEntry(
      tableInfo,
      'main',
      'parent',
      OpType.insert,
      nextTs,
      genEncodedTags('remote', [DateTime.fromMillisecondsSinceEpoch(nextTs)]),
      newValues: {
        'id': 2,
        'value': 'remote',
        'other': 2,
      },
      oldValues: {},
    );

// satellite must be aware of the relations in order to turn `DataChange`s into `OpLogEntry`s
    satellite.relations = kTestRelations;

    final prevChange = opLogEntryToChange(prevEntry, kTestRelations);
    final prevTx = Transaction(
      origin: 'remote',
      commitTimestamp: Int64(prevTs),
      changes: [prevChange],
      lsn: [],
    );
    await satellite.applyTransaction(prevTx);

    final nextChange = opLogEntryToChange(nextEntry, kTestRelations);
    final nextTx = Transaction(
      origin: 'remote',
      commitTimestamp: Int64(nextTs),
      changes: [nextChange],
      lsn: [],
    );
    await satellite.applyTransaction(nextTx);

    final shadow = await getMatchingShadowEntries(adapter);
    final expectedShadow = [
      ShadowEntry(
        namespace: 'main',
        tablename: 'parent',
        primaryKey: '{"id":1}',
        tags: genEncodedTags(
          'remote',
          [DateTime.fromMillisecondsSinceEpoch(prevTs)],
        ),
      ),
      ShadowEntry(
        namespace: 'main',
        tablename: 'parent',
        primaryKey: '{"id":2}',
        tags: genEncodedTags(
          'remote',
          [DateTime.fromMillisecondsSinceEpoch(nextTs)],
        ),
      ),
    ];
    expect(shadow, expectedShadow);

    //let entries= await satellite._getEntries()
    //console.log(entries)
    final userTable = await adapter.query(Statement('SELECT * FROM parent;'));
    //console.log(table)

    // In both cases insert wins over delete, but
    // for id = 1 CR picks local data before delete, while
    // for id = 2 CR picks remote data
    final List<Map<String, Object?>> expectedUserTable = [
      {'id': 1, 'value': 'local', 'other': null},
      {'id': 2, 'value': 'remote', 'other': 2},
    ];

    expect(userTable, expectedUserTable);
  });

  test('remote tx (INSERT) concurrently with 2 local txses (INSERT -> DELETE)',
      () async {
    await context.runMigrations();
    satellite.setAuthState(context.authState);

    List<Statement> stmts = [];

    // For this key we will choose remote Tx, such that: Local TM > Remote TX
    stmts.add(
      Statement(
        'INSERT INTO parent (id, value, other) VALUES (?, ?, ?);',
        ['1', 'local', null],
      ),
    );
    stmts.add(
      Statement(
        'INSERT INTO parent (id, value, other) VALUES (?, ?, ?);',
        ['2', 'local', null],
      ),
    );
    await adapter.runInTransaction(stmts);
    final txDate1 = await satellite.performSnapshot();

    stmts = [];
    // For this key we will choose remote Tx, such that: Local TM < Remote TX
    stmts.add(Statement('DELETE FROM parent WHERE id = 1'));
    stmts.add(Statement('DELETE FROM parent WHERE id = 2'));
    await adapter.runInTransaction(stmts);
    await satellite.performSnapshot();

    final prevTs =
        DateTime.fromMillisecondsSinceEpoch(txDate1.millisecondsSinceEpoch - 1);
    final nextTs =
        DateTime.fromMillisecondsSinceEpoch(txDate1.millisecondsSinceEpoch + 1);

    final prevEntry = generateRemoteOplogEntry(
      tableInfo,
      'main',
      'parent',
      OpType.insert,
      prevTs.millisecondsSinceEpoch,
      genEncodedTags('remote', [prevTs]),
      newValues: {
        'id': 1,
        'value': 'remote',
        'other': 1,
      },
      oldValues: {},
    );
    final nextEntry = generateRemoteOplogEntry(
      tableInfo,
      'main',
      'parent',
      OpType.insert,
      nextTs.millisecondsSinceEpoch,
      genEncodedTags('remote', [nextTs]),
      newValues: {
        'id': 2,
        'value': 'remote',
        'other': 2,
      },
      oldValues: {},
    );

// satellite must be aware of the relations in order to turn `DataChange`s into `OpLogEntry`s in `_applyTransaction`
    satellite.relations = kTestRelations;

    final prevChange = opLogEntryToChange(prevEntry, kTestRelations);
    final prevTx = Transaction(
      origin: 'remote',
      commitTimestamp: Int64(prevTs.millisecondsSinceEpoch),
      changes: [prevChange],
      lsn: [],
    );
    await satellite.applyTransaction(prevTx);

    final nextChange = opLogEntryToChange(nextEntry, kTestRelations);
    final nextTx = Transaction(
      origin: 'remote',
      commitTimestamp: Int64(nextTs.millisecondsSinceEpoch),
      changes: [nextChange],
      lsn: [],
    );
    await satellite.applyTransaction(nextTx);

    final shadow = await getMatchingShadowEntries(adapter);
    final expectedShadow = [
      ShadowEntry(
        namespace: 'main',
        tablename: 'parent',
        primaryKey: '{"id":1}',
        tags: genEncodedTags('remote', [prevTs]),
      ),
      ShadowEntry(
        namespace: 'main',
        tablename: 'parent',
        primaryKey: '{"id":2}',
        tags: genEncodedTags('remote', [nextTs]),
      ),
    ];
    expect(shadow, expectedShadow);

    //let entries= await satellite._getEntries()
    //console.log(entries)
    final userTable = await adapter.query(Statement('SELECT * FROM parent;'));
    //console.log(table)

    // In both cases insert wins over delete, but
    // for id = 1 CR picks local data before delete, while
    // for id = 2 CR picks remote data
    final expectedUserTable = [
      {'id': 1, 'value': 'local', 'other': null},
      {'id': 2, 'value': 'remote', 'other': 2},
    ];
    expect(expectedUserTable, userTable);
  });

  test('remote tx (INSERT) concurrently with local tx (INSERT -> UPDATE)',
      () async {
    await context.runMigrations();
    satellite.setAuthState(context.authState);
    final clientId = satellite.authState?.clientId ?? 'test_id';
    final stmts = <Statement>[];

    // For this key we will choose remote Tx, such that: Local TM > Remote TX
    stmts.add(
      Statement(
        'INSERT INTO parent (id, value, other) VALUES (?, ?, ?);',
        ['1', 'local', null],
      ),
    );
    stmts.add(
      Statement(
        'UPDATE parent SET value = ?, other = ? WHERE id = 1',
        ['local', 'not_null'],
      ),
    );
    // For this key we will choose remote Tx, such that: Local TM < Remote TX
    stmts.add(
      Statement(
        'INSERT INTO parent (id, value, other) VALUES (?, ?, ?);',
        ['2', 'local', null],
      ),
    );
    stmts.add(
      Statement(
        'UPDATE parent SET value = ?, other = ? WHERE id = 1',
        ['local', 'not_null'],
      ),
    );
    await adapter.runInTransaction(stmts);

    final txDate1 = await satellite.performSnapshot();

    final prevTs =
        DateTime.fromMillisecondsSinceEpoch(txDate1.millisecondsSinceEpoch - 1);
    final nextTs =
        DateTime.fromMillisecondsSinceEpoch(txDate1.millisecondsSinceEpoch + 1);

    final prevEntry = generateRemoteOplogEntry(
      tableInfo,
      'main',
      'parent',
      OpType.insert,
      prevTs.millisecondsSinceEpoch,
      genEncodedTags('remote', [prevTs]),
      newValues: {
        'id': 1,
        'value': 'remote',
        'other': 1,
      },
      oldValues: {},
    );

    final nextEntry = generateRemoteOplogEntry(
      tableInfo,
      'main',
      'parent',
      OpType.insert,
      nextTs.millisecondsSinceEpoch,
      genEncodedTags('remote', [nextTs]),
      newValues: {
        'id': 2,
        'value': 'remote',
        'other': 2,
      },
      oldValues: {},
    );

    // satellite must be aware of the relations in order to turn `DataChange`s into `OpLogEntry`s in `_applyTransaction`
    satellite.relations = kTestRelations;

    final prevChange = opLogEntryToChange(prevEntry, kTestRelations);
    final prevTx = Transaction(
      origin: 'remote',
      commitTimestamp: Int64(prevTs.millisecondsSinceEpoch),
      changes: [prevChange],
      lsn: [],
    );
    await satellite.applyTransaction(prevTx);

    final nextChange = opLogEntryToChange(nextEntry, kTestRelations);
    final nextTx = Transaction(
      origin: 'remote',
      commitTimestamp: Int64(nextTs.millisecondsSinceEpoch),
      changes: [nextChange],
      lsn: [],
    );
    await satellite.applyTransaction(nextTx);

    final shadow = await getMatchingShadowEntries(adapter);
    final expectedShadow = [
      ShadowEntry(
        namespace: 'main',
        tablename: 'parent',
        primaryKey: '{"id":1}',
        tags: encodeTags([
          generateTag(clientId, txDate1),
          generateTag('remote', prevTs),
        ]),
      ),
      ShadowEntry(
        namespace: 'main',
        tablename: 'parent',
        primaryKey: '{"id":2}',
        tags: encodeTags([
          generateTag(clientId, txDate1),
          generateTag('remote', nextTs),
        ]),
      ),
    ];
    expect(shadow, expectedShadow);

    final entries = await satellite.getEntries();
    //console.log(entries)

    // Given that Insert and Update happen within the same transaction clear should not
    // contain itself
    expect(entries[0].clearTags, encodeTags([]));
    expect(entries[1].clearTags, encodeTags([]));
    expect(entries[2].clearTags, encodeTags([]));
    expect(entries[3].clearTags, encodeTags([]));

    final userTable = await adapter.query(Statement('SELECT * FROM parent;'));

    // In both cases insert wins over delete, but
    // for id = 1 CR picks local data before delete, while
    // for id = 2 CR picks remote data
    final expectedUserTable = [
      {'id': 1, 'value': 'local', 'other': 'not_null'},
      {'id': 2, 'value': 'remote', 'other': 2},
    ];
    expect(expectedUserTable, userTable);
  });

  test('origin tx (INSERT) concurrently with local txses (INSERT -> DELETE)',
      () async {
    //
    await context.runMigrations();
    satellite.setAuthState(context.authState);
    final clientId = satellite.authState?.clientId ?? 'test_id';

    var stmts = <Statement>[];

    // For this key we will choose remote Tx, such that: Local TM > Remote TX
    stmts.add(
      Statement(
        'INSERT INTO parent (id, value, other) VALUES (?, ?, ?);',
        ['1', 'local', null],
      ),
    );
    stmts.add(
      Statement(
        'INSERT INTO parent (id, value, other) VALUES (?, ?, ?);',
        ['2', 'local', null],
      ),
    );
    await adapter.runInTransaction(stmts);
    final txDate1 = await satellite.performSnapshot();

    stmts = [];
    // For this key we will choose remote Tx, such that: Local TM < Remote TX
    stmts.add(Statement('DELETE FROM parent WHERE id = 1'));
    stmts.add(Statement('DELETE FROM parent WHERE id = 2'));
    await adapter.runInTransaction(stmts);
    await satellite.performSnapshot();

    final entries = await satellite.getEntries();
    //console.log(entries)
    expect(entries[0].newRow, isNotNull);
    expect(entries[1].newRow, isNotNull);

    // For this key we receive transaction which was older
    final electricEntrySameTs =
        DateTime.parse(entries[0].timestamp).millisecondsSinceEpoch;
    final electricEntrySame = generateRemoteOplogEntry(
      tableInfo,
      entries[0].namespace,
      entries[0].tablename,
      OpType.insert,
      electricEntrySameTs,
      '[]',
      newValues: json.decode(entries[0].newRow!) as Map<String, Object?>,
      oldValues: {},
    );

    // For this key we had concurrent insert transaction from another node `remote`
    // with same timestamp
    final electricEntryConflictTs =
        DateTime.parse(entries[1].timestamp).millisecondsSinceEpoch;
    final electricEntryConflict = generateRemoteOplogEntry(
      tableInfo,
      entries[1].namespace,
      entries[1].tablename,
      OpType.insert,
      electricEntryConflictTs,
      encodeTags([generateTag('remote', txDate1)]),
      newValues: json.decode(entries[1].newRow!) as Map<String, Object?>,
      oldValues: {},
    );

    satellite.relations =
        kTestRelations; // satellite must be aware of the relations in order to turn `DataChange`s into `OpLogEntry`s in `_applyTransaction`

    final electricEntrySameChange = opLogEntryToChange(
      electricEntrySame,
      kTestRelations,
    );
    final electricEntryConflictChange =
        opLogEntryToChange(electricEntryConflict, kTestRelations);
    final tx = Transaction(
      origin: clientId,
      commitTimestamp: Int64(
        DateTime.now().millisecondsSinceEpoch,
      ), // commit_timestamp doesn't matter for this test, it is only used to GC the oplog
      changes: [electricEntrySameChange, electricEntryConflictChange],
      lsn: [],
    );
    await satellite.applyTransaction(tx);

    final shadow = await getMatchingShadowEntries(adapter);
    final expectedShadow = [
      ShadowEntry(
        namespace: 'main',
        tablename: 'parent',
        primaryKey: '{"id":2}',
        tags: genEncodedTags('remote', [txDate1]),
      ),
    ];
    expect(shadow, expectedShadow);

    final userTable = await adapter.query(Statement('SELECT * FROM parent;'));
    final expectedUserTable = [
      {'id': 2, 'value': 'local', 'other': null},
    ];
    expect(expectedUserTable, userTable);
  });

  test('local (INSERT -> UPDATE -> DELETE) with remote equivalent', () async {
    await context.runMigrations();
    satellite.setAuthState(context.authState);
    final clientId = satellite.authState?.clientId ?? 'test_id';
    final txDate1 = DateTime.now();

    final insertEntry = generateRemoteOplogEntry(
      tableInfo,
      'main',
      'parent',
      OpType.update,
      txDate1.millisecondsSinceEpoch,
      genEncodedTags('remote', [txDate1]),
      newValues: {
        'id': 1,
        'value': 'local',
      },
      oldValues: {},
    );

    final deleteDate = txDate1.millisecondsSinceEpoch + 1;
    final deleteEntry = generateRemoteOplogEntry(
      tableInfo,
      'main',
      'parent',
      OpType.delete,
      deleteDate,
      genEncodedTags('remote', []),
      newValues: {
        'id': 1,
        'value': 'local',
      },
      oldValues: {},
    );

    satellite.relations =
        kTestRelations; // satellite must be aware of the relations in order to turn `DataChange`s into `OpLogEntry`s in `_applyTransaction`

    final insertChange = opLogEntryToChange(insertEntry, kTestRelations);
    final insertTx = Transaction(
      origin: clientId,
      commitTimestamp: Int64(txDate1.millisecondsSinceEpoch),
      changes: [insertChange],
      lsn: [],
    );
    await satellite.applyTransaction(insertTx);

    var shadow = await getMatchingShadowEntries(adapter);
    final expectedShadow = [
      ShadowEntry(
        namespace: 'main',
        tablename: 'parent',
        primaryKey: '{"id":1}',
        tags: genEncodedTags('remote', [txDate1]),
      ),
    ];
    expect(shadow, expectedShadow);

    final deleteChange = opLogEntryToChange(deleteEntry, kTestRelations);
    final deleteTx = Transaction(
      origin: clientId,
      commitTimestamp: Int64(deleteDate),
      changes: [deleteChange],
      lsn: [],
    );
    await satellite.applyTransaction(deleteTx);

    shadow = await getMatchingShadowEntries(adapter);
    expect(<ShadowEntry>[], shadow);

    final entries = await satellite.getEntries(since: 0);
    expect(<OplogEntry>[], entries);
  });
}
