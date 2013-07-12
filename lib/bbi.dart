library bbi;

import 'dart:async';
import 'dart:typed_data';

import 'package:zlib/zlib.dart';

import 'package:bud/io.dart';

/**
 * Open a BBI file.
 */

Future<BBIFile> openBBI(Resource r) {
    return r.fetch(0, 512)
       .then((hdr) => new _BBIFile(r, hdr)._init());
}

/**
 * View on a BBI file.
 * 
 * Create one of these using openBBI.
 */

abstract class BBIFile {
  int get type;
  Future<List<Feature>> features(String chr, [int min, int max]);
}

/**
 * Feature in a BBI file.
 */

class Feature {
  final String seqName;
  final int min;
  final int max;
  final num score;
  
  Feature._(this.seqName, this.min, this.max, this.score);
  
  String toString() => '$seqName:$min..$max';
}

class _ByteStream {
  final ByteData data;
  final Endianness endian;
  int pointer;
  
  _ByteStream(ByteBuffer d, {this.pointer: 0, this.endian: Endianness.LITTLE_ENDIAN}) :
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
  int getUint64() => data.getUint64(_incr(8), endian);
  double getFloat32() => data.getFloat32(_incr(4), endian);
  double getFloat64() => data.getFloat64(_incr(8), endian);
  
  void skip(int n) {
    _incr(n);
  }
  
  List<int> getBytes(int n) {
    return new Uint8List.view(data.buffer, _incr(n), n);
  }
}

class _ChromInfo {
  final int id;
  final int length;
  
  _ChromInfo(int this.id, int this.length);
}

class _BBIFile implements BBIFile {
  static const int BIG_WIG_SIG = 0x888FFC26;
  static const int BIG_BED_SIG = 0x8789F2EB;
  static const int BIG_WIG_TYPE_GRAPH = 1;
  static const int BIG_WIG_TYPE_VSTEP = 2;
  static const int BIG_WIG_TYPE_FSTEP = 3;
  
  Resource r;
  int type;
  Endianness end;
  
  int chromTreeOffset;
  int unzoomedDataOffset;
  int unzoomedIndexOffset;
  int fieldCount;
  int definedFieldCount;
  int totalSummaryOffset;
  int uncompressBufSize;
  
  Map<String,_ChromInfo> chromosomes = {};
  Map<int,String> chrNames = {};
  
  _BBIFile(Resource this.r, ByteBuffer hdr) {
    var h = new ByteData.view(hdr);
    int mb = h.getUint32(0, Endianness.BIG_ENDIAN);
    int ml = h.getUint32(0, Endianness.LITTLE_ENDIAN);
    
    if (mb == BIG_WIG_SIG) {
      end = Endianness.BIG_ENDIAN;
      type = 1;
    } else if (mb == BIG_BED_SIG) {
      end = Endianness.BIG_ENDIAN;
      type = 2;
    } else if (ml == BIG_WIG_SIG) {
      end = Endianness.LITTLE_ENDIAN;
      type = 1;
    } else if (ml == BIG_BED_SIG) {
      end = Endianness.LITTLE_ENDIAN;
      type = 2;
    } else {
      throw 'Not a BBI file';
    }
    
    int version = h.getUint16(4, end);
    int numZoomLevels = h.getUint16(6, end);
    chromTreeOffset = h.getUint64(8, end);
    unzoomedDataOffset = h.getUint64(16, end);
    unzoomedIndexOffset = h.getUint64(24, end);
    fieldCount = h.getUint16(32, end);
    definedFieldCount = h.getUint16(34, end);
    totalSummaryOffset = h.getUint64(4, end);
    uncompressBufSize = h.getUint32(52, end);
  }
  
  Future<BBIFile> _init() {
    return r.fetch(chromTreeOffset, ((unzoomedDataOffset + 3) & ~3))
        .then((ByteBuffer chromTree) {
          _ByteStream cts = new _ByteStream(chromTree, endian: end);
          int magic = cts.getUint32();
          int blockSize = cts.getUint32();
          int keySize = cts.getUint32();
          int valSize = cts.getUint32();
          int itemCount = cts.getUint64();
          
          void readNode(int ptr) {
            _ByteStream nts = new _ByteStream(chromTree, pointer: ptr, endian: end);
            int nodeType = nts.getUint8();
            nts.getUint8();
            int cnt = nts.getUint16();
            
            for (int n = 0; n < cnt; ++n) {
              if (nodeType == 0) {
                nts.skip(keySize);
                readNode(nts.getUint64() - chromTreeOffset);
              } else {
                String key = new String.fromCharCodes(nts.getBytes(keySize).where((c) => c != 0));
                int chromId = nts.getInt32();
                int chromLength = nts.getInt32();
                
                chromosomes[key] = new _ChromInfo(chromId, chromLength);
                chrNames[chromId] = key;
              }
            }
          }
          readNode(32);
          
          return this;
        });
  }
  
  Future<List<Feature>> features(String chr, [int min, int max]) {
    _ChromInfo info = chromosomes[chr];
    if (info == null) {
      info = chromosomes['chr$chr'];
    }
    if (info == null) {
      return new Future.error("Couldn't find sequence named $chr");
    }
    
    if (min == null) min = 1;
    if (max == null) max = info.length;
    
    return r.fetch(unzoomedIndexOffset, unzoomedIndexOffset + 48)
      .then((ByteBuffer ch) {
        ByteData cirHeader = new ByteData.view(ch);
        int cirBlockSize = cirHeader.getInt32(4, end);
        int maxCirBlockSpan = 4 + cirBlockSize * 32;
        
        StreamController cirBlocksSC = new StreamController();
        StreamController featureBlocksSC = new StreamController();
        Completer featureCompleter = new Completer();
        List<Feature> features = [];
        
        cirBlocksSC.add(unzoomedIndexOffset + 48);
        int outstandingBlocks = 1;
        
        cirBlocksSC.stream.listen((int offset) {
          r.fetch(offset, offset + maxCirBlockSpan)
            ..then((ByteBuffer block) {
              _ByteStream b = new _ByteStream(block, endian: end);
              bool isLeaf = b.getUint8() != 0;
              b.skip(1);
              int cnt = b.getUint16();
              
              if (isLeaf) {
                for (int i = 0; i < cnt; ++i) {
                  int startChrom = b.getUint32();
                  int startBase = b.getUint32();
                  int endChrom = b.getUint32();
                  int endBase = b.getUint32();
                  int blockOffset = b.getUint64();
                  int blockSize = b.getUint64();
                  
                  if ((startChrom < info.id || (startChrom == info.id && startBase <= max)) &&
                      (endChrom   > info.id || (endChrom   == info.id && endBase >= min)))
                  {
                    featureBlocksSC.add(new _FeatureBlock(blockOffset, blockSize));
                  }
                }
              } else {
                for (int i = 0; i < cnt; ++i) {
                  int startChrom = b.getUint32();
                  int startBase = b.getUint32();
                  int endChrom = b.getUint32();
                  int endBase = b.getUint32();
                  int blockOffset = b.getUint64();
                  
                  if ((startChrom < info.id || (startChrom == info.id && startBase <= max)) &&
                      (endChrom   > info.id || (endChrom   == info.id && endBase >= min)))
                  {
                    outstandingBlocks++;
                    cirBlocksSC.add(blockOffset);
                  }
                }
              }
              
              outstandingBlocks--;
              if (outstandingBlocks == 0) {
                cirBlocksSC.close();
              }
            })
            ..catchError((err) {
              featureCompleter.completeError(err);
            });
          
        },
        onDone: () {
          featureBlocksSC.close();
        },
        onError: (err) {
          featureBlocksSC.addError(err);
        });
        
        int outstandingFBs = 0;
        featureBlocksSC.stream.listen((b) {
          ++outstandingFBs;
          r.fetch(b.start, b.start + b.length)
            .then((ByteBuffer fb) {
              if (uncompressBufSize > 0) {
                // List<int> bytes = new Uint8List.view(fb.buffer, 2);   // Skip default ZLib header
                List<int> bytes = new Inflater().inflate(new Uint8List.view(fb, 2));
                fb = new Uint8List.fromList(bytes).buffer;
              }
              
              for (Feature f in parseFeatures(fb)) {
                if (f.min <= max && f.max >= min) {
                  features.add(f);
                }
              }
              
              --outstandingFBs;
              if (outstandingFBs == 0) {
                featureCompleter.complete(features);
              }
            },
            onError: (err) {
              featureCompleter.completeError(err);
            });
        },
        onDone: () {
          if (outstandingFBs == 0) 
            featureCompleter.complete(features);
        },
        onError: (err) {
          featureCompleter.completeError(err);
        });
        
        return featureCompleter.future;
      });
  }
  
  List<Feature> parseFeatures(ByteBuffer d) {
    _ByteStream fs = new _ByteStream(d, endian: end);
    List<Feature> features = [];
    
    int chromId = fs.getUint32();
    int blockStart = fs.getUint32();
    int blockEnd = fs.getUint32();
    int itemStep = fs.getUint32();
    int itemSpan = fs.getUint32();
    int blockType = fs.getUint8();
    fs.skip(1);
    int itemCount = fs.getUint16();
    
    String chr = chrNames[chromId];
    
    if (blockType == BIG_WIG_TYPE_FSTEP) {
      for (int i = 0; i < itemCount; ++i) {
        features.add(new Feature._(chr, blockStart + (i*itemStep) + 1, blockStart + (i*itemStep) + itemSpan, fs.getInt32()));
      }
    } else if (blockType == BIG_WIG_TYPE_VSTEP) {
      for (int i = 0; i < itemCount; ++i) {
        int start = fs.getUint32();
        int score = fs.getInt32();
        features.add(new Feature._(chr, start + 1, start + itemSpan, score));
      }
    } else if (blockType == BIG_WIG_TYPE_GRAPH) {
      for (int i = 0; i < itemCount; ++i) {
        int start = fs.getUint32();
        int end = fs.getUint32();
        int score = fs.getInt32();
        features.add(new Feature._(chr, start + 1, end, score));
      }
    } else {
      throw 'Not handling bigwig blocktype $blockType';
    }
    
    return features;
  }
}  

class _FeatureBlock {
  final int start, length;
  _FeatureBlock(this.start, this.length);
}