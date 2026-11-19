///|
test "bits_at reads bits low first, zeros outside the bytes" {
  let b : Bytes = b"\xa5\x0f"
  assert_eq(bits_at(b[:], 0, 4), 5)
  assert_eq(bits_at(b[:], 4, 8), 0xfa)
  assert_eq(bits_at(b[:], 12, 8), 0)
  assert_eq(bits_at(b[:], -4, 8), 0x50)
  assert_eq(bits_at(b[:], 0, 0), 0)
  assert_eq(msb(1), 0)
  assert_eq(msb(0x7fffffff), 30)
}

///|
test "Fse::build spreads symbols over the states, and refuses counts of another sum" {
  let table = Fse::build([2, 1, 1], 2).unwrap()
  assert_eq(table.symbols.iter().map(b => b.to_int()).collect(), [0, 0, 1, 2])
  assert_eq(table.bits.iter().map(b => b.to_int()).collect(), [1, 1, 2, 2])
  assert_eq(table.next.iter().collect(), [0, 2, 0, 0])
  assert_true(Fse::build([2, 1], 2) is None)
  assert_true(Fse::build([4, 1], 2) is None)
  // A "less than one" probability takes the last state.
  let low = Fse::build([3, -1], 2).unwrap()
  assert_eq(low.symbols[3].to_int(), 1)
  assert_eq(default_ll.symbols.length(), 64)
  assert_eq(default_of.symbols.length(), 32)
  assert_eq(default_ml.symbols.length(), 64)
}

///|
test "Fse::read and Huffman::read refuse descriptions that are cut or say too much" {
  assert_true(Fse::read(b"", 0, 9) is None)
  // An accuracy of 5 + 15 = 20.
  assert_true(Fse::read(b"\xff\xff\xff", 0, 9) is None)
  assert_true(Fse::read(b"\x00", 0, 9) is None)
  assert_true(Huffman::read(b"", 0) is None)
  // Four direct weights of 1: 8 codes' worth is no power of two short of one.
  assert_true(Huffman::read(b"\x83\x11\x10", 0) is Some(_))
  assert_true(Huffman::read(b"\x83\x11", 0) is None)
  // A weight past 11.
  assert_true(Huffman::read(b"\x81\xc0", 0) is None)
  // Weights of 0 only.
  assert_true(Huffman::read(b"\x81\x00", 0) is None)
}

///|
test "baselines add up the codes' ranges" {
  assert_eq(ll_base[15], 15)
  assert_eq(ll_base[16], 16)
  assert_eq(ll_base[25], 64)
  assert_eq(ll_base[35], 65536)
  assert_eq(ml_base[0], 3)
  assert_eq(ml_base[32], 35)
  assert_eq(ml_base[43], 131)
  assert_eq(ml_base[52], 65539)
}
