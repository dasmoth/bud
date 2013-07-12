library intset;

abstract class IntSet {
  factory IntSet(int min, int max) {
    return new _Range(min, max);
  }
  
  int get min;
  int get max;
  bool get isContiguous;
  Iterable<IntSet> get spans;
}

class _Range implements IntSet {
  final int min;
  final int max;
  
  _Range(this.min, this.max);
  
  bool get isContiguous => true;
  
  Iterable<IntSet> get spans => [this];
}

class _Composite implements IntSet {
  final List<IntSet> spans;
  
  _Composite(this.spans);
  
  int get min => spans.first.min;
  int get max => spans.last.max;
  bool get isContiguous => false;   // Relies on the factories only
                                    // making one of these if a _Range
                                    // won't work.
}