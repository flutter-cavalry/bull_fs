import 'dart:async';

class BFSerialQueue {
  Future<void> _last = Future.value();

  Future<T> queueAndWait<T>(Future<T> Function() action) {
    final completer = Completer<T>();

    _last = _last.then((_) async {
      try {
        final result = await action();
        completer.complete(result);
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });

    return completer.future;
  }

  void queue<T>(Future<T> Function() action) {
    // ignore: discarded_futures
    queueAndWait(action);
  }

  Future<void> drain() => _last;
}
