library io_host;

import 'dart:typed_data';
import 'dart:async';
import 'dart:io';

import 'package:bud/io.dart';

class UrlResource extends Resource {
  Future<ByteBuffer> fetch([int start, int end]) {
    throw 'FIXME';
  }
}

class FileResource extends Resource {
  RandomAccessFile _raf;
  
  FileResource(File f) : _raf = f.openSync();
  
  Future<ByteBuffer> fetch([int start, int end]) {
    if (end == null)
      end = _raf.lengthSync();
    if (start == null)
      start = 0;
    return _raf.setPosition(start)
        .then((r) => r.read(end - start))
        .then((l) => new Uint8List.fromList(l).buffer);
  }
  
  void close() => _raf.closeSync();
}