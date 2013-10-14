library vcf;

class VCFRecord {
  String seqName;
  int pos;
  String id;
  String ref;
  String alt;
  num quality;
  String filter;
  Map<String,String> info;
  String genotypeKey;
  List<String> genotypes;
  
  static VCFRecord parse(String s) {
    List<String> toks = s.split('\t');
    
    if (toks.length < 7)
      throw 'Not enough columns for VCF';
    
    VCFRecord r = new VCFRecord();
    r.seqName = toks[0];
    r.pos = int.parse(toks[1]);
    r.id = toks[2];
    r.ref = toks[3];
    r.alt = toks[4];
    r.quality = double.parse(toks[5], (s) => double.NAN);
    r.filter = toks[6];
    if (toks.length > 7) 
      r.info = Uri.splitQueryString(toks[7]);
    if (toks.length > 9) {
      r.genotypeKey = toks[8];
      r.genotypes = toks.sublist(9);
    }
    
    return r;
  }
  
  String toString() => 'VCF($seqName:$pos:$ref:$alt)';
}