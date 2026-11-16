# draco

A [Draco](https://github.com/google/draco) decoder in MoonBit: meshes (as glTF's `KHR_draco_mesh_compression` stores them) and point clouds, decoded as Draco 1.5.7's decoder (the `draco3d` npm package) does. Pure MoonBit on every backend (wasm, wasm-gc, js, native), with no dependencies.

Part of [mbt-map](https://github.com/t-ujiie-g/mbt-map), a WebGIS library, published on its own.

```sh
moon add t-ujiie-g/draco
```

```moonbit
/// The triangle count and the bytes of the attribute glTF names with `id`.
fn read(bytes : FixedArray[Byte], id : Int) -> (Int, FixedArray[Byte])? {
  guard @draco.decode(bytes, 0, bytes.length()) is Some(mesh) else { return None }
  guard mesh.attribute(id) is Some(attribute) else { return None }
  Some((mesh.indices.length() / 3, attribute.data))
}
```

## What it gives

- `decode(src, offset, length)`: a `DracoMesh`, or `None` for data draco3d refuses, bitstreams before 2.0, and meshes past the caps (`MAX_POINTS` and the like: the input is treated as untrusted).
- `DracoMesh`: `indices` (three point indices per face, none for a point cloud), `num_points`, `attributes`.
- `DracoAttribute`: `unique_id` (what the glTF extension's `attributes` name), Draco's `attribute_type` (0 POSITION, 1 NORMAL, 2 COLOR, 3 TEX_COORD, 4 GENERIC) and `data_type` (1 INT8 … 9 FLOAT32, 10 FLOAT64, 11 BOOL), `num_components`, `normalized`, and `data`: little-endian values for every point, as draco3d's `GetAttributeDataArrayForAllPoints` gives them (quantized and octahedral attributes come out as FLOAT32).
- `DracoMesh::to_bytes()`: everything in one buffer (a header of u32s, the indices, each attribute's data), the layout mbt-map's worker hands to JavaScript.

Covered: sequential and edgebreaker meshes (standard, predictive and valence traversals), sequential and kd-tree point clouds, the prediction schemes and transforms, rANS. There is no encoder.

## Matching draco3d

The repository compares the decoder with draco3d 1.5.7 on seeded meshes and point clouds, Draco's own test files and PLATEAU's 3D tiles, plus corrupted copies (`draco:golden`): no difference on the js and wasm-gc backends.

## License

Apache-2.0, as Draco itself (see `NOTICE`).
