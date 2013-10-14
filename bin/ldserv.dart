import 'dart:io';
import 'dart:convert';
import 'dart:math';

import 'package:args/args.dart';

import 'package:bud/tabix.dart';
import 'package:bud/vcf.dart';
import 'package:bud/io_host.dart';

void main() {
  ArgParser parser = new ArgParser();
  parser.addOption('port', defaultsTo: "8701");
  parser.addOption('file');
  ArgResults results = parser.parse(new Options().arguments);
  
  int port = int.parse(results['port']);
  String fileName = results['file'];
  if (fileName == null) {
    throw 'Missing required option: file';
  }
  
  TabixIndexedFile.open(new FileResource(new File("$fileName.tbi")),
                        new FileResource(new File(fileName)))
    .then((TabixIndexedFile tif) {
      print('File opened');
      HttpServer.bind('127.0.0.1', port).then((HttpServer server) {
        server.listen((HttpRequest req) {
          req.response.done.catchError((e) => print('$e'));
          
          var res = req.response;
          var qp = req.uri.queryParameters;
          String chrName = qp['chr'];
          String minStr = qp['min'];
          String maxStr = qp['max'];
          
          print(new Map.from(qp));
          
          if (chrName != null && minStr != null && maxStr != null) {
            int min = int.parse(minStr), max = int.parse(maxStr);
            tif.fetch(chrName, min, max).then((List<String> lines) {
              List<Map> records = [];
              List<List<String>> genotypes = [];
              for (VCFRecord r in lines.map(VCFRecord.parse)) {
                records.add({'min': r.pos,
                             'max': r.pos,
                             'name': r.id});
                genotypes.add(new List.from(r.genotypes.map((s) => s.substring(2, 3))));
              }
              
              List<String> ref = genotypes[0];
              for (int i = 0; i < records.length; ++i) {
                records[i]['score'] = ld(genotypes[i], ref);
              }
              res.write(JSON.encode(records));
              res.close();
            });
          } else {
            res.write('Bad request');
            res.close();
          }
        });
      });
    });
}

double ld(List<String> a, List<String> b) {
  int n = a.length;
  int x11 = 0, x12 = 0, x21 = 0, x22 = 0;
  for (int i = 0; i < n; ++i) {
    if (a[i] == '0')
      if (b[i] == '0')
        ++x11;
      else
        ++x12;
    else
      if (b[i] == '0')
        ++x21;
    else
        ++x22;
  }
  
  double p1 = (x11 + x12) / n;
  double p2 = (x21 + x22) / n;
  double q1 = (x11 + x21) / n;
  double q2 = (x12 + x22) / n;
  
  double D = x11/n - (p1*q1);
  double r = D / sqrt(p1*p2*q1*q2);
  
  return r;
}