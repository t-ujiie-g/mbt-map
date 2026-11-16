# meshopt

[meshoptimizer](https://github.com/zeux/meshoptimizer)'s decoders in MoonBit: the buffers glTF compresses with `EXT_meshopt_compression` / `KHR_meshopt_compression`, decoded as meshoptimizer 1.3.0's `MeshoptDecoder.decodeGltfBuffer` does. Pure MoonBit on every backend (wasm, wasm-gc, js, native), with no dependencies.

Part of [mbt-map](https://github.com/t-ujiie-g/mbt-map), a WebGIS library, published on its own.

```sh
moon add t-ujiie-g/meshopt
```

```moonbit
/// A buffer view of `count` elements of `size` bytes, or None if `source` is malformed.
fn view(
  source : FixedArray[Byte],
  count : Int,
  size : Int,
  mode : @meshopt.Mode,
  filter : @meshopt.Filter,
) -> FixedArray[Byte]? {
  // Check before allocating: the counts come from an untrusted glTF.
  guard @meshopt.source_fits(count, size, source.length(), mode, filter) else {
    return None
  }
  let target = FixedArray::make(count * size, b'\x00')
  let ok = @meshopt.decode_gltf_buffer(
    target,
    count,
    size,
    source,
    0,
    source.length(),
    mode,
    filter,
  )
  if ok { Some(target) } else { None }
}
```

- `Mode`: the extension's `mode`, `Attributes`, `Triangles` or `Indices`.
- `Filter`: its `filter`, `NoFilter` ("NONE"), `Octahedral`, `Quaternion`, `Exponential` or `Color`.
- `decode_gltf_buffer` returns false where meshoptimizer throws or asserts; the target is then partly written.

There is no encoder.

## Matching meshoptimizer

The repository compares the decoder with meshoptimizer 1.3.0's `MeshoptDecoder` (`meshopt:golden`): no difference on the js and wasm-gc backends.

## License

Apache-2.0 for the port; meshoptimizer is under the MIT License (see `NOTICE`).
