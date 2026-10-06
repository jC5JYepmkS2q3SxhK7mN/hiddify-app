import 'dart:async';

import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/app_based_routing/data/auto_selection_repository.dart';
import 'package:hiddify/features/app_based_routing/data/auto_selection_repository_provider.dart';
import 'package:hiddify/features/app_based_routing/data/selected_data_provider.dart';
import 'package:hiddify/features/app_based_routing/model/per_app_proxy_mode.dart';
import 'package:hiddify/features/app_based_routing/overview/auto_selection_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:installed_apps/index.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_based_routing_notifier.g.dart';

@riverpod
class AppBasedRouting extends _$AppBasedRouting with AppLogger {
  StreamSubscription? _includeSubscription;
  StreamSubscription? _excludeSubscription;
  Timer? _timer;
  @override
  Future<void> build() async {
    final phonePkgs = (await InstalledApps.getInstalledApps(false)).map((e) => e.packageName).toSet();
    _includeSubscription = ref
        .read(appProxyDataSourceProvider)
        .watchActivePackages(phonePkgs: phonePkgs, mode: AppProxyMode.include)
        .listen((pkgs) => ref.read(Preferences.includeApps.notifier).update(pkgs));
    _excludeSubscription = ref
        .read(appProxyDataSourceProvider)
        .watchActivePackages(phonePkgs: phonePkgs, mode: AppProxyMode.exclude)
        .listen((pkgs) => ref.read(Preferences.excludeApps.notifier).update(pkgs));

    _timer = Timer.periodic(const Duration(days: 1), (_) async => await _autoSelectionUpdate());
    ref.onDispose(() {
      _includeSubscription?.cancel();
      _excludeSubscription?.cancel();
      _timer?.cancel();
    });
    await _autoSelectionUpdate();
  }

  AppProxyMode? get _mode => ref.read(Preferences.perAppProxyModeInUse);

  bool get _autoOn => ref.read(Preferences.autoAppsSelectionRegion) != null;

  Future<void> setAutoSelection(bool enabled) async {
    final mode = _mode;
    if (mode == null) return;
    if (enabled) {
      await _loading(() => _applyAutoSelection(mode));
    } else {
      await _clearAutoSelection(mode);
      ref.read(autoSelectionIssueProvider.notifier).update(null);
    }
  }

  Future<void> updateAutoSelection() async {
    final mode = _mode;
    if (mode != null) await _loading(() => _applyAutoSelection(mode));
  }

  /// Ticks again the auto apps the user removed.
  Future<void> restoreRemoved() async {
    final mode = _mode;
    if (mode != null) await ref.read(appProxyDataSourceProvider).revertForceDeselection(mode: mode);
  }

  Future<void> _autoSelectionUpdate() async {
    final mode = _mode;
    if (!_autoOn || mode == null) return;
    final lastUpdate = ref.read(Preferences.autoAppsSelectionLastUpdate);
    if (lastUpdate != null && DateTime.now().difference(lastUpdate) < const Duration(days: 1)) return;
    await _loading(() => _applyAutoSelection(mode));
  }

  Future<AutoSelectionResult> _applyAutoSelection(AppProxyMode mode) async {
    loggy.info('Performing auto selection');
    final region = ref.read(ConfigOptions.region);
    final (list, result) = await ref.read(autoSelectionRepoProvider).getByAppProxyMode(mode: mode, region: region);
    if (result == AutoSelectionResult.success) {
      await ref.read(appProxyDataSourceProvider).applyAutoSelection(autoList: list!, mode: mode);
      await ref.read(Preferences.autoAppsSelectionRegion.notifier).update(region);
      await ref.read(Preferences.autoAppsSelectionLastUpdate.notifier).update(DateTime.now());
    } else if (result == AutoSelectionResult.notFound) {
      // this region has no list for this mode, so auto selection turns off
      await _clearAutoSelection(mode);
    }
    ref.read(autoSelectionIssueProvider.notifier).update(result);
    return result;
  }

  Future<void> _clearAutoSelection(AppProxyMode mode) async {
    loggy.info('Clearing auto selected');
    await ref.read(appProxyDataSourceProvider).clearAutoSelected(mode: mode);
    await ref.read(Preferences.autoAppsSelectionRegion.notifier).update(null);
    await ref.read(Preferences.autoAppsSelectionLastUpdate.notifier).update(null);
  }

  Future<void> _loading(Future<void> Function() operation) =>
      ref.read(autoSelectionLoadingProvider.notifier).doAsync(operation);
}
