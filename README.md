![Tests](https://github.com/SkillDevs/electric_dart/actions/workflows/tests.yml/badge.svg)
![E2E](https://github.com/SkillDevs/electric_dart/actions/workflows/e2e.yml/badge.svg)

[![pub package](https://img.shields.io/pub/v/electricsql.svg?label=electricsql&color=blue)](https://pub.dartlang.org/packages/electricsql)
[![pub package](https://img.shields.io/pub/v/electricsql_flutter.svg?label=electricsql_flutter&color=blue)](https://pub.dartlang.org/packages/electricsql_flutter)
[![pub package](https://img.shields.io/pub/v/electricsql_cli.svg?label=electricsql_cli&color=blue)](https://pub.dartlang.org/packages/electricsql_cli)

<h1>
    <img align="center" height="60" src="https://raw.githubusercontent.com/SkillDevs/electric_dart/master/resources/electric_dart_icon.png"/>
    Electric Dart
</h1>

#### 🛠️ WORK IN PROGRESS 🛠️

[Electric](https://electric-sql.com/) is currently in **public alpha** phase, and the Dart client is currently being developed introducing the new features from the official client as they come out.
For development updates make sure to check out the official [ElectricSQL Discord](https://discord.gg/B7kHGwDcbj) server, as well as the official [Javascript client](https://www.npmjs.com/package/electric-sql)  

---

Unofficial Dart client implementation for [Electric](https://electric-sql.com/).

Client based on the Typescript client from the `clients/typescript` subfolder from [electric git repository](https://github.com/electric-sql/electric) 

### Reference implementation: 

* [NPM package](https://www.npmjs.com/package/electric-sql).
* Version `v0.8.1-dev`
* Commit: `22652fb3e7616bc5d48f445cdad2d77a0c99c9a8`


### What's Electric?

ElectricSQL is a local-first software platform. Use it to build super fast, collaborative, offline-capable cross-platform apps directly on Postgres. [Introduction & Live Demos](https://electric-sql.com/docs/intro/local-first)


### Run the Todos example

This is a simple Todos app which can sync across all the platforms supported by Flutter (iOS, Android, Web, Windows, macOS and Linux).

[Instructions](https://github.com/SkillDevs/electric_dart/blob/master/todos_flutter/README.md)

![Electric Flutter](https://github.com/SkillDevs/electric_dart/assets/22084723/4fa1d198-97c6-48ef-9500-24bd1cf788ea)

## Quickstart

[Quickstart](https://github.com/SkillDevs/electric_dart/blob/master/docs/quickstart.md) to integrate Electric into your own Flutter app.


## Usage

### Instantiate

You can electrify a [`drift`](https://pub.dev/packages/drift) database or a [`sqlite3`](https://pub.dev/packages/sqlite3) database.

```dart
import 'package:electricsql/electricsql.dart';
import 'package:electricsql_flutter/drivers/drift.dart'; // or sqlite3.dart

// This would be the Drift database
AppDatabase db;

final electric = await electrify<AppDatabase>(
    dbName: '<db_name>',
    db: db,
    // Bundled migrations. This variable is autogenerated using 
    // `dart run electricsql_cli generate`
    migrations: kElectricMigrations,
    config: ElectricConfig(
        auth: AuthConfig(
            // https://electric-sql.com/docs/usage/auth
            // You can use the functions `insecureAuthToken` or `secureAuthToken` to generate one
            token: '<your JWT>',
        ),
        // logger: LoggerConfig(
        //     level: Level.debug, // in production you can use Logger.off
        // ),
        // url: '<ELECTRIC_SERVICE_URL>',
    ),
);
```

### Sync data

Sync data into the local database. This only needs to be called once. [Shapes](https://electric-sql.com/docs/usage/data-access/shapes)

```dart
final shape = await electric.syncTables([
    'todos',
])
```

### Read data

Bind live data to the widgets. This can be possible when using drift + its Stream queries.

```dart
AppDatabase db;
// Since we've electrified it, we can now use the original database instance normally.
final Stream<List<Todo>> todosStream = db.select(db.todos).watch();

// Stateful Widget + initState
todosStream.listen((liveTodos) {
    setState(() => todos = liveTodos.toList());
});

// StreamBuilder
StreamBuilder<List<Todo>>(
    stream: todosStream,
    builder: (context, snapshot) {
        ...
    },
);
```

### Write data

You can use the original database instance normally so you don't need to change your database code at all. The data will be synced automatically, even raw SQL statements.

```dart
AppDatabase db;
await db.into(db.todos).insert(TodosCompanion(
    title: Value('My todo'),
    completed: Value(false),
));

// Or raw SQL
await db.customInsert(
    'INSERT INTO todos (title, completed) VALUES (?, ?)', 
    variables: [Variable('My todo'), Variable(false)],
    updates: {db.todos}, // This will notify stream queries to rebuild the widget
);
```

This automatic reactivity works no matter where the write is made — locally, [on another device, by another user](https://electric-sql.com/docs/intro/multi-user), or [directly into Postgres](https://electric-sql.com/docs/intro/active-active).

## More about ElectricSQL

Check out the official docs from ElectricSQL [here](https://electric-sql.com/docs) to look at live demos, API docs and integrations.

---

## Development instructions for maintainers and contributors

Dart 3.x and Melos required

`dart pub global activate melos`


### Bootstrap the workspace

`melos bs`


### Generate the Protobuf code

Install the `protoc_plugin` Dart package.

`dart pub global activate protoc_plugin`

To generate the code

`melos generate_proto`


### Run the tests

`melos test:all`
