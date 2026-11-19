// Ported from fzstd 0.1.1 (https://github.com/101arrowz/fzstd): MIT License,
// Copyright (c) 2020 Arjun Barrett. See NOTICE. The format is RFC 8878's.

///|
/// Largest block a frame may hold (RFC 8878 3.1.1.2.3).
const MAX_BLOCK : Int32 = 1 << 17

///|
/// Output bytes, growing: a frame's matches reach back into it.
priv struct Out {
  mut bytes : FixedArray[Byte]
  mut len : Int32
  limit : Int32
}

///|
/// Makes room for `n` more bytes; false if that passes the limit.
fn Out::room(self : Out, n : Int32) -> Bool {
  guard n >= 0 && n <= self.limit - self.len else { return false }
  if self.len + n > self.bytes.length() {
    let grown = FixedArray::make(
      (self.bytes.length() * 2).max(self.len + n),
      b'\x00',
    )
    self.bytes.blit_to(grown, len=self.len)
    self.bytes = grown
  }
  true
}

///|
/// The position of the highest set bit of `v` (positive).
fn msb(v : Int32) -> Int32 {
  31 - v.clz()
}

///|
/// Up to 32 bits of `b` from bit `pos`, the lowest of each byte first; bits outside `b` are 0.
fn bits_at(b : BytesView, pos : Int32, n : Int32) -> Int32 {
  guard n > 0 else { return 0 }
  let mut v = 0UL
  let first = pos >> 3
  for k in 0..<5 {
    let at = first + k
    if at >= 0 && at < b.length() {
      v = v | (b[at].to_uint64() << (k * 8))
    }
  }
  ((v >> (pos & 7)) & ((1UL << n) - 1UL)).to_int()
}

///|
/// An FSE decoding table of `1 << accuracy` states: each state's symbol, how many bits to read
/// for the next state and that state's base.
priv struct Fse {
  accuracy : Int32
  symbols : FixedArray[Byte]
  bits : FixedArray[Byte]
  next : FixedArray[Int32]
}

///|
/// The table of normalized counts `counts` (-1 for a "less than one" probability), which must
/// sum to `1 << accuracy`; None otherwise.
fn Fse::build(counts : ArrayView[Int32], accuracy : Int32) -> Fse? {
  let size = 1 << accuracy
  let symbols = FixedArray::make(size, b'\x00')
  let bits = FixedArray::make(size, b'\x00')
  let next = FixedArray::make(size, 0)
  // Symbols of probability "less than one" take the last cells.
  let mut high = size
  let state = FixedArray::make(counts.length(), 0)
  let mut total = 0
  for s, count in counts {
    if count == -1 {
      guard high > 0 else { return None }
      high -= 1
      symbols[high] = s.to_byte()
      state[s] = 1
      total += 1
    } else {
      state[s] = count
      total += count
    }
  }
  guard total == size else { return None }
  let step = (size >> 1) + (size >> 3) + 3
  let mask = size - 1
  let mut pos = 0
  for s, count in counts {
    for _ in 0..<count {
      symbols[pos] = s.to_byte()
      pos = (pos + step) & mask
      while pos >= high {
        pos = (pos + step) & mask
      }
    }
  }
  guard pos == 0 else { return None }
  for i in 0..<size {
    let s = symbols[i].to_int()
    let n = state[s]
    state[s] += 1
    let nb = accuracy - msb(n)
    bits[i] = nb.to_byte()
    next[i] = (n << nb) - size
  }
  Some({ accuracy, symbols, bits, next, })
}

///|
/// The FSE table described in `b` from byte `at` (RFC 8878 4.1.1), of an accuracy of at most
/// `max`, and the byte after it; None if malformed.
fn Fse::read(b : BytesView, at : Int32, max : Int32) -> (Fse, Int32)? {
  guard at < b.length() else { return None }
  let accuracy = (b[at].to_int() & 15) + 5
  guard accuracy <= max else { return None }
  let end = b.length() * 8
  let mut pos = at * 8 + 4
  let mut left = 1 << accuracy
  let counts : Array[Int32] = []
  while left > 0 && counts.length() < 256 {
    guard pos < end else { return None }
    let n = msb(left + 1)
    let mask = (1 << (n + 1)) - 1
    let low = (1 << n) - 1
    let small = mask - left - 1
    let mut value = bits_at(b, pos, n + 1)
    if (value & low) < small {
      pos += n
      value = value & low
    } else {
      pos += n + 1
      if value > low {
        value -= small
      }
    }
    value -= 1
    counts.push(value)
    left -= value.abs()
    if value == 0 {
      // Zeros repeat: two bits say how many more, 3 meaning "and read again".
      while true {
        guard pos < end else { return None }
        let repeat = bits_at(b, pos, 2)
        pos += 2
        for _ in 0..<repeat {
          counts.push(0)
        }
        guard repeat == 3 else { break }
      }
    }
  }
  guard left == 0 && counts.length() <= 256 && pos <= end else { return None }
  match Fse::build(counts, accuracy) {
    Some(table) => Some((table, (pos + 7) >> 3))
    None => None
  }
}

///|
/// A table of the one symbol `symbol` (RLE mode).
fn Fse::single(symbol : Int32) -> Fse {
  { accuracy: 0, symbols: [symbol.to_byte()], bits: [b'\x00'], next: [0], }
}

///|
/// A Huffman decoding table of `1 << bits` cells: each cell's symbol and its code's length.
priv struct Huffman {
  bits : Int32
  symbols : FixedArray[Byte]
  lengths : FixedArray[Byte]
}

///|
/// The Huffman table described in `b` from byte `at` (RFC 8878 4.2.1) and the byte after it;
/// None if malformed.
fn Huffman::read(b : BytesView, at : Int32) -> (Huffman, Int32)? {
  guard at < b.length() else { return None }
  let head = b[at].to_int()
  let weights : Array[Int32] = []
  let mut after = at + 1
  if head < 128 {
    // Weights compressed with FSE, two states taking turns, read from the end.
    after = at + 1 + head
    guard after <= b.length() && head > 0 else { return None }
    let stream = b[at + 1:after]
    guard Fse::read(stream, 0, 6) is Some((table, start)) else { return None }
    let last = stream[stream.length() - 1].to_int()
    guard last != 0 && start < stream.length() else { return None }
    let floor = start * 8
    let mut pos = stream.length() * 8 - 8 + msb(last)
    pos -= table.accuracy
    guard pos >= floor else { return None }
    let mut s1 = bits_at(stream, pos, table.accuracy)
    pos -= table.accuracy
    guard pos >= floor else { return None }
    let mut s2 = bits_at(stream, pos, table.accuracy)
    while weights.length() < 255 {
      weights.push(table.symbols[s1].to_int())
      let n1 = table.bits[s1].to_int()
      if pos - n1 < floor {
        weights.push(table.symbols[s2].to_int())
        break
      }
      pos -= n1
      s1 = table.next[s1] + bits_at(stream, pos, n1)
      weights.push(table.symbols[s2].to_int())
      let n2 = table.bits[s2].to_int()
      if pos - n2 < floor {
        weights.push(table.symbols[s1].to_int())
        break
      }
      pos -= n2
      s2 = table.next[s2] + bits_at(stream, pos, n2)
    }
    guard weights.length() <= 255 else { return None }
  } else {
    let count = head - 127
    after = at + 1 + (count + 1) / 2
    guard after <= b.length() else { return None }
    for i in 0..<count {
      let byte = b[at + 1 + i / 2].to_int()
      weights.push(if i % 2 == 0 { byte >> 4 } else { byte & 15 })
    }
  }
  // The last weight is what brings the sum of 2^(weight - 1) to a power of two.
  let mut sum = 0
  for w in weights {
    guard w <= 11 else { return None }
    if w > 0 {
      sum += 1 << (w - 1)
    }
  }
  guard sum > 0 else { return None }
  let max = msb(sum) + 1
  let size = 1 << max
  let rest = size - sum
  guard max <= 11 && rest > 0 && (rest & (rest - 1)) == 0 else { return None }
  weights.push(msb(rest) + 1)
  let symbols = FixedArray::make(size, b'\x00')
  let lengths = FixedArray::make(size, b'\x00')
  // Codes by weight, the lightest first, symbols in order within a weight.
  let mut cell = 0
  for weight in 1..<=max {
    for symbol, w in weights {
      guard w == weight else { continue }
      let span = 1 << (weight - 1)
      guard cell <= size - span else { return None }
      for k in cell..<(cell + span) {
        symbols[k] = symbol.to_byte()
        lengths[k] = (max + 1 - weight).to_byte()
      }
      cell += span
    }
  }
  guard cell == size else { return None }
  Some(({ bits: max, symbols, lengths, }, after))
}

///|
/// Decodes the Huffman stream `stream` (read from its end) into `count` bytes of `out` from
/// `at`; false if it does not hold exactly them.
fn Huffman::decode(
  self : Huffman,
  stream : BytesView,
  out : FixedArray[Byte],
  at : Int32,
  count : Int32,
) -> Bool {
  guard stream.length() > 0 else { return false }
  let last = stream[stream.length() - 1].to_int()
  guard last != 0 else { return false }
  let mut pos = stream.length() * 8 - 8 + msb(last)
  let mask = (1 << self.bits) - 1
  let mut state = 0
  let mut take = self.bits
  for i in 0..<count {
    pos -= take
    // The last codes may be shorter than a table index: the bits before the stream are 0.
    guard pos > -self.bits else { return false }
    state = ((state << take) | bits_at(stream, pos, take)) & mask
    out[at + i] = self.symbols[state]
    take = self.lengths[state].to_int()
  }
  pos + self.bits - take == 0
}

///|
/// Extra bits of each literal length code (RFC 8878 3.1.1.3.2.1.1).
let ll_bits : FixedArray[Int32] = [
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 3, 3, 4, 6, 7,
  8, 9, 10, 11, 12, 13, 14, 15, 16,
]

///|
/// Extra bits of each match length code.
let ml_bits : FixedArray[Int32] = [
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 3, 3, 4, 4, 5, 7, 8, 9, 10, 11, 12, 13, 14, 15,
  16,
]

///|
/// The baseline of each code: `start`, then each code's baseline plus two to its extra bits.
fn baselines(bits : FixedArray[Int32], start : Int32) -> FixedArray[Int32] {
  let out = FixedArray::make(bits.length(), 0)
  let mut base = start
  for i, n in bits {
    out[i] = base
    base += 1 << n
  }
  out
}

///|
let ll_base : FixedArray[Int32] = baselines(ll_bits, 0)

///|
let ml_base : FixedArray[Int32] = baselines(ml_bits, 3)

///|
/// The predefined distributions (RFC 8878 3.1.1.3.2.2): literal lengths, offsets, match lengths.
let default_ll : Fse = Fse::build(
  [
    4, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 3,
    2, 1, 1, 1, 1, 1, -1, -1, -1, -1,
  ],
  6,
).unwrap()

///|
let default_of : Fse = Fse::build(
  [
    1, 1, 1, 1, 1, 1, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, -1, -1,
    -1, -1, -1,
  ],
  5,
).unwrap()

///|
let default_ml : Fse = Fse::build(
  [
    1, 4, 3, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, -1, -1, -1, -1, -1,
    -1, -1,
  ],
  6,
).unwrap()

///|
/// What a frame keeps from block to block: the Huffman table, the three sequence tables and
/// the last three offsets.
priv struct Frame {
  mut huffman : Huffman?
  mut ll : Fse?
  mut of : Fse?
  mut ml : Fse?
  offsets : FixedArray[Int32]
  // Where the frame starts in the output: matches reach no further back.
  start : Int32
  literals : FixedArray[Byte]
}

///|
/// The literals of the compressed block `b` (RFC 8878 3.1.1.3.1) into `frame.literals`: how
/// many, and the byte after their section; None if malformed.
fn Frame::literals(self : Frame, b : BytesView) -> (Int32, Int32)? {
  guard b.length() >= 1 else { return None }
  let head = b[0].to_int()
  let kind = head & 3
  let format = (head >> 2) & 3
  let byte = (i : Int32) => if i < b.length() { b[i].to_int() } else { 0 }
  let mut size = 0
  let mut packed = 0
  let mut at = 1
  let mut streams = 1
  if kind < 2 {
    match format {
      0 | 2 => size = head >> 3
      1 => {
        size = (head >> 4) | (byte(1) << 4)
        at = 2
      }
      _ => {
        size = (head >> 4) | (byte(1) << 4) | (byte(2) << 12)
        at = 3
      }
    }
  } else {
    let word = head | (byte(1) << 8) | (byte(2) << 16)
    match format {
      0 | 1 => {
        streams = if format == 0 { 1 } else { 4 }
        size = (word >> 4) & 0x3ff
        packed = (word >> 14) & 0x3ff
        at = 3
      }
      2 => {
        streams = 4
        let word = word | (byte(3) << 24)
        size = (word >> 4) & 0x3fff
        packed = (word >> 18) & 0x3fff
        at = 4
      }
      _ => {
        streams = 4
        size = ((word >> 4) | (byte(3) << 20)) & 0x3ffff
        packed = ((byte(2) >> 6) | (byte(3) << 2) | (byte(4) << 10)) & 0x3ffff
        at = 5
      }
    }
  }
  guard at <= b.length() && size <= MAX_BLOCK else { return None }
  let out = self.literals
  match kind {
    0 => {
      guard size <= b.length() - at else { return None }
      out.blit_from_bytesview(0, b[at:at + size])
      Some((size, at + size))
    }
    1 => {
      guard at < b.length() else { return None }
      out.fill(b[at], start=0, end=size)
      Some((size, at + 1))
    }
    _ => {
      guard packed <= b.length() - at else { return None }
      let end = at + packed
      let mut from = at
      if kind == 2 {
        guard Huffman::read(b[:end], at) is Some((table, after)) else {
          return None
        }
        self.huffman = Some(table)
        from = after
      }
      guard self.huffman is Some(table) && from <= end else { return None }
      if streams == 1 {
        guard table.decode(b[from:end], out, 0, size) else { return None }
      } else {
        // Four streams: the first three's lengths, then the streams; each a quarter of the bytes.
        guard end - from >= 6 else { return None }
        let quarter = (size + 3) / 4
        let mut src = from + 6
        let mut dst = 0
        for k in 0..<4 {
          let length = if k < 3 {
            byte(from + k * 2) | (byte(from + k * 2 + 1) << 8)
          } else {
            end - src
          }
          let count = if k < 3 { quarter } else { size - dst }
          guard length >= 0 &&
            length <= end - src &&
            count >= 0 &&
            dst + count <= size &&
            table.decode(b[src:src + length], out, dst, count) else {
            return None
          }
          src += length
          dst += count
        }
      }
      Some((size, end))
    }
  }
}

///|
/// The table a sequence section names for one of its three codes: `mode` 0 the predefined one,
/// 1 one symbol (a byte), 2 a description, 3 the frame's last; with the byte after what it read.
fn sequence_table(
  b : BytesView,
  at : Int32,
  mode : Int32,
  default : Fse,
  last : Fse?,
  max_accuracy : Int32,
  max_symbol : Int32,
) -> (Fse, Int32)? {
  match mode {
    0 => Some((default, at))
    1 => {
      guard at < b.length() && b[at].to_int() <= max_symbol else { return None }
      Some((Fse::single(b[at].to_int()), at + 1))
    }
    2 => {
      guard Fse::read(b, at, max_accuracy) is Some((table, after)) else {
        return None
      }
      for s in table.symbols {
        guard s.to_int() <= max_symbol else { return None }
      }
      Some((table, after))
    }
    _ =>
      match last {
        Some(table) => Some((table, at))
        None => None
      }
  }
}

///|
/// Decodes a compressed block `b` of `frame` onto the end of `out`; false if malformed or past
/// `out`'s limit.
fn Frame::block(self : Frame, b : BytesView, out : Out) -> Bool {
  guard self.literals(b) is Some((count, after)) else { return false }
  let literals = self.literals
  let mut at = after
  guard at < b.length() else { return false }
  let mut sequences = b[at].to_int()
  at += 1
  if sequences == 255 {
    guard at <= b.length() - 2 else { return false }
    sequences = (b[at].to_int() | (b[at + 1].to_int() << 8)) + 0x7f00
    at += 2
  } else if sequences > 127 {
    guard at < b.length() else { return false }
    sequences = ((sequences - 128) << 8) | b[at].to_int()
    at += 1
  }
  let mut used = 0
  if sequences > 0 {
    guard at < b.length() else { return false }
    let modes = b[at].to_int()
    at += 1
    guard (modes & 3) == 0 else { return false }
    guard sequence_table(b, at, modes >> 6, default_ll, self.ll, 9, 35)
      is Some((ll, a1)) &&
      sequence_table(b, a1, (modes >> 4) & 3, default_of, self.of, 8, 31)
      is Some((of, a2)) &&
      sequence_table(b, a2, (modes >> 2) & 3, default_ml, self.ml, 9, 52)
      is Some((ml, a3)) else {
      return false
    }
    self.ll = Some(ll)
    self.of = Some(of)
    self.ml = Some(ml)
    guard a3 < b.length() else { return false }
    let stream = b[a3:]
    let last = stream[stream.length() - 1].to_int()
    guard last != 0 else { return false }
    let mut pos = stream.length() * 8 - 8 + msb(last)
    let take = (n : Int32) => {
      pos -= n
      bits_at(stream, pos, n)
    }
    let mut ll_state = take(ll.accuracy)
    let mut of_state = take(of.accuracy)
    let mut ml_state = take(ml.accuracy)
    let offsets = self.offsets
    for i in 0..<sequences {
      let of_code = of.symbols[of_state].to_int()
      let ml_code = ml.symbols[ml_state].to_int()
      let ll_code = ll.symbols[ll_state].to_int()
      // An offset of 2^31 or more cannot be reached in an output that Int32 counts.
      guard of_code < 31 else { return false }
      let raw = (1 << of_code) + take(of_code)
      let match_length = ml_base[ml_code] + take(ml_bits[ml_code])
      let literal_length = ll_base[ll_code] + take(ll_bits[ll_code])
      if i + 1 < sequences {
        ll_state = ll.next[ll_state] + take(ll.bits[ll_state].to_int())
        ml_state = ml.next[ml_state] + take(ml.bits[ml_state].to_int())
        of_state = of.next[of_state] + take(of.bits[of_state].to_int())
      }
      guard pos >= 0 else { return false }
      // Offsets 1 to 3 repeat one of the last three (shifted by one after no literals).
      let offset = if raw > 3 {
        offsets[2] = offsets[1]
        offsets[1] = offsets[0]
        offsets[0] = raw - 3
        raw - 3
      } else {
        let index = raw - (if literal_length != 0 { 1 } else { 0 })
        if index == 0 {
          offsets[0]
        } else {
          let value = if index == 3 { offsets[0] - 1 } else { offsets[index] }
          guard value > 0 else { return false }
          if index > 1 {
            offsets[2] = offsets[1]
          }
          offsets[1] = offsets[0]
          offsets[0] = value
          value
        }
      }
      guard literal_length <= count - used &&
        out.room(literal_length) &&
        offset <= out.len + literal_length - self.start &&
        out.room(literal_length + match_length) else {
        return false
      }
      literals.blit_to(
        out.bytes,
        len=literal_length,
        src_offset=used,
        dst_offset=out.len,
      )
      used += literal_length
      out.len += literal_length
      // Byte by byte: a match may overlap what it writes.
      for k in 0..<match_length {
        out.bytes[out.len + k] = out.bytes[out.len - offset + k]
      }
      out.len += match_length
    }
    guard pos == 0 else { return false }
  }
  // The literals no sequence took end the block.
  guard out.room(count - used) else { return false }
  literals.blit_to(
    out.bytes,
    len=count - used,
    src_offset=used,
    dst_offset=out.len,
  )
  out.len += count - used
  true
}

///|
/// The frame at byte `at` of `src` decoded onto `out`: the byte after it, or -1 if it is
/// malformed, uses a dictionary, or passes `out`'s limit.
fn frame(src : BytesView, at : Int32, out : Out) -> Int32 {
  let n = src.length()
  guard at <= n - 5 else { return -1 }
  let flags = src[at + 4].to_int()
  let single = (flags >> 5) & 1
  let checksum = (flags >> 2) & 1
  guard (flags & 8) == 0 else { return -1 }
  let dictionary = [0, 1, 2, 4][flags & 3]
  let content = match flags >> 6 {
    0 => single
    1 => 2
    2 => 4
    _ => 8
  }
  let mut pos = at + 5 + (1 - single)
  guard pos <= n - dictionary - content else { return -1 }
  for k in 0..<dictionary {
    guard src[pos + k] == b'\x00' else { return -1 }
  }
  pos += dictionary + content
  let state : Frame = {
    huffman: None,
    ll: None,
    of: None,
    ml: None,
    offsets: [1, 4, 8],
    start: out.len,
    literals: FixedArray::make(MAX_BLOCK, b'\x00'),
  }
  while true {
    guard pos <= n - 3 else { return -1 }
    let head = src[pos].to_int() |
      (src[pos + 1].to_int() << 8) |
      (src[pos + 2].to_int() << 16)
    pos += 3
    let size = head >> 3
    match (head >> 1) & 3 {
      0 => {
        guard size <= n - pos && out.room(size) else { return -1 }
        out.bytes.blit_from_bytesview(out.len, src[pos:pos + size])
        out.len += size
        pos += size
      }
      1 => {
        guard pos < n && out.room(size) else { return -1 }
        out.bytes.fill(src[pos], start=out.len, end=out.len + size)
        out.len += size
        pos += 1
      }
      2 => {
        guard size <= MAX_BLOCK &&
          size <= n - pos &&
          state.block(src[pos:pos + size], out) else {
          return -1
        }
        pos += size
      }
      _ => return -1
    }
    if (head & 1) == 1 {
      break
    }
  }
  pos += checksum * 4
  guard pos <= n else { return -1 }
  pos
}

///|
/// The bytes the Zstandard frames of `src` hold, one after another (skippable frames passed
/// over), at most `limit`; None if `src` is malformed, uses a dictionary or holds more.
/// Checksums are not verified.
pub fn decompress(src : BytesView, limit~ : Int32 = 0x7fffffff) -> Bytes? {
  let out : Out = { bytes: FixedArray::make(1024, b'\x00'), len: 0, limit, }
  let n = src.length()
  let mut pos = 0
  while pos < n {
    guard pos <= n - 8 || pos <= n - 4 else { return None }
    guard pos <= n - 4 else { return None }
    let magic = src[pos].to_int() |
      (src[pos + 1].to_int() << 8) |
      (src[pos + 2].to_int() << 16) |
      (src[pos + 3].to_int() << 24)
    if (magic & 0xfffffff0) == 0x184d2a50 {
      // A skippable frame: its length, then that many bytes.
      guard pos <= n - 8 else { return None }
      let mut length = 0UL
      for k in 0..<4 {
        length = length | (src[pos + 4 + k].to_uint64() << (k * 8))
      }
      guard length <= (n - pos - 8).to_uint64() else { return None }
      pos += 8 + length.to_int()
      continue
    }
    guard magic == 0xfd2fb528 else { return None }
    pos = frame(src, pos, out)
    guard pos >= 0 else { return None }
  }
  Some(Bytes::makei(out.len, i => out.bytes[i]))
}
