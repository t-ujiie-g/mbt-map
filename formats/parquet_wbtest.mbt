///|
test "snappy copies literals and matches, overlapping ones too" {
  // "abcabcabcabcX": a literal of 3, a copy of 9 from 3 back, a literal of 1.
  let block : Bytes = b"\x0d\x08abc\x15\x03\x00X"
  assert_eq(snappy(block[:], 100), Some(b"abcabcabcabcX"))
  assert_true(snappy(block[:], 12) is None)
  // A copy with a 2-byte offset, and a literal whose length takes a byte of its own.
  let long : Bytes = Bytes::makei(64, i => (i + 65).to_byte())
  let framed = Bytes::from_array(
    [b'\x44', b'\xf0', b'\x3f'] + long.to_array() + [b'\x0e', b'\x40', b'\x00'],
  )
  let got = snappy(framed[:], 100).unwrap()
  assert_eq(got.length(), 68)
  assert_eq(got[64:], long[0:4])
  // Offsets before the output, a length past the block and a cut block are refused.
  assert_true(snappy(b"\x05\x00a\x15\x09\x00", 100) is None)
  assert_true(snappy(b"\x05\x08abc", 100) is None)
  assert_true(snappy(b"\x0d\x08ab", 100) is None)
  assert_true(snappy(b"", 100) is None)
}

///|
test "rle_hybrid reads runs and bit-packed groups" {
  // A run of 5 fours (3 bits), then 8 bit-packed values 0 to 7 (the format's own example).
  let b : Bytes = b"\x0a\x04\x03\x88\xc6\xfa"
  assert_eq(
    rle_hybrid(b[:], 0, 3, 13),
    Some([4, 4, 4, 4, 4, 0, 1, 2, 3, 4, 5, 6, 7]),
  )
  assert_eq(rle_hybrid(b[:], 0, 3, 7), Some([4, 4, 4, 4, 4, 0, 1]))
  assert_true(rle_hybrid(b[:], 0, 3, 14) is None)
  assert_eq(rle_hybrid(b[:], 0, 3, 0), Some([]))
  // A run of no values, a width past 32 and a cut group.
  assert_true(rle_hybrid(b"\x00\x01", 0, 1, 1) is None)
  assert_true(rle_hybrid(b[:], 0, 33, 1) is None)
  assert_true(rle_hybrid(b"\x03\x88", 0, 3, 8) is None)
  // A width of 0: every value is 0 and takes no byte.
  assert_eq(rle_hybrid(b"\x06", 0, 0, 3), Some([0, 0, 0]))
}

///|
test "delta_packed reads a first value and blocks of deltas" {
  // Blocks of 8 in one miniblock, 5 values from 7: deltas -2, -2, -2, 1 as 2-bit offsets from -2.
  let b : Bytes = b"\x08\x01\x05\x0e\x03\x02\xc0\x00"
  assert_eq(delta_packed(b[:], 0, 10), Some(([7L, 5L, 3L, 1L, 2L], 8)))
  assert_true(delta_packed(b[:], 0, 4) is None)
  assert_true(delta_packed(b[:7], 0, 10) is None)
  // One value needs no block; none at all gives none.
  assert_eq(delta_packed(b"\x80\x01\x04\x01\x09", 0, 10), Some(([-5L], 5)))
  assert_eq(delta_packed(b"\x80\x01\x04\x00\x00", 0, 10), Some(([], 5)))
  // A block size that is no multiple of its miniblocks, and a width past 64 bits.
  assert_true(delta_packed(b"\x07\x02\x05\x0e", 0, 10) is None)
  assert_true(delta_packed(b"\x08\x01\x05\x0e\x03\x41", 0, 10) is None)
}

///|
test "be_number and scaled read decimals" {
  assert_eq(be_number(b"\x00"), 0.0)
  assert_eq(be_number(b"\x30\x39"), 12345.0)
  assert_eq(be_number(b"\xff"), -1.0)
  assert_eq(be_number(b"\xff\xff\xfe\xff"), -257.0)
  assert_eq(be_number(b""), 0.0)
  assert_eq(scaled(12345.0, 2), 123.45)
  assert_eq(scaled(-257.0, 2), -2.57)
  assert_eq(scaled(5.0, -3), 5000.0)
  assert_eq(scaled(7.0, 0), 7.0)
}

///|
test "Thrift reads the compact protocol's integers, lists and nested structs, and skips the rest" {
  // Field 1 an i32 of -3, field 2 a list of two i64, field 5 a struct with a string, field 6 true.
  let b : Bytes = b"\x15\x05\x19\x26\x02\x04\x3c\x18\x02hi\x00\x11\x00"
  let t : Thrift = { b: b[:], pos: 0, bad: false, depth: 0, }
  let seen = []
  let mut first = 0
  t.fields((id, kind) => {
    seen.push((id, kind))
    if id == 1 {
      first = t.i32()
    } else {
      t.skip(kind)
    }
  })
  assert_eq(first, -3)
  assert_eq(seen, [(1, 5), (2, 9), (5, 12), (6, 1)])
  assert_false(t.bad)
  assert_eq(t.pos, b.length())
  // A struct that never ends, and one nested past the limit.
  let open : Thrift = { b: b"\x15\x05", pos: 0, bad: false, depth: 0, }
  open.fields((_, kind) => open.skip(kind))
  assert_true(open.bad)
  let deep : Thrift = {
    b: Bytes::make(100, b'\x1c')[:],
    pos: 0,
    bad: false,
    depth: 0,
  }
  deep.fields((_, kind) => deep.skip(kind))
  assert_true(deep.bad)
}

///|
test "listing GZIP pages charges what they say they inflate to" {
  // A chunk of two GZIP pages of 3 bytes that each claim about 600 MB: the second passes 1 GB.
  let header : Bytes = b"\x15\x00\x15\x80\x8c\x9b\xbc\x04\x15\x06\x2c\x15\x02\x15\x00\x15\x00\x15\x00\x00\x00"
  let page = header.to_array() + [b'\x01', b'\x02', b'\x03']
  let file = Bytes::from_array([b'P', b'A', b'R', b'1'] + page + page)
  let leaf : Leaf = {
    name: "n",
    path: "n",
    physical: 1,
    length: 0,
    optional: false,
    logical: Plain,
    flat: true,
  }
  let wanted = []
  let reader : ParquetReader = {
    segments: [{ offset: 0L, base: 0, bytes: file[:], }],
    inflated: [],
    next_inflated: 0,
    budget: MAX_ARROW_INFLATED,
    wanted: Some(wanted),
  }
  let chunk : Chunk = {
    codec: 2,
    start: 4L,
    size: (page.length() * 2).to_int64(),
    min: b"",
    max: b"",
  }
  assert_true(reader.column(leaf, chunk, 2) is Err(_))
  assert_eq(wanted.length(), 4)
  assert_true(wanted[2] > 536870912)
}

///|
fn leaf_of(physical : Int32, length~ : Int32 = 0) -> Leaf {
  {
    name: "n",
    path: "n",
    physical,
    length,
    optional: true,
    logical: Plain,
    flat: true,
  }
}

///|
test "Thrift skips lists and maps nested past the limit as bad, and booleans in a map by a byte" {
  // Lists of one list, 200 deep.
  let deep : Thrift = {
    b: Bytes::make(200, b'\x19')[:],
    pos: 0,
    bad: false,
    depth: 0,
  }
  deep.skip(T_LIST)
  assert_true(deep.bad)
  // A map of two entries from true to false: its count, its types, then a byte each.
  let map : Thrift = {
    b: b"\x02\x12\x01\x02\x01\x02",
    pos: 0,
    bad: false,
    depth: 0,
  }
  map.skip(T_MAP)
  assert_false(map.bad)
  assert_eq(map.pos, 6)
  assert_eq(map.depth, 0)
}

///|
test "delta_packed passes over the rest of a miniblock without reading it" {
  // Blocks of 2^24 values in one miniblock of width 0: two values, the second from a delta of 3.
  let b : Bytes = b"\x80\x80\x80\x08\x01\x02\x0e\x06\x00"
  assert_eq(delta_packed(b[:], 0, 10), Some(([7L, 10L], 9)))
  // Of width 8, the miniblock's bytes must be there.
  assert_true(
    delta_packed(b"\x80\x80\x80\x08\x01\x02\x0e\x06\x08\x00", 0, 10) is None,
  )
}

///|
test "plain_values takes no count the bytes cannot hold" {
  let huge = 0x7fffffff
  assert_true(plain_values(leaf_of(BOOLEAN), b"\x05", huge) is None)
  assert_true(plain_values(leaf_of(BOOLEAN), b"\x05", 8) is Some(Flags(_)))
  assert_true(plain_values(leaf_of(BYTE_ARRAY), b"", huge) is None)
  assert_true(plain_values(leaf_of(FIXED_LEN_BYTE_ARRAY), b"", huge) is None)
  assert_true(plain_values(leaf_of(INT32), b"\x01\x00\x00\x00", -1) is None)
  assert_true(
    plain_values(leaf_of(FIXED_LEN_BYTE_ARRAY, length=2), b"ab", 1)
    is Some(Blobs([_])),
  )
}

///|
test "a dictionary page of no values keeps the column's kind of values" {
  let leaf = leaf_of(INT32)
  assert_true(
    page_values(leaf, b"", 0, RLE_DICTIONARY, Some(Ints([42L]))) is Ok(Ints([])),
  )
  assert_true(
    page_values(leaf, b"", 0, PLAIN_DICTIONARY, Some(Reals([1.5])))
    is Ok(Reals([])),
  )
}

///|
test "snappy refuses a length its bytes cannot inflate to" {
  // 3 bytes claiming 1000: more than 64 times them.
  assert_true(snappy(b"\xe8\x07\x00", 2000) is None)
  assert_true(snappy(b"\x02\x04hi", 2000) is Some(b"hi"))
}
