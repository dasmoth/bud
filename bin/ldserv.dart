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
  
  HttpServer.bind('127.0.0.1', port).then((HttpServer server) {
    server.listen((HttpRequest req) {
      req.response.done.catchError((e) => print('$e'));
      
      var res = req.response;
      res.headers.set('Access-Control-Allow-Origin', '*');
      
      var qp = req.uri.queryParameters;
      String chrName = qp['chr'];
      String minStr = qp['min'];
      String maxStr = qp['max'];
      String refSnp = qp['ref'];
      
      print(new Map.from(qp));
      
      if (chrName != null && minStr != null && maxStr != null) {
        int min = int.parse(minStr), max = int.parse(maxStr);

        Process.start('/Users/thomas/Software/tabix/tabix',
                      [fileName, '$chrName:$min-$max'])
          .then((Process proc) {
            List<Map> records = [];
            List<List<String>> genotypes = [];
            List<String> ref;
            
            proc.stdout
              .transform(new AsciiDecoder())
              .transform(new LineSplitter())
              .listen((String line) {
                VCFRecord r = VCFRecord.parse(line);
                records.add({'min': r.pos,
                  'max': r.pos,
                  'id': r.id,
                  'score': 0});
                List<String> genotype = new List.from(r.genotypes.map((s) => s.substring(2, 3)));
                genotypes.add(genotype);
                if (r.id == refSnp)
                  ref = genotype;
              }, onDone: () {
                if (ref != null){
                  for (int i = 0; i < records.length; ++i) {
                    double r = ld(genotypes[i], ref);
                    if (!r.isNaN)
                      records[i]['score'] = r.abs();
                  }
                }
                
                res.write(JSON.encode(records));
                res.close();
              });
            
          });
      } else {
        res.write('Bad request');
        res.close();
      }
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