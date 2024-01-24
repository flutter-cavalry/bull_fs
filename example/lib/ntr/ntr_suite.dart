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
  final String name;
  final List<Future<void> Function()> _cases = [];

  void Function(String s)? onLog;
  Future<dynamic> Function()? beforeAll;
  Future<void> Function(NTRHandle h)? afterAll;

  NTRSuite({required this.name});

  void add(String name, Future<void> Function(NTRHandle h) fn) {
    _cases.add(() async {
      NTRHandle? h;
      try {
        final data = await beforeAll?.call();
        h = NTRHandle(data);
        onLog?.call(name);
        await fn(h);
      } catch (err) {
        debugPrint('❌ $name\n$err\n');
        rethrow;
      } finally {
        if (h != null) {
          // `afterAll` only gets called when `beforeAll` is called (i.e. NTRHandle is created).
          await afterAll?.call(h);
        }
      }
    });
  }

  Future<void> run() async {
    await Future.wait(_cases.map((e) => e.call()));
  }
}
