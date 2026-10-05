import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'auto_selection_notifier.g.dart';

@Riverpod()
class AutoSelectionLoading extends _$AutoSelectionLoading {
  @override
  bool build() => false;

  Future<T?> doAsync<T>(Future<T> Function() operation) async {
    state = true;
    final T? result = await operation();
    state = false;
    return result;
  }
}
