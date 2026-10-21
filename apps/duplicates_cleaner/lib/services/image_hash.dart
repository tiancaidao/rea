/// `SkiaImageMathOperations.GetHammingDistance`: number of differing bits
/// between two 64-bit perceptual hashes.
int hammingDistance(int a, int b) {
  var x = a ^ b;
  var count = 0;
  while (x != 0) {
    x &= x - 1;
    count++;
  }
  return count;
}
