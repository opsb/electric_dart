import 'dart:async';

import 'package:args/command_runner.dart';
import 'package:electricsql_cli/src/commands/docker_commands/docker_utils.dart';
import 'package:electricsql_cli/src/config.dart';
import 'package:electricsql_cli/src/logger.dart';
import 'package:electricsql_cli/src/util.dart';

class DockerStatusCommand extends Command<int> {
  DockerStatusCommand({
    required Logger logger,
  }) : _logger = logger;

  @override
  String get description =>
      'Show status of the ElectricSQL sync service docker containers';

  @override
  String get name => 'status';

  // ignore: unused_field
  final Logger _logger;

  @override
  FutureOr<int>? run() async {
    final config = getConfig();
    return await runStatusCommand(config: config);
  }
}

Future<int> runStatusCommand({required Config config}) async {
  final containerName = config.read<String>('CONTAINER_NAME');
  final p = await dockerCompose('ps', [], containerName: containerName);
  return await waitForProcess(p);
}
