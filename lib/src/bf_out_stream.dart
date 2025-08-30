import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'types.dart';

/// Abstract class for file system out streams.
abstract class BFOutStream {
  /// Returns the [BFPath] of the stream.
  BFPath getPath();

  /// Returns the file name of the stream.
  String getFileName();

  /// Writes data to the stream.
  Future<void> write(Uint8List data);

  /// Closes the stream.
  Future<void> close();

  /// Flushes the stream.
  Future<void> flush();
}

/// Local file system out stream.
class BFLocalRafOutStream extends BFOutStream {
  final RandomAccessFile _raf;
  final BFPath _path;
  bool _closed = false;

  BFLocalRafOutStream(this._raf, this._path);

  @override
  BFPath getPath() {
    return _path;
  }

  @override
  String getFileName() {
    return p.basename(_path.localPath());
  }

  @override
  Future<void> write(Uint8List data) async {
    await _raf.writeFrom(data);
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    await _raf.close();
    _closed = true;
  }

  @override
  Future<void> flush() async {
    await _raf.flush();
  }
}

/// In-memory out stream.
class BFMemoryOutStream extends BFOutStream {
  // ignore: deprecated_export_use
  final _bb = BytesBuilder(copy: false);

  @override
  BFPath getPath() {
    throw Exception('`getPath` is not supported in `MemoryBFOutStream`');
  }

  @override
  String getFileName() {
    throw Exception('`getFileName` is not supported in `MemoryBFOutStream`');
  }

  @override
  Future<void> write(Uint8List data) async {
    _bb.add(data);
  }

  @override
  Future<void> close() async {}

  @override
  Future<void> flush() async {}

  Uint8List toBytes() {
    return _bb.toBytes();
  }
}
