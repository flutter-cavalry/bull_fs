import 'dart:async';

class BFSerialQueue {
  Future<void> _last = Future.value();

  Future<void> queueAndWait(FutureOr<void> Function(void) action) {
    _last = _last.then(action);
    return _last;
  }

  void queue(FutureOr<void> Function(void) action) {
    // ignore: discarded_futures
    queueAndWait(action);
  }

  Future<void> drain() => _last;
}
