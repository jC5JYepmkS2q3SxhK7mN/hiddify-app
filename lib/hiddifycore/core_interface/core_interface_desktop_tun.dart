import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:grpc/grpc.dart';
import 'package:hiddify/core/model/directories.dart';
import 'package:hiddify/hiddifycore/core_interface/core_interface_desktop.dart';
import 'package:hiddify/hiddifycore/core_interface/vpn_config_snapshot.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcommon/common.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore_service.pbgrpc.dart';
import 'package:hiddify/singbox/model/core_status.dart';
import 'package:hiddify/singbox/model/singbox_config_option.dart';
import 'package:path/path.dart' as p;
import 'package:rxdart/rxdart.dart';

/// Windows and Linux VPN: the full core usually runs in HiddifyTunnelService (elevated once at
/// install). The app talks to it over authenticated gRPC — same model as the unsigned macOS path.
///
/// Exceptions that keep TUN in this process (no service):
/// - the app is already root / Administrator (e.g. `sudo ./Hiddify.AppImage`);
/// - Linux AppImage cannot host a service (FUSE mount is invisible to `pkexec` as root).
class CoreInterfaceDesktopTun extends CoreInterfaceDesktop {
  CoreInterfaceDesktopTun() : super(port: 17078);

  static const _servicePort = 18020;
  final _status = BehaviorSubject<CoreStatus>.seeded(const CoreStatus.stopped());
  final _clientChanges = StreamController<void>.broadcast();
  ClientChannel? _serviceChannel;
  Directory? _workingDirectory;
  SingboxConfigOption? _options;
  bool _usingVPN = false;
  bool? _privileged;
  String? _secret;

  /// AppImage payload lives under a user FUSE mount; root/`pkexec` cannot exec that path.
  bool get _isAppImage => Platform.isLinux && (Platform.environment['APPIMAGE'] ?? '').isNotEmpty;

  @override
  bool get managesLifecycle => true;
  @override
  bool get persistsAfterAppExit => false;
  @override
  Stream<CoreStatus> get managedStatus => _status.stream;
  @override
  Stream<void> get clientChanges => _clientChanges.stream;

  String get _cliPath {
    final dir = p.dirname(Platform.resolvedExecutable);
    return p.join(dir, Platform.isWindows ? 'HiddifyCli.exe' : 'HiddifyCli');
  }

  String get _dataDir {
    if (Platform.isWindows) {
      final base = Platform.environment['PROGRAMDATA'] ?? r'C:\ProgramData';
      return p.join(base, 'Hiddify', 'TunnelService');
    }
    return '/var/lib/hiddify-tunnel';
  }

  String get _secretPath => p.join(_dataDir, 'control.secret');
  String get _buildStampPath => p.join(_dataDir, 'build.id');

  @override
  Future<String> setup(Directories directories, bool debug, int mode) async {
    final error = await super.setup(directories, debug, mode);
    if (error.isNotEmpty) return error;
    _workingDirectory = directories.workingDir.absolute;
    return '';
  }

  @override
  Future<void> setOptions(SingboxConfigOption options) async {
    _options = options;
    // Strip TUN only when the elevated service will own it; in-process TUN keeps enableTun.
    final apply = (options.enableTun && !await _isPrivileged())
        ? options.copyWith(enableTun: false)
        : options;
    final response = await fgClient.changeHiddifySettings(
      ChangeHiddifySettingsRequest(hiddifySettingsJson: jsonEncode(apply.toJson())),
    );
    _checkResponse(response);
  }

  @override
  Future<void> startManaged(String path, String name, bool disableMemoryLimit) async {
    final options = _options;
    if (options == null) throw StateError('Apply connection options before starting the core.');
    await stop();
    if (!options.enableTun) {
      _usingVPN = false;
      bgClient = fgClient;
      _clientChanges.add(null);
      _checkResponse(
        await fgClient.start(StartRequest(configPath: path, configName: name, disableMemoryLimit: disableMemoryLimit)),
      );
      _status.add(const CoreStatus.started());
      return;
    }

    // Already elevated: run TUN in this process. AppImage also cannot install a service
    // (pkexec cannot see the FUSE mount), so root AppImage uses the same path.
    if (await _isPrivileged()) {
      _status.add(const CoreStatus.starting());
      try {
        _usingVPN = false;
        bgClient = fgClient;
        _clientChanges.add(null);
        _checkResponse(
          await fgClient.changeHiddifySettings(
            ChangeHiddifySettingsRequest(hiddifySettingsJson: jsonEncode(options.toJson())),
          ),
        );
        _checkResponse(
          await fgClient.start(
            StartRequest(configPath: path, configName: name, disableMemoryLimit: disableMemoryLimit),
          ),
        );
        _status.add(const CoreStatus.started());
      } catch (error) {
        _status.add(CoreStatus.stopped(message: error.toString()));
        rethrow;
      }
      return;
    }

    if (_isAppImage) {
      throw StateError(
        'VPN mode in the AppImage needs root. Quit and run: sudo ${Platform.environment['APPIMAGE']}',
      );
    }

    _status.add(const CoreStatus.starting());
    try {
      await _ensureService();
      final workingDirectory = _workingDirectory;
      if (workingDirectory == null) throw StateError('Set up the core before starting VPN mode.');
      final snapshot = await snapshotVpnConfiguration(path, workingDirectory);
      final requestFile = await _writeConnectRequest(
        configContent: snapshot.$1,
        resources: snapshot.$2,
        configName: name,
        settingsJSON: jsonEncode(options.toJson()),
        disableMemoryLimit: disableMemoryLimit,
      );
      try {
        await _runCli(['tunnel', 'connect', requestFile.path]);
      } finally {
        await requestFile.delete().catchError((_) => requestFile);
      }
      _secret = await File(_secretPath).readAsString();
      _secret = _secret!.trim();
      if (_secret!.length < 32) throw StateError('The VPN service secret is missing. Reinstall the VPN service.');
      final old = _serviceChannel;
      _serviceChannel = ClientChannel(
        '127.0.0.1',
        port: _servicePort,
        options: const ChannelOptions(credentials: ChannelCredentials.insecure()),
      );
      bgClient = CoreClient(_serviceChannel!, options: CallOptions(metadata: {'x-hiddify-secret': _secret!}));
      if (old != null) unawaited(old.shutdown());
      _usingVPN = true;
      _clientChanges.add(null);
      _status.add(const CoreStatus.started());
    } catch (error) {
      _status.add(CoreStatus.stopped(message: error.toString()));
      rethrow;
    }
  }

  Future<bool> _isPrivileged() async {
    final cached = _privileged;
    if (cached != null) return cached;
    if (Platform.isLinux || Platform.isMacOS) {
      final result = await Process.run('id', ['-u']);
      _privileged = result.exitCode == 0 && result.stdout.toString().trim() == '0';
    } else if (Platform.isWindows) {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        '([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)',
      ]);
      _privileged = result.stdout.toString().trim().toLowerCase() == 'true';
    } else {
      _privileged = false;
    }
    return _privileged!;
  }

  Future<File> _writeConnectRequest({
    required String configContent,
    required Map<String, Uint8List> resources,
    required String configName,
    required String settingsJSON,
    required bool disableMemoryLimit,
  }) async {
    final encoded = <String, String>{};
    for (final entry in resources.entries) {
      encoded[entry.key] = base64Encode(entry.value);
    }
    final body = jsonEncode({
      'configContent': configContent,
      'configName': configName,
      'settingsJSON': settingsJSON,
      'resources': encoded,
      'disableMemoryLimit': disableMemoryLimit,
      'ownerPid': pid,
    });
    final file = File(p.join(Directory.systemTemp.path, 'hiddify-tunnel-$pid.json'));
    await file.writeAsString(body);
    return file;
  }

  Future<void> _ensureService() async {
    // Ready only when the running service binary matches this app's HiddifyCli exactly.
    // Matching builds connect with no prompt; a rebuild/upgrade reinstalls once.
    if (await _serviceReady()) return;
    final sameBinary = await _binariesMatch();
    if (File(_secretPath).existsSync() && sameBinary) {
      try {
        await _runCli(['tunnel', 'start']);
      } catch (_) {
        await _elevateInstall();
      }
    } else {
      await _elevateInstall();
    }
    for (var i = 0; i < 50; i++) {
      if (await _serviceReady()) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError('The VPN service was installed but did not start with this app build.');
  }

  Future<void> _elevateInstall() async {
    final owner = Platform.isWindows
        ? (Platform.environment['USERNAME'] ?? '')
        : (Platform.environment['USER'] ?? '');
    if (Platform.isWindows) {
      final cli = _cliPath.replaceAll("'", "''");
      final ownerArg = owner.replaceAll("'", "''");
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        "Start-Process -FilePath '$cli' -ArgumentList 'tunnel','install','$ownerArg' -Verb RunAs -Wait",
      ]);
      if (result.exitCode != 0) {
        throw StateError(result.stderr.toString().trim().isEmpty
            ? 'Could not install the VPN service. Allow the administrator prompt and try again.'
            : result.stderr.toString().trim());
      }
    } else {
      // pkexec clears the environment; pass the owner as a CLI argument.
      final result = await Process.run('pkexec', [_cliPath, 'tunnel', 'install', owner]);
      if (result.exitCode != 0) {
        throw StateError(result.stderr.toString().trim().isEmpty
            ? 'Could not install the VPN service. Allow the administrator prompt and try again.'
            : result.stderr.toString().trim());
      }
    }
  }

  Future<bool> _serviceReady() async {
    if (!File(_secretPath).existsSync()) return false;
    if (!await _binariesMatch()) return false;
    try {
      final socket = await Socket.connect('127.0.0.1', _servicePort, timeout: const Duration(milliseconds: 200));
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _binariesMatch() async {
    final stampFile = File(_buildStampPath);
    if (!stampFile.existsSync()) return false;
    final stamped = (await stampFile.readAsString()).trim();
    if (stamped.isEmpty || stamped == 'unset') return false;
    // Build id lives only in Go; ask the bundled HiddifyCli (same core the service should run).
    final result = await Process.run(_cliPath, ['tunnel', 'build-id']);
    if (result.exitCode != 0) return false;
    final bundled = result.stdout.toString().trim();
    return bundled.isNotEmpty && bundled != 'unset' && bundled == stamped;
  }

  Future<void> _runCli(List<String> args) async {
    final result = await Process.run(_cliPath, args);
    if (result.exitCode != 0) {
      final message = result.stderr.toString().trim();
      throw StateError(message.isEmpty ? 'The VPN service command failed.' : message);
    }
  }

  void _checkResponse(CoreInfoResponse response, {bool allowStopped = false}) {
    if (response.messageType != MessageType.EMPTY &&
        response.messageType != MessageType.ALREADY_STARTED &&
        !(allowStopped && response.messageType == MessageType.ALREADY_STOPPED)) {
      throw StateError('${response.messageType}: ${response.message}');
    }
  }

  @override
  Future<bool> stop() async {
    if (_usingVPN) {
      try {
        await _runCli(['tunnel', 'disconnect']);
      } catch (error) {
        loggy.warning('stopping the VPN service failed: $error');
      }
    }
    final old = _serviceChannel;
    _serviceChannel = null;
    if (old != null) await old.shutdown();
    _usingVPN = false;
    bgClient = fgClient;
    _clientChanges.add(null);
    _checkResponse(await fgClient.stop(Empty()), allowStopped: true);
    _status.add(const CoreStatus.stopped());
    return true;
  }

  @override
  Future<bool> isBgClientAvailable() async => !_usingVPN || await _serviceReady();

  @override
  Future<bool> resetTunnel() async {
    await stop();
    return true;
  }

  @override
  Future<void> dispose() async {
    await _serviceChannel?.shutdown();
    await _clientChanges.close();
    await _status.close();
  }
}
