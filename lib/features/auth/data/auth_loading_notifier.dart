import 'package:flutter_riverpod/flutter_riverpod.dart';

class AuthLoadingNotifier extends Notifier<bool> {
  @override
  bool build() {
    return false;
  }

  void setLoading(bool loading) {
    state = loading;
  }
}
