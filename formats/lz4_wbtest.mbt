///|
test "lz4_frame inflates a frame of literals and an overlapping match" {
  // lz4js 0.2.0's frame of 40 bytes counting 0 to 4 over and over.
  let frame : Bytes = b"\x04\x22\x4d\x18\x40\x70\xdf\x0f\x00\x00\x00\x5f\x00\x01\x02\x03\x04\x05\x00\x0b\x50\x00\x01\x02\x03\x04\x00\x00\x00\x00"
  let want = Bytes::makei(40, i => (i % 5).to_byte())
  assert_eq(lz4_frame(frame[:], 40), Some(want))
  assert_eq(lz4_frame(frame[:], 4000), Some(want))
  assert_true(lz4_frame(frame[:], 39) is None)
}

///|
test "lz4_frame takes stored blocks and an empty frame" {
  let stored : Bytes = b"\x04\x22\x4d\x18\x40\x70\xdf\x03\x00\x00\x80\x01\x02\x03\x00\x00\x00\x00"
  assert_eq(lz4_frame(stored[:], 3), Some(b"\x01\x02\x03"))
  assert_true(lz4_frame(stored[:], 2) is None)
  let empty : Bytes = b"\x04\x22\x4d\x18\x40\x70\xdf\x00\x00\x00\x00"
  assert_eq(lz4_frame(empty[:], 0), Some(b""))
}

///|
test "lz4_frame refuses what is cut, another magic, and matches before the output" {
  let frame : Bytes = b"\x04\x22\x4d\x18\x40\x70\xdf\x0f\x00\x00\x00\x5f\x00\x01\x02\x03\x04\x05\x00\x0b\x50\x00\x01\x02\x03\x04\x00\x00\x00\x00"
  for cut in 0..<frame.length() {
    assert_true(lz4_frame(frame[:cut], 40) is None)
  }
  assert_true(
    lz4_frame(b"\x05\x22\x4d\x18\x40\x70\xdf\x00\x00\x00\x00", 0) is None,
  )
  // An offset of 6 with only 5 bytes written.
  let far : Bytes = b"\x04\x22\x4d\x18\x40\x70\xdf\x0f\x00\x00\x00\x5f\x00\x01\x02\x03\x04\x06\x00\x0b\x50\x00\x01\x02\x03\x04\x00\x00\x00\x00"
  assert_true(lz4_frame(far[:], 40) is None)
  // An offset of 0.
  let zero : Bytes = b"\x04\x22\x4d\x18\x40\x70\xdf\x0f\x00\x00\x00\x5f\x00\x01\x02\x03\x04\x00\x00\x0b\x50\x00\x01\x02\x03\x04\x00\x00\x00\x00"
  assert_true(lz4_frame(zero[:], 40) is None)
}
