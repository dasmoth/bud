library gff;

abstract class Strand {
  int get ori;
  String get token;
  
  static const Strand POSITIVE = const _Strand(1, '+');
  static const Strand NEGATIVE = const _Strand(-1, '-');
  static const Strand UNKNOWN  = const _Strand(0, '?'); 
  
}

class _Strand implements Strand {
  final int ori;
  final String token;
  
  const _Strand(this.ori, this.token);
  
  String toString() => token;
}

class GFFRecord {
  String seqName;
  String source;
  String type;
  int start;
  int end;
  num score;
  Strand strand;
  int phase;
  
  Map<String,String> attributes = {};
  
  static GFFRecord parse(String line, [int format=3]) {
    List<String> toks = line.split('\t');
    if (toks.length <8 || toks.length >9)
      throw 'Incorrect number of tokens: ${toks.length}';
      
    GFFRecord record = new GFFRecord();
    record.seqName = toks[0];
    record.source = toks[1];
    record.type = toks[2];
    record.start = int.parse(toks[3]);
    record.end = int.parse(toks[4]);
    
    String scoreStr = toks[5];
    if (scoreStr == '.')
      record.score = null;
    else if (_INT_REGEXP.hasMatch(scoreStr))
      record.score = int.parse(scoreStr);
    else
      record.score = double.parse(scoreStr);
    
    String strandStr = toks[6];
    if (strandStr == '.') 
      record.strand = null;
    else if (strandStr == '+')
      record.strand = Strand.POSITIVE;
    else if (strandStr == '-')
      record.strand = Strand.NEGATIVE;
    else if (strandStr == '?')
      record.strand = Strand.UNKNOWN;
    else
      throw 'Bad strand $strandStr';
    
    String phaseStr = toks[7];
    if (phaseStr == '.') {
      record.phase = null;
    } else {
      int p = int.parse(phaseStr);
      if (p < 0 || p > 2)
        throw 'Invalid phase $p';
      record.phase = p;
    }
    
    if (toks.length > 8) {
      if (format == 2) 
        record.attributes = _splitQueryStringGFF2(toks[8]);
      else
        record.attributes = _splitQueryStringGFF3(toks[8]);
    }
    
    return record;
  }
  
  static Map<String, String> _splitQueryStringGFF3(
      String query) {
    return query.split(";").fold({}, (map, element) {
      int index = element.indexOf("=");
      if (index == -1) {
        if (element != "") map[Uri.decodeQueryComponent(element)] = "";
      } else if (index != 0) {
        var key = element.substring(0, index);
        var value = element.substring(index + 1);
        map[Uri.decodeQueryComponent(key)] =
            Uri.decodeQueryComponent(value);
      }
      return map;
    });
  }
  
  static Map<String, String> _splitQueryStringGFF2(String query) {
    return query.split(";").fold({}, (map, element) {
      element = element.trim();
      int index = element.indexOf(" ");
      if (index == -1) {
        if (element != "") map[element] = "";
      } else if (index != 0) {
        var key = element.substring(0, index);
        var value = element.substring(index 
            + 1);
        map[key] = value.replaceAll('"', '');
      }
      return map;
    });
  }

  
  String toString() {
    List l = [
      seqName, 
      source, 
      type, 
      start, 
      end, 
      score != null ? score : '.', 
      strand != null ? strand : '.', 
      phase != null ? phase : '.'];
    if (attributes != null && !attributes.isEmpty) {
      var result = new StringBuffer();
      var first = true;
      attributes.forEach((key, value) {
        if (!first) {
          result.write(";");
        }
        first = false;
        result.write(Uri.encodeQueryComponent(key));
        if (value != null && !value.isEmpty) {
          result.write("=");
          result.write(Uri.encodeQueryComponent(value));
        }
      });
      l.add(result.toString());
    
    }
    
    return l.join('\t');
  }
}

RegExp _INT_REGEXP = new RegExp(r'^[0-9]+$');