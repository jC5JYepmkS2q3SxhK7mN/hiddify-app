import 'package:circle_flags/circle_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/region.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/app_based_routing/model/per_app_proxy_mode.dart';
import 'package:hiddify/features/app_based_routing/overview/app_based_routing_notifier.dart';
import 'package:hiddify/features/route_rules/notifier/rules_notifier.dart';
import 'package:hiddify/features/route_rules/widget/rule_tile.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
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
    final rules = ref.watch(rulesNotifierProvider);

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
          const _RegionChip(),
          PopupMenuButton(icon: const Icon(Icons.more_vert_rounded), itemBuilder: (_) => menuItems),
          const Gap(8),
        ],
      ),
      // the built-in rules are always there, so the list is never empty
      body: ReorderableListView.builder(
        padding: const EdgeInsets.only(bottom: 56 + 16 + 16),
        buildDefaultDragHandles: false,
        header: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // native, so it applies before every rule
            if (PlatformUtils.isAndroid) const _AppBasedRoutingSection(),
            const _PinnedOptions(),
          ],
        ),
        onReorder: ref.read(rulesNotifierProvider.notifier).reorder,
        itemBuilder: (context, index) => RuleTile(key: Key('$index'), index: index, rule: rules[index]),
        itemCount: rules.length,
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: t.pages.settings.routing.routeRule.add,
        onPressed: () => context.goNamed('rule', pathParameters: {'orderId': 'new'}),
        child: const Icon(Icons.add_rounded),
      ),
    );
  }
}

/// The region decides the region rule and auto selection, so it stays in sight; the flag shows which one.
class _RegionChip extends ConsumerWidget {
  const _RegionChip();

  static const _radius = BorderRadius.all(Radius.circular(8));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);
    final region = ref.watch(ConfigOptions.region);
    final colorScheme = theme.colorScheme;
    // a popup menu, so back closes it and not the page
    return PopupMenuButton<Region>(
      tooltip: region.presentName(t),
      position: PopupMenuPosition.under,
      borderRadius: _radius,
      onSelected: (value) async {
        if (value == region) return;
        await ref.read(ConfigOptions.region.notifier).update(value);
        // the direct DNS server's default depends on the region
        await ref.read(ConfigOptions.directDnsAddress.notifier).reset();
      },
      itemBuilder: (_) => [
        for (final option in Region.values)
          PopupMenuItem(
            value: option,
            child: Row(
              children: [
                _RegionFlag(option),
                const Gap(12),
                Expanded(child: Text(option.presentName(t))),
                if (option == region) const Icon(Icons.check_rounded),
              ],
            ),
          ),
      ],
      child: Container(
        height: 32,
        decoration: BoxDecoration(
          border: Border.all(color: colorScheme.outline),
          borderRadius: _radius,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // as tall as the chip: its outer corners follow the line's, its inner ones meet the word
            _RegionFlag(
              region,
              size: 30,
              borderRadius: const BorderRadiusDirectional.horizontal(start: Radius.circular(7)),
            ),
            const Gap(8),
            Text(
              t.pages.settings.routing.region,
              style: theme.textTheme.labelLarge?.copyWith(color: colorScheme.onSurface),
            ),
            Icon(Icons.arrow_drop_down_rounded, size: 20, color: colorScheme.onSurfaceVariant),
            const Gap(4),
          ],
        ),
      ),
    );
  }
}

/// Square, like the other flags in the app; Other has a gray tile with a globe in the same shape.
class _RegionFlag extends StatelessWidget {
  const _RegionFlag(this.region, {this.size = 24, this.borderRadius = const BorderRadius.all(Radius.circular(6))});

  final Region region;
  final double size;
  final BorderRadiusGeometry borderRadius;

  @override
  Widget build(BuildContext context) {
    if (region == Region.other) {
      final colorScheme = Theme.of(context).colorScheme;
      return Container(
        width: size,
        height: size,
        // a tint of the text color, so it shows on any background
        decoration: BoxDecoration(color: colorScheme.onSurface.withValues(alpha: 0.1), borderRadius: borderRadius),
        child: Icon(Icons.public_rounded, size: size * 2 / 3, color: colorScheme.onSurfaceVariant),
      );
    }
    return CircleFlag(
      // the lion and sun, as for the IP's country
      region == Region.ir ? 'ir-shir' : region.name,
      size: size,
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
    );
  }
}

/// App-based routing works through the Android VPN app list, so it sits above the rules and can't be moved.
class _AppBasedRoutingSection extends ConsumerWidget {
  const _AppBasedRoutingSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final appBasedRouting = t.pages.settings.routing.appBasedRouting;
    final mode = ref.watch(Preferences.perAppProxyModeInUse);
    final service = ref.read(appBasedRoutingProvider.notifier);
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // both modes sit under the name, the other one a tap away; only the switch turns it off
          ListTile(
            title: Text(appBasedRouting.title),
            subtitle: mode == null
                ? null
                // the pills start where the title starts, a little below it
                : Transform.translate(
                    offset: const Offset(0, 2),
                    child: Wrap(
                      spacing: 4,
                      children: [
                        for (final option in const [AppProxyMode.exclude, AppProxyMode.include])
                          _ModeOption(
                            label: option.present(t),
                            selected: option == mode,
                            onTap: () => service.changeMode(option),
                          ),
                      ],
                    ),
                  ),
            onTap: mode == null ? () => service.setEnabled(true) : null,
            trailing: Switch(value: mode != null, onChanged: service.setEnabled),
          ),
          const Divider(height: 3, thickness: 3),
        ],
      ),
    );
  }
}

/// A mode under the section's name: the current one sits in a tinted pill, the other is a tap away.
class _ModeOption extends StatelessWidget {
  const _ModeOption({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const radius = BorderRadius.all(Radius.circular(12));
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: selected ? null : onTap,
        borderRadius: radius,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: selected ? BoxDecoration(color: colorScheme.secondaryContainer, borderRadius: radius) : null,
          child: Text(
            label,
            style: TextStyle(color: selected ? colorScheme.onSecondaryContainer : colorScheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

/// Options for every rule, so they head the rules and can't be moved.
class _PinnedOptions extends ConsumerWidget {
  const _PinnedOptions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final routing = t.pages.settings.routing;
    const divider = Divider(height: 1, indent: 16, endIndent: 16);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _MenuOption(
          title: routing.balancerStrategy.title,
          selected: ref.watch(ConfigOptions.balancerStrategy),
          choices: BalancerStrategy.values,
          present: (value) => value.present(t),
          onSelected: ref.read(ConfigOptions.balancerStrategy.notifier).update,
        ),
        divider,
        SwitchListTile.adaptive(
          title: Text(routing.resolveDestination),
          value: ref.watch(ConfigOptions.resolveDestination),
          onChanged: ref.read(ConfigOptions.resolveDestination.notifier).update,
        ),
        divider,
        _MenuOption(
          title: routing.ipv6Route,
          selected: ref.watch(ConfigOptions.ipv6Mode),
          choices: IPv6Mode.values,
          present: (value) => value.present(t),
          onSelected: ref.read(ConfigOptions.ipv6Mode.notifier).update,
        ),
        const Divider(height: 3, thickness: 3),
      ],
    );
  }
}

/// A choice on one line: the value sits at the end, and its menu opens there.
class _MenuOption<T> extends HookWidget {
  const _MenuOption({
    required this.title,
    required this.selected,
    required this.choices,
    required this.present,
    required this.onSelected,
  });

  final String title;
  final T selected;
  final List<T> choices;
  final String Function(T value) present;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    final menu = useMemoized(GlobalKey<PopupMenuButtonState<T>>.new);
    return ListTile(
      title: Text(title),
      // the row takes the tap, so all of it ripples
      onTap: () => menu.currentState?.showButtonMenu(),
      trailing: IgnorePointer(
        // a popup menu, so back closes it and not the page
        child: PopupMenuButton<T>(
          key: menu,
          position: PopupMenuPosition.under,
          onSelected: onSelected,
          itemBuilder: (_) => [
            for (final choice in choices)
              PopupMenuItem(
                value: choice,
                child: Row(
                  children: [
                    Expanded(child: Text(present(choice))),
                    if (choice == selected) const Icon(Icons.check_rounded),
                  ],
                ),
              ),
          ],
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(present(selected), style: theme.textTheme.bodyMedium?.copyWith(color: color)),
              Icon(Icons.arrow_drop_down_rounded, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
