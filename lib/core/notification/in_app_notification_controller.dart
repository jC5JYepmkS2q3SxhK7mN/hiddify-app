import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'in_app_notification_controller.g.dart';

/// The app's [ScaffoldMessenger], so a notification can be shown without a [BuildContext].
final appScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

@Riverpod(keepAlive: true)
InAppNotificationController inAppNotificationController(Ref ref) {
  return InAppNotificationController();
}

enum NotificationType { info, error, success }

/// A button at the end of a toast, such as Undo. Pressing it also closes the toast.
typedef ToastAction = ({String label, VoidCallback onPressed});

class InAppNotificationController with AppLogger {
  void _show(String message, {NotificationType type = NotificationType.info, ToastAction? action}) {
    // Notifications raised during bootstrap (before runApp) have no messenger to show them yet.
    final messenger = appScaffoldMessengerKey.currentState;
    if (messenger == null) {
      loggy.warning("failed to show notification, the app is not ready yet");
      return;
    }
    showAppSnackBar(messenger, message, type: type, action: action);
  }

  void showErrorToast(String message) => _show(message, type: NotificationType.error);

  void showSuccessToast(String message, {ToastAction? action}) =>
      _show(message, type: NotificationType.success, action: action);

  void showInfoToast(String message, {ToastAction? action}) => _show(message, action: action);
}

/// Shows [message] as the app's SnackBar, replacing the one on screen.
///
/// A SnackBar starts its close timer only once it is fully on screen, so one raised while the app
/// draws no frames (in the background) still closes after it shows.
void showAppSnackBar(
  ScaffoldMessengerState messenger,
  String message, {
  NotificationType type = NotificationType.info,
  ToastAction? action,
}) {
  final side = math.max(16.0, (MediaQuery.sizeOf(messenger.context).width - 480) / 2);
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(message, maxLines: 6, overflow: TextOverflow.ellipsis),
        behavior: SnackBarBehavior.floating,
        // at most 480 wide, 16 from the sides on a narrow screen. A margin instead of a width: SnackBar
        // takes only one of them. On a phone it clears the 80 high bottom bar by 12.
        margin: EdgeInsets.fromLTRB(side, 0, side, Breakpoint(messenger.context).isMobile() ? 92 : 16),
        action: action == null ? null : SnackBarAction(label: action.label, onPressed: action.onPressed),
        // closes itself even with an action (a SnackBar keeps it by default)
        persist: false,
        // 4 s, a Material 3 snackbar's time; 8 s with a button, to read it and reach the button
        duration: Duration(seconds: action == null ? 4 : 8),
      ),
    );
}

/// Shows the app's SnackBars above every route, so a dialog or a bottom sheet can't cover them.
///
/// It is a Scaffold around the Navigator. The pages' Scaffolds sit inside it, and a
/// ScaffoldMessenger shows a SnackBar only on the outermost of its Scaffolds: this one.
class SnackBarHost extends StatelessWidget {
  const SnackBarHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    // no top padding: on iOS a Scaffold puts a status bar tap target there, over the pages' own
    final hostMediaQuery = mediaQuery.removePadding(removeTop: true);
    return MediaQuery(
      // the keyboard as bottom padding: a floating SnackBar stays above both
      data: hostMediaQuery.copyWith(
        viewPadding: hostMediaQuery.viewPadding.copyWith(
          bottom: math.max(mediaQuery.viewPadding.bottom, mediaQuery.viewInsets.bottom),
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        // the pages keep their full height and handle the keyboard themselves
        resizeToAvoidBottomInset: false,
        // the pages get the app's MediaQuery as it was
        body: MediaQuery(data: mediaQuery, child: child),
      ),
    );
  }
}
