library tabix;

import 'dart:async';
import 'dart:typed_data';
import 'dart:math';

import 'package:bud/io.dart';
import 'package:zlib/zlib.dart';

int _TABIX_MAGIC = 0x01494254;

abstract class TabixIndexedFile {
  static Future<TabixIndexedFile> open(Resource index, Resource target) {
    return index.fetch().then((idx) => new _TIF(idx, target));
  }
  
  Future<List<String>> fetch(String chr, int min, int max);
}

class _Chunk {
  final int start;
  final int end;
  
  _Chunk(this.start, this.end);
  
  int compareTo(o) => start - o.start;
  String toString() => '[${start.toRadixString(16)}..${end.toRadixString(16)} (${end-start + 1})]';
  
}

class _TabixIdx {
  Map<int,List<_Chunk>> bindex;
  List<int> lindex;
  
  _TabixIdx(this.bindex, this.lindex);
}

List<int> doInflate(Inflater inf) {
  var buffer = new List<int>();

  inf.slide = new List(2 * Inflater.WSIZE);

  // Start the inflation.
  var i = 1;
  while (i > 0 && inf.currentPosition < inf.inflateData.length) {
    i = inf.inflateInternalEntry(buffer, buffer.length, 1024);
  }

  return buffer;
}

ByteBuffer _unbgzf(ByteBuffer bb, [int maxChunkIndex]) {
  if (maxChunkIndex == null)
    maxChunkIndex = bb.lengthInBytes - 50;
  
  List<List<int>> blocks = <List<int>>[];
  int tot = 0;
  List<int> bbAsArray = new Int8List.view(bb);
  
  ByteStream bs = new ByteStream(bb, endian: Endianness.LITTLE_ENDIAN);
  while (bs.pointer <= maxChunkIndex) {
    bs.skip(10);
    int xlen = bs.getUint16();
    bs.skip(xlen);
    
    Inflater inf = new Inflater();
    inf.inflateData = bbAsArray;
    inf.currentPosition = bs.pointer;
    
    var ib = doInflate(inf);
    tot += ib.length;
    blocks.add(ib);
    
    bs.pointer = inf.currentPosition + 8; // Skip len and checksum.
    
    // print('pointer=${bs.pointer}, limit=${bb.lengthInBytes}');
  }
  
  Uint8List merged = new Uint8List(tot);
  int ptr = 0;
  for (var block in blocks) {
    merged.setAll(ptr, block);
    // for (int bi = 0; bi < block.length; ++bi) {
    //   var bib = block[bi];
    //   if (bib != null)
    //     merged[ptr + bi] = bib;
    // }
    ptr += block.length;
  }
  
  return merged.buffer;
}

class _TIF implements TabixIndexedFile {
  final Resource target;
  final Map<String,_TabixIdx> indices = {};
  
  int format, colSeq, colStart, colEnd, meta, skip;
  
  _TIF(ByteBuffer zidx, Resource this.target) {
    ByteBuffer idx = _unbgzf(zidx);
    
    ByteStream ibs = new ByteStream(idx, endian: Endianness.LITTLE_ENDIAN);
    int magic = ibs.getUint32();
    if (magic != _TABIX_MAGIC)
        throw 'Not a TABIX index';
    
    int nseq = ibs.getUint32();
    format = ibs.getUint32();
    colSeq = ibs.getUint32();
    colStart = ibs.getUint32();
    colEnd = ibs.getUint32();
    meta = ibs.getUint32();
    skip = ibs.getUint32();
    int nameLength = ibs.getUint32();
    
    List<String> seqNames = <String>[];
    for (int i = 0; i < nseq; ++i) {
      List<int> cc = <int>[];
      for (;;) {
        int c = ibs.getUint8();
        if (c == 0) break;
        cc.add(c);
      }
      seqNames.add(new String.fromCharCodes(cc));
    }
    
    for (int i = 0; i < nseq; ++i) {
      int nBin = ibs.getUint32();
      var bi = new Map<int,List<_Chunk>>();
      for (int b = 0; b < nBin; ++b) {
        int bin = ibs.getUint32();
        int nChnk = ibs.getUint32();

        var cl = <_Chunk>[];
        for (int c = 0; c < nChnk; ++c) {
          int start = ibs.getUint64();
          int end = ibs.getUint64();
          cl.add(new _Chunk(start, end));
        }
        bi[bin] = cl;
      }
      
      var li = <int>[];
      int nintv = ibs.getUint32();
      for (int l = 0; l < nintv; ++l) {
        li.add(ibs.getUint64());
      }
      
      indices[seqNames[i]] = new _TabixIdx(bi, li);
    }
    
  }
  
  Future<List<String>> fetch(String chr, int minp, int maxp) {
    _TabixIdx idx = indices[chr];
    if (idx == null)
      throw 'No index for reference sequence $chr';
    
    int minLinBin = minp ~/ 16384;
    int maxLinBin = min(idx.lindex.length - 1, maxp ~/ 16384);
    int minChunk = 0;
    for (int linbin = minLinBin; linbin <= maxLinBin; ++linbin) 
      minChunk = min(minChunk, idx.lindex[linbin]);
    
    List<int> bins = _reg2bins(minp, maxp);
    // print('Bins: $bins');
    
    List<_Chunk> chunks = <_Chunk>[];
    for (int b in bins) {
      var bc = idx.bindex[b];
      if (bc != null) {
        for (_Chunk c in bc) {
          if (c.start >= minChunk)
            chunks.add(c);
        }
      }
    }
    chunks.sort();
    
    // print('Chunks: $chunks');
    
    List<_Chunk> mchunks = <_Chunk>[];
    _Chunk last = null;
    for (_Chunk c in chunks) {
      if (last == null) {
        last = c;
      } else if (c.start <= last.end) {
        last = new _Chunk(last.start, max(c.end, last.end));
      } else {
        mchunks.add(last);
        last = c;
      }
    }
    if (last != null) mchunks.add(last);
    
    // print('Mchunks: $mchunks');
    
    List<String> lines = <String>[];
    Future<List<String>> fetch(int ci) {
      if (ci >= mchunks.length) {
        return new Future.value(lines);
      }
      _Chunk c = mchunks[ci];
      
      // The divisions here are horrific, but seem to be the simplest
      // thing that generates working code with dart2js.  Switch back
      // to using shifts if we ever stop supporting Javascript.
      
      int fmin = c.start ~/ 0x10000;
      int fmax = (c.end ~/ 0x10000);
      int offsetOfLastChunkStart = fmax - fmin;
      
      int lii;
      for (lii = maxLinBin; lii < idx.lindex.length; ++lii) {
        if ((idx.lindex[lii] ~/ 0x10000) > fmax)
          break;
      }
      
      if (lii >= idx.lindex.length) {
        fmax = fmin + 0x10000;   // Fixme can we set a smarter bound?
      } else {
        fmax = idx.lindex[lii] ~/ 0x10000;
      }
      
      return target.fetch(fmin, fmax)
          .then((ByteBuffer b) {
            String unc = new String.fromCharCodes(new Uint8List.view(_unbgzf(b, offsetOfLastChunkStart), c.start & 0xffff));
            
            for (String l in unc.split('\n')) {
              List<String> toks = l.split('\t');
              if (toks[colSeq - 1] == chr && toks.length > colEnd) {
                int fmin = int.parse(toks[colStart - 1]);
                int fmax = int.parse(toks[colEnd - 1]);
                if ((format&0x10000) != 0) ++fmin;
                if (fmin <= maxp && fmax >= minp)
                  lines.add(l);
              }
            }
            return fetch(ci + 1);
          });
    }
    
    return fetch(0);
  }
}

int _reg2bin(int beg, int end)
{
    --end;
    if (beg>>14 == end>>14) return ((1<<15)-1) ~/ 7 + (beg>>14);
    if (beg>>17 == end>>17) return ((1<<12)-1) ~/ 7 + (beg>>17);
    if (beg>>20 == end>>20) return ((1<<9)-1)  ~/ 7 + (beg>>20);
    if (beg>>23 == end>>23) return ((1<<6)-1)  ~/ 7 + (beg>>23);
    if (beg>>26 == end>>26) return ((1<<3)-1)  ~/ 7 + (beg>>26);
    return 0;
}

/* calculate the list of bins that may overlap with region [beg,end) (zero-based) */
int _MAX_BIN = (((1<<18)-1) ~/ 7);

List<int> _reg2bins(int beg, int end) 
{
    int i = 0, k;
    List<int> list = <int>[];
    --end;
    list.add(0);
    for (k = 1 + (beg>>26); k <= 1 + (end>>26); ++k) list.add(k);
    for (k = 9 + (beg>>23); k <= 9 + (end>>23); ++k) list.add(k);
    for (k = 73 + (beg>>20); k <= 73 + (end>>20); ++k) list.add(k);
    for (k = 585 + (beg>>17); k <= 585 + (end>>17); ++k) list.add(k);
    for (k = 4681 + (beg>>14); k <= 4681 + (end>>14); ++k) list.add(k);
    return list;
}