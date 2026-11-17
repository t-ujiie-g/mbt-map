# pbf

The [Protocol Buffers](https://protobuf.dev/programming-guides/encoding/) wire format in MoonBit: a zero-copy reader that walks messages by hand, and a small writer. Pure MoonBit on every backend (wasm, wasm-gc, js, native), with no dependencies outside the standard library. There is no `.proto` compiler: you read the tags and call the reader for each field, as [pbf](https://github.com/mapbox/pbf) users do in JavaScript.

Part of [mbt-map](https://github.com/t-ujiie-g/mbt-map), a WebGIS library, where it reads vector tiles and ArcGIS feature responses; published on its own.

```sh
moon add t-ujiie-g/pbf
```

```moonbit
/// The `name` (field 1, a string) and the sum of `sizes` (field 2, packed varints) of a message.
fn read(bytes : Bytes) -> (String, Int)? {
  let r = @pbf.Reader::new(bytes[:])
  let mut name = ""
  let mut sum = 0
  while !r.at_end() {
    let tag = r.read_tag()
    if tag == @pbf.tag(1, @pbf.WIRE_LEN) {
      name = r.read_string()
    } else if tag == @pbf.tag(2, @pbf.WIRE_LEN) {
      let token = r.enter()
      while !r.at_end() {
        sum += r.read_varint32()
      }
      r.exit(token)
    } else {
      r.skip(tag)
    }
  }
  guard r.error() is None else { return None }
  Some((name, sum))
}
```

## What it gives

- `Reader`: a cursor over a `BytesView`. `read_tag`, `read_varint32` / `read_varint64`, `read_svarint32` / `read_sint64` (zigzag), `read_int64`, `read_bool`, `read_fixed32` / `read_fixed64`, `read_float` / `read_double`, `read_bytes` (a view of the buffer, no copy), `read_string` (UTF-8, invalid sequences become U+FFFD as `TextDecoder` does), `skip(tag)`.
- Nested messages and packed fields without allocating: `enter()` narrows the reader to the next length-delimited field and `exit(token)` leaves it; `read_len_start()` skips a field and gives where it starts, and `reset(start, end)` moves a reader back over a range.
- Errors are sticky, never raised: a failed read records the first `PbfError` (`UnexpectedEof`, `VarintTooLong`, `UnsupportedWireType`, `LengthOutOfRange`, each with its byte offset), returns 0 and moves to the end, so `at_end` loops stop. Check `error()` or `failed()` once per message. In wasm-gc a call to a function that may raise allocates even when it succeeds, which is why the hot path has none.
- `Writer`: `write_tag`, `write_varint`, `write_varint32`, `write_svarint32`, `write_sint64`, `write_fixed32`, `write_fixed64`, `write_bytes`, `write_string`, `to_bytes`. It is a minimal encoder meant for test data and small messages.
- `tag(field, wire)` and `WIRE_VARINT`, `WIRE_FIXED64`, `WIRE_LEN`, `WIRE_FIXED32`.

The input is treated as untrusted: every read is bounds-checked, varints longer than 10 bytes and lengths past the end of the range are errors, and groups (wire types 3 and 4) are refused.

## License

Apache-2.0. The module is written from the Protocol Buffers encoding documentation and contains no third-party code (see `NOTICE`).
