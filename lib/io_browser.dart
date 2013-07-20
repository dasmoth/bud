library io_browser;

import 'dart:typed_data';
import 'dart:async';
import 'dart:html';

import 'package:bud/io.dart';

class UrlResource extends Resource {
  String uri;
  int _size = null;
  
  UrlResource(this.uri);
  
  Future<ByteBuffer> fetch([int start, int end]) {
    Map<String,String> headers = {};
    if (start != null && end != null) {
      if (start == null) start = 0;
      
      if (end == null) {
        headers['Range'] = 'bytes=$start-';
      } else {
        headers['Range'] = 'bytes=$start-$end';
      }
    }
    
    return HttpRequest.request(uri, requestHeaders: headers, responseType: 'arraybuffer')
        .then((HttpRequest req) => req.response);
  }
}