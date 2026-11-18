// LZ4 frames and blocks, read after their format descriptions (lz4_Frame_format.md and
// lz4_Block_format.md of the LZ4 project); checksums are not verified.

///|
/// The bytes an LZ4 frame starts with (0x184D2204, little-endian).
let lz4_magic : Bytes = b"\x04\x22\x4d\x18"

///|
/// The bytes the LZ4 frame `src` holds, at most `limit`; None if it is malformed or holds more.
fn lz4_frame(src : BytesView, limit : Int32) -> Bytes? {
  let n = src.length()
  guard n >= 7 && src[0:4] == lz4_magic else { return None }
  let flags = src[4].to_int()
  guard flags >> 6 == 1 else { return None }
  // After the descriptor: the content size and dictionary id it may hold, and its checksum.
  let mut pos = 6 +
    (if (flags & 8) != 0 { 8 } else { 0 }) +
    (if (flags & 1) != 0 { 4 } else { 0 }) +
    1
  let block_checksum = if (flags & 0x10) != 0 { 4 } else { 0 }
  let out = Out::new()
  while true {
    guard pos <= n - 4 else { return None }
    let word = le_i32(src, pos)
    pos += 4
    if word == 0 {
      break
    }
    let length = word & 0x7fffffff
    guard length <= n - pos else { return None }
    if word < 0 {
      guard length <= limit - out.len else { return None }
      out.room(length)
      out.bytes.blit_from_bytesview(out.len, src[pos:pos + length])
      out.len += length
    } else {
      guard lz4_block(src[pos:pos + length], out, limit) else { return None }
    }
    pos += length + block_checksum
  }
  Some(Bytes::makei(out.len, i => out.bytes[i]))
}

///|
/// Decodes the LZ4 block `src` onto the end of `out` (matches may reach back into what it
/// held); false if the block is malformed or `out` would pass `limit` bytes.
fn lz4_block(src : BytesView, out : Out, limit : Int32) -> Bool {
  let n = src.length()
  let mut pos = 0
  // A length whose 4 bits are all set goes on in bytes until one below 255.
  let extended = (nibble : Int32) => {
    let mut length = nibble
    if nibble == 15 {
      while pos < n {
        let more = src[pos].to_int()
        pos += 1
        length += more
        guard more == 255 && length < 0x40000000 else { break }
      }
    }
    length
  }
  while pos < n {
    let token = src[pos].to_int()
    pos += 1
    let literals = extended(token >> 4)
    guard literals <= n - pos && literals <= limit - out.len else {
      return false
    }
    out.room(literals)
    out.bytes.blit_from_bytesview(out.len, src[pos:pos + literals])
    pos += literals
    out.len += literals
    if pos == n {
      break
    }
    guard pos <= n - 2 else { return false }
    let offset = src[pos].to_int() | (src[pos + 1].to_int() << 8)
    pos += 2
    let length = extended(token & 15) + 4
    guard offset > 0 && offset <= out.len && length <= limit - out.len else {
      return false
    }
    out.room(length)
    // Byte by byte: a match may overlap what it writes.
    for k in 0..<length {
      out.bytes[out.len + k] = out.bytes[out.len - offset + k]
    }
    out.len += length
  }
  true
}
