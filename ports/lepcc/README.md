# lepcc

[LEPCC](https://github.com/Esri/lepcc) (Limited Error Point Cloud Compression) decoders in MoonBit: the `lepcc-xyz`, `lepcc-rgb` and `lepcc-intensity` buffers of I3S point cloud scene layers, decoded as Esri's LEPCC C API does. Pure MoonBit on every backend (wasm, wasm-gc, js, native), with no dependencies.

Part of [mbt-map](https://github.com/t-ujiie-g/mbt-map), a WebGIS library, published on its own.

```sh
moon add t-ujiie-g/lepcc
```

```moonbit
/// The number of points in a `lepcc-xyz` resource, or None if it is malformed.
fn point_count(resource : FixedArray[Byte]) -> Int? {
  guard @lepcc.decode(Xyz, resource, 0, resource.length()) is Some(out) else {
    return None
  }
  Some(out[0].to_int() | (out[1].to_int() << 8) | (out[2].to_int() << 16) | (out[3].to_int() << 24))
}
```

`decode(kind, data, start, len)` gives one little-endian buffer, or `None` where Esri's decoder refuses the blob (and for blobs of no points or more than `MAX_POINTS`; the input is treated as untrusted):

| Bytes | Content |
| --- | --- |
| 8 | u32 count `n`, u32 0 |
| 24 × `n` (`Xyz`) | f64 x, y, z per point, absolute coordinates in the layer's spatial reference |
| 3 × `n` (`Rgb`) | u8 r, g, b per point |
| 2 × `n` (`Intensity`) | u16 per point |

`FlagBytes` blobs are not ported (always `None`). There is no encoder.

## Matching Esri's library

The repository compares the decoders with Esri's C++ (a pinned commit) on blobs its encoder writes, plus corrupted copies (`lepcc:golden`): no difference on the js and wasm-gc backends.

## License

Apache-2.0, as LEPCC itself (see `NOTICE`).
