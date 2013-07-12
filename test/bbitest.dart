library bbitest;

import 'package:bud/bbi.dart';
import 'package:bud/io_host.dart';

import 'dart:io';



void main() {
  openBBI(new FileResource(new File('data/spermMethylation.bw')))
    .then((b) {
      print(b.type);
      print('Uncompress ${b.uncompressBufSize}');
      
      b.features('chr22', 30000000, 30010000)
        .then(print);
    });
}