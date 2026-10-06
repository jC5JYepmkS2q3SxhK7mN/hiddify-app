import 'package:circle_flags/circle_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/region.dart';
import 'package:hiddify/features/route_rules/notifier/rules_notifier.dart';
import 'package:hiddify/features/route_rules/widget/rule_tile.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
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
