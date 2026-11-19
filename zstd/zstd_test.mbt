///|
/// libzstd 1.5's frame (level 19) of `zstd_text`: Huffman literals and sequences.
let zstd_packed : Bytes = b"\x28\xb5\x2f\xfd\x60\x26\x00\x3d\x03\x00\x42\x05\x14\x18\x60\xcd\x03\x2f\x29\xed\x20\x43\xab\xe8\xd0\xfa\x28\x8a\x79\x3a\x42\x86\xf1\x59\xd8\x20\x58\x3c\xc0\x24\x45\xd0\xb3\x1d\x9d\x1b\xfc\xd7\x56\x3a\x65\x84\xcf\x35\xb6\xd4\xa2\x24\xc8\x61\x14\xc4\x20\x78\xa0\xb1\xba\xce\xc0\x6f\x2e\x4d\xaa\x7a\x76\xcf\xbb\xc6\x76\x4f\x8f\xfe\xf9\x85\x3e\x2f\xa7\x4c\xee\xc6\x5d\x74\x02\x06\x00\x5a\x50\x40\x23\x06\x84\xe2\x78\x0b\x25\x50\x05\x2a\x42\x0b\x56\x39\x01"

///|
let zstd_text : String = "the quick brown fox jumps over the lazy dog; the quick brown fox naps. the quick brown fox jumps over the lazy dog; the quick brown fox naps. the quick brown fox jumps over the lazy dog; the quick brown fox naps. 0123456789abcdefghijklmnopqrstuvwxyz the lazy dog jumps over the quick brown fox!"

///|
test "decompress inflates a compressed block of Huffman literals and sequences" {
  let want = @utf8.encode(zstd_text)
  assert_eq(@zstd.decompress(zstd_packed[:]), Some(want))
  assert_eq(@zstd.decompress(zstd_packed[:], limit=want.length()), Some(want))
  assert_true(@zstd.decompress(zstd_packed[:], limit=want.length() - 1) is None)
}

///|
test "decompress takes raw and RLE blocks, sequences that repeat, checksums and several frames" {
  assert_eq(
    @zstd.decompress(b"\x28\xb5\x2f\xfd\x20\x02\x11\x00\x00\x61\x62"),
    Some(b"ab"),
  )
  let run = @zstd.decompress(
    b"\x28\xb5\x2f\xfd\x60\x2c\x00\x4d\x00\x00\x10\x7a\x7a\x01\x00\x27\x2a\xc0\x02",
  ).unwrap()
  assert_eq(run.length(), 300)
  assert_true(run.iter().all(b => b == b'z'))
  let summed : Bytes = b"\x28\xb5\x2f\xfd\x24\x17\x65\x00\x00\x30\x68\x65\x6c\x6c\x6f\x20\x01\x00\x99\x4b\x11\x17\x5e\xae\x0d"
  assert_eq(@zstd.decompress(summed[:]), Some(b"hello hello hello hello"))
  // Two frames, a skippable one between them.
  let skippable : Bytes = b"\x50\x2a\x4d\x18\x02\x00\x00\x00\x09\x09"
  let joined = Bytes::from_array(
    summed.to_array() + skippable.to_array() + summed.to_array(),
  )
  assert_eq(
    @zstd.decompress(joined[:]),
    Some(b"hello hello hello hellohello hello hello hello"),
  )
  assert_eq(@zstd.decompress(b""), Some(b""))
}

///|
test "decompress refuses another magic, a dictionary, and frames that are cut or changed" {
  assert_true(@zstd.decompress(b"\x01\x02\x03\x04\x05\x06\x07\x08") is None)
  assert_true(@zstd.decompress(b"\x28\xb5\x2f") is None)
  // A frame that names dictionary 7.
  assert_true(
    @zstd.decompress(b"\x28\xb5\x2f\xfd\x21\x07\x00\x01\x00\x00") is None,
  )
  // A reserved block type.
  assert_true(@zstd.decompress(b"\x28\xb5\x2f\xfd\x20\x00\x07\x00\x00") is None)
  for cut in 1..<zstd_packed.length() {
    assert_true(@zstd.decompress(zstd_packed[:cut]) is None)
  }
  // Any byte changed: refused or inflated to something, within the limit.
  let bytes = zstd_packed.to_array()
  for i in 0..<bytes.length() {
    for flip in [1, 0x80, 0xff] {
      let damaged = bytes.copy()
      damaged[i] = (damaged[i].to_int() ^ flip).to_byte()
      match @zstd.decompress(Bytes::from_array(damaged)[:], limit=4096) {
        Some(out) => assert_true(out.length() <= 4096)
        None => ()
      }
    }
  }
}
