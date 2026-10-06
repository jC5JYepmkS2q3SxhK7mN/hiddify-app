import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/region.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/app_based_routing/model/per_app_proxy_mode.dart';
import 'package:hiddify/features/app_based_routing/overview/app_list_notifier.dart';
import 'package:hiddify/features/route_rules/notifier/rules_notifier.dart';
import 'package:hiddify/features/route_rules/widget/rule_tile.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/settings/widget/preference_tile.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class RoutingOptionsPage extends HookConsumerWidget {
  const RoutingOptionsPage({super.key, required this.routeRule});

  // Import route rule from deep link
  final String? routeRule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);
    final appBasedRouting = ref.watch(Preferences.perAppProxyMode).enabled;
    final rules = ref.watch(rulesNotifierProvider);
    final showGeneralOptions = ref.watch(Preferences.showRouteGeneralOptions);

    final animationController = useAnimationController(
      duration: const Duration(milliseconds: 300),
      initialValue: showGeneralOptions ? 1.0 : 0.0,
    );

    useEffect(() {
      if (showGeneralOptions) {
        animationController.forward();
      } else {
        animationController.reverse();
      }
      return null;
    }, [showGeneralOptions]);

    final menuItems = <PopupMenuEntry>[
      PopupMenuItem(
        onTap: ref.read(rulesNotifierProvider.notifier).importRulesFromClipboard,
        child: Text(t.pages.settings.routing.routeRule.options.import.clipboard),
      ),
      PopupMenuItem(
        onTap: ref.read(rulesNotifierProvider.notifier).importRulesFromJsonFile,
        child: Text(t.pages.settings.routing.routeRule.options.import.file),
      ),
      const PopupMenuDivider(),
      PopupMenuItem(
        onTap: () async => await ref.read(rulesNotifierProvider.notifier).exportJsonToClipboard(),
        child: Text(t.pages.settings.routing.routeRule.options.export.clipboard),
      ),
      PopupMenuItem(
        onTap: () async => await ref.read(rulesNotifierProvider.notifier).saveRulesAsJsonFile(),
        child: Text(t.pages.settings.routing.routeRule.options.export.file),
      ),
      const PopupMenuDivider(),
      PopupMenuItem(
        onTap: ref.read(rulesNotifierProvider.notifier).resetRules,
        child: Text(t.pages.settings.routing.routeRule.options.reset),
      ),
    ];

    useMemoized(() {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (routeRule != null && context.mounted) {
          await ref.read(rulesNotifierProvider.notifier).importRulesFromDeepLink(routeRule!);
        }
      });
    });
    return Scaffold(
      appBar: AppBar(
        title: Text(t.pages.settings.routing.title),
        actions: [
          PopupMenuButton(
            icon: const Icon(Icons.more_vert_rounded),
            itemBuilder: (_) => rules.isEmpty ? menuItems.getRange(0, 2).toList() : menuItems,
          ),
          const Gap(8),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                if (rules.isNotEmpty)
                  Positioned.fill(
                    child: ReorderableListView.builder(
                      padding: const EdgeInsets.only(bottom: 56 + 16 + 16),
                      buildDefaultDragHandles: false,
                      onReorder: ref.read(rulesNotifierProvider.notifier).reorder,
                      itemBuilder: (context, index) => RuleTile(key: Key('$index'), index: index, rule: rules[index]),
                      itemCount: rules.length,
                    ),
                  )
                else
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        t.pages.settings.routing.routeRule.empty,
                        style: theme.textTheme.bodyLarge!.copyWith(color: theme.colorScheme.onSurface),
                      ),
                    ),
                  ),
                Positioned(
                  right: 0,
                  left: 0,
                  bottom: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Material(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                        ),
                        child: InkWell(
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(16),
                            topRight: Radius.circular(16),
                          ),
                          onTap: () =>
                              ref.read(Preferences.showRouteGeneralOptions.notifier).update(!showGeneralOptions),
                          child: Container(
                            height: 32,
                            padding: const EdgeInsetsDirectional.only(start: 16, end: 8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(t.pages.settings.routing.title),
                                const Gap(4),
                                Icon(
                                  showGeneralOptions ? Icons.arrow_drop_down_rounded : Icons.arrow_drop_up_rounded,
                                  size: 16,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizeTransition(
            sizeFactor: CurvedAnimation(parent: animationController, curve: Curves.easeInOut),
            axisAlignment: -1,
            child: Column(
              children: [
                Divider(height: 4, thickness: 4, color: theme.colorScheme.primaryContainer),
                ChoicePreferenceWidget(
                  selected: ref.watch(ConfigOptions.region),
                  preferences: ref.watch(ConfigOptions.region.notifier),
                  choices: Region.values,
                  title: t.pages.settings.routing.region,
                  showFlag: true,
                  icon: Icons.place_rounded,
                  presentChoice: (value) => value.present(t),
                  onChanged: (val) async {
                    await ref.read(ConfigOptions.directDnsAddress.notifier).reset();
                    final autoRegion = ref.read(Preferences.autoAppsSelectionRegion);
                    final mode = ref.read(Preferences.perAppProxyMode).toAppProxy();
                    if (autoRegion != val &&
                        autoRegion != null &&
                        val != Region.other &&
                        mode != null &&
                        PlatformUtils.isAndroid) {
                      await ref
                          .read(dialogNotifierProvider.notifier)
                          .showOk(
                            t.pages.settings.routing.appBasedRouting.autoSelection.dialog.title,
                            t.pages.settings.routing.appBasedRouting.autoSelection.dialog.msg(region: val.name),
                          );
                      await ref.read(AppListProvider(mode).notifier).clearAutoSelected();
                    }
                  },
                ),
                if (PlatformUtils.isAndroid)
                  ListTile(
                    title: Text(t.pages.settings.routing.appBasedRouting.title),
                    leading: const Icon(Icons.apps_rounded),
                    trailing: Switch(
                      value: appBasedRouting,
                      onChanged: (value) async {
                        final newMode = appBasedRouting ? PerAppProxyMode.off : PerAppProxyMode.exclude;
                        await ref.read(Preferences.perAppProxyMode.notifier).update(newMode);
                        if (!appBasedRouting && context.mounted) context.goNamed('appList');
                      },
                    ),
                    onTap: () async {
                      if (!appBasedRouting) {
                        await ref.read(Preferences.perAppProxyMode.notifier).update(PerAppProxyMode.exclude);
                      }
                      if (context.mounted) context.goNamed('appList');
                    },
                  ),
                ChoicePreferenceWidget(
                  title: t.pages.settings.routing.balancerStrategy.title,
                  icon: Icons.balance_rounded,
                  selected: ref.watch(ConfigOptions.balancerStrategy),
                  preferences: ref.watch(ConfigOptions.balancerStrategy.notifier),
                  choices: BalancerStrategy.values,
                  presentChoice: (value) => value.present(t),
                ),
                SwitchListTile.adaptive(
                  title: Text(t.pages.settings.routing.resolveDestination),
                  secondary: const Icon(Icons.find_replace_rounded),
                  value: ref.watch(ConfigOptions.resolveDestination),
                  onChanged: ref.read(ConfigOptions.resolveDestination.notifier).update,
                ),
                ChoicePreferenceWidget(
                  selected: ref.watch(ConfigOptions.ipv6Mode),
                  preferences: ref.watch(ConfigOptions.ipv6Mode.notifier),
                  choices: IPv6Mode.values,
                  title: t.pages.settings.routing.ipv6Route,
                  icon: Icons.looks_6_rounded,
                  presentChoice: (value) => value.present(t),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: t.pages.settings.routing.routeRule.add,
        onPressed: () => context.goNamed('rule', pathParameters: {'orderId': 'new'}),
        child: const Icon(Icons.add_rounded),
      ),
    );
  }
}
