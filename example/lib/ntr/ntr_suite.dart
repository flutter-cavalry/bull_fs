import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

class NTRHandle {
  final dynamic data;

  NTRHandle(this.data);

  void notNull(Object? actual) {
    if (actual == null) {
      throw Exception('Expected: not null, Actual: null');
    }
  }

  void equals<T>(T actual, T expected) {
    if (expected != actual) {
      throw Exception('Expected: $expected, Actual: $actual');
    }
  }

  void mapEquals<T, U>(Map<T, U>? a, Map<T, U>? b) {
    if (!const DeepCollectionEquality().equals(a, b)) {
      throw Exception('Expected: ${jsonEncode(b)}, Actual: ${jsonEncode(a)}');
    }
  }

  void isTrue(bool actual) {
    if (!actual) {
      throw Exception('Expected: true, Actual: false');
    }
  }

  void isFalse(bool actual) {
    if (actual) {
      throw Exception('Expected: false, Actual: true');
    }
  }

  void isNull(Object? actual) {
    if (actual != null) {
      throw Exception('Expected: null, Actual: $actual');
    }
  }
}

class NTRTime {
  final String name;
  final Duration duration;

  NTRTime(this.name, this.duration);
}

class NTRSuite {
  final String suiteName;
  final List<String> _caseNames = [];
  final List<Future<void> Function()> _cases = [];

  List<String> _failed = [];
  final List<NTRTime> _durations = [];

  void Function(String s)? onLog;
  Future<dynamic> Function()? beforeEach;
  Future<void> Function(NTRHandle h)? afterEach;

  NTRSuite({required this.suiteName});

  void add(String name, Future<void> Function(NTRHandle h) fn) {
    _caseNames.add(name.toLowerCase());
    _cases.add(() async {
      NTRHandle? h;
      final startTime = DateTime.now();
      try {
        final data = await beforeEach?.call();
        h = NTRHandle(data);
        onLog?.call(name);
        await fn(h);
      } catch (err, st) {
        _failed.add(name);
        debugPrint('❌ $name\n$err\n');
        debugPrintStack(stackTrace: st);
      } finally {
        final endTime = DateTime.now();
        final duration = endTime.difference(startTime);
        _durations.add(NTRTime(name, duration));
        debugPrint('Duration: $name (${duration.inMilliseconds}ms)');
        if (h != null) {
          // `afterEach` only gets called when `beforeEach` is called (i.e. NTRHandle is created).
          await afterEach?.call(h);
        }
      }
    });
  }

  Future<List<String>> run({String? debugName}) async {
    _failed = [];
    List<Future<void>> futures = [];
    for (var i = 0; i < _caseNames.length; i++) {
      if (debugName == null || _caseNames[i].contains(debugName)) {
        futures.add(_cases[i].call());
      }
    }
    await Future.wait(futures);
    return _failed;
  }

  List<NTRTime> reportDurations() {
    _durations.sort((a, b) => b.duration.compareTo(a.duration));
    return _durations;
  }
}
