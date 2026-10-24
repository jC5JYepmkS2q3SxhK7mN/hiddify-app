import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/model/directories.dart';
import 'package:hiddify/hiddifycore/core_interface/core_interface_desktop.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcommon/common.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pbenum.dart';

/// macOS/desktop smoke: start the native core with mTLS and complete an RPC.
void main() {
  test('desktop mTLS hello round-trip', () async {
    if (!(Platform.isMacOS || Platform.isLinux || Platform.isWindows)) {
      return;
    }

    final tmp = await Directory.systemTemp.createTemp('hiddify-mtls-desktop-');
    addTearDown(() async {
      try {
        CoreInterfaceDesktop.nativeLibrary.closeGrpc(SetupMode.GRPC_NORMAL.value);
      } catch (_) {}
      await tmp.delete(recursive: true);
    });

    final core = CoreInterfaceDesktop(port: 17178);
    final err = await core.setup(
      (baseDir: tmp, workingDir: tmp, tempDir: tmp),
      true,
      SetupMode.GRPC_NORMAL.value,
    );
    expect(err, isEmpty, reason: 'setup should succeed with mTLS: $err');

    final info = await core.fgClient.getSystemInfo(Empty());
    expect(info, isNotNull);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
