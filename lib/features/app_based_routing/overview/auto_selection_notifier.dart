import 'package:hiddify/features/app_based_routing/data/auto_selection_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'auto_selection_notifier.g.dart';

@Riverpod(keepAlive: true)
class AutoSelectionLoading extends _$AutoSelectionLoading {
  @override
  bool build() => false;

  Future<T?> doAsync<T>(Future<T> Function() operation) async {
    state = true;
    try {
      return await operation();
    } finally {
      state = false;
    }
  }
}

/// Why the last auto selection did not give a list. Null when it worked or was not tried.
@Riverpod(keepAlive: true)
class AutoSelectionIssue extends _$AutoSelectionIssue {
  @override
  AutoSelectionResult? build() => null;

  void update(AutoSelectionResult? result) => state = result == AutoSelectionResult.success ? null : result;
}
