library tabixtest3;

import 'package:bud/tabix.dart';
import 'package:bud/io.dart';
import 'package:bud/io_host.dart';
import 'package:bud/gff.dart';

import 'dart:io';


void main() {
  Resource idx = new FileResource(new File('data/c_elegans.sort.gff3.gz.tbi'));
  Resource tgt = new FileResource(new File('data/c_elegans.sort.gff3.gz'));
  
  TabixIndexedFile.open(idx, tgt).then(
      (TabixIndexedFile tif) {
        return tif.fetch('CHROMOSOME_II', 3000000, 3001000);
      })
      .then((lines) {
        for (String l in lines) {
          print(l);
          print(GFFRecord.parse(l));
        }
      });
}