library tabixtest;

import 'package:bud/tabix.dart';
import 'package:bud/io.dart';
import 'package:bud/io_host.dart';

import 'dart:io';



void main() {
  Resource idx = new FileResource(new File('data/example.gtf.gz.tbi'));
  Resource tgt = new FileResource(new File('data/example.gtf.gz'));
  
  TabixIndexedFile.open(idx, tgt).then(
      (TabixIndexedFile tif) {
        return tif.fetch('chr1', 10000, 50000);
      })
      .then((lines) {
        for (String l in lines)
          print(l);
      });
}