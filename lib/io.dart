library io;

import 'dart:async';
import 'dart:typed_data';

abstract class Resource {
  Future<ByteBuffer> fetch([int start, int end]);
  void close() {}
}

class ByteStream {
  final ByteData data;
  final Endianness endian;
  int pointer;
  
  ByteStream(ByteBuffer d, {this.pointer: 0, this.endian: Endianness.LITTLE_ENDIAN}) :
    data = new ByteData.view(d);
  
  int _incr(n) {
    int p = pointer;
    pointer += n;
    return p;
  }
  
  int getInt8()   => data.getInt8(_incr(1));
  int getUint8()  => data.getUint8(_incr(1));
  int getInt16()  => data.getInt16(_incr(2), endian);
  int getUint16() => data.getUint16(_incr(2), endian);
  int getInt32()  => data.getInt32(_incr(4), endian);
  int getUint32() => data.getUint32(_incr(4), endian);
  int getInt64()  => data.getInt64(_incr(8), endian);
  
  // This doesn't work in dart2js :-(
  // int getUint64() => data.getUint64(_incr(8), endian);
  int getUint64() {
    int a = getUint32();
    int b = getUint32();
    
    int x = (b * 0x100000000) + a;
    
    // print('a=${a.toRadixString(16)} b=${b.toRadixString(16)} x=${x.toRadixString(16)}');
    return x;
  }
  
  
  double getFloat32() => data.getFloat32(_incr(4), endian);
  double getFloat64() => data.getFloat64(_incr(8), endian);
  
  void skip(int n) {
    _incr(n);
  }
  
  List<int> getBytes(int n) {
    return new Uint8List.view(data.buffer, _incr(n), n);
  }
}