library io;

import 'dart:async';
import 'dart:typed_data';

abstract class Resource {
  Future<ByteBuffer> fetch([int start, int end]);
  void close() {}
}