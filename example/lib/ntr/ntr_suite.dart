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

class NTRSuite {
  final String suiteName;
  final List<String> _caseNames = [];
  final List<Future<void> Function()> _cases = [];

  List<String> _failed = [];

  void Function(String s)? onLog;
  Future<dynamic> Function()? beforeAll;
  Future<void> Function(NTRHandle h)? afterAll;

  NTRSuite({required this.suiteName});

  void add(String name, Future<void> Function(NTRHandle h) fn) {
    _caseNames.add(name.toLowerCase());
    _cases.add(() async {
      NTRHandle? h;
      try {
        final data = await beforeAll?.call();
        h = NTRHandle(data);
        onLog?.call(name);
        await fn(h);
      } catch (err, st) {
        _failed.add(name);
        debugPrint('❌ $name\n$err\n');
        debugPrintStack(stackTrace: st);
      } finally {
        if (h != null) {
          // `afterAll` only gets called when `beforeAll` is called (i.e. NTRHandle is created).
          await afterAll?.call(h);
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
}
