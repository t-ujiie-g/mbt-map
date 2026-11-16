# clipper

[Clipper2](https://github.com/AngusJohnson/Clipper2) in MoonBit: polygon clipping (union, intersection, difference, xor) and offsetting on 64-bit integer coordinates. It is a port of Clipper2 2.0.1 whose results are identical to the C++ library's, vertex for vertex, on every MoonBit backend (wasm, wasm-gc, js, native). It has no dependencies besides `moonbitlang/core`.

It is the geometry engine of [mbt-map](https://github.com/t-ujiie-g/mbt-map), a WebGIS library, published on its own.

```sh
moon add t-ujiie-g/clipper
```

```moonbit
fn square(x : Int64, y : Int64, s : Int64) -> Array[@clipper.Point64] {
  [{ x, y }, { x: x + s, y }, { x: x + s, y: y + s }, { x, y: y + s }]
}

test "clip and offset" {
  let a = [square(0L, 0L, 10L)]
  let b = [square(5L, 5L, 10L)]
  let both = @clipper.intersect(a, b, NonZero)
  assert_eq(@clipper.area(both[0][:]), 25.0)
  let either = @clipper.union(a, b, NonZero)
  assert_eq(@clipper.area(either[0][:]), 175.0)
  // A square grown by 1 with miter joins keeps its corners: 12 x 12.
  let grown = @clipper.inflate_paths(a, 1.0, Miter, Polygon)
  assert_eq(@clipper.area(grown[0][:]), 144.0)
}
```

## What is in it

- `union`, `intersect`, `difference`, `xor`, `boolean_op`: closed paths in, closed paths out, by a fill rule (`EvenOdd`, `NonZero`, `Positive`, `Negative`).
- `Clipper64`: the engine itself, for open subjects (`add_open_subject`) and for results as a tree of outer rings and holes (`execute_tree`, `PolyPath64`).
- `inflate_paths` and `ClipperOffset`: growing and shrinking polygons and buffering lines, with `Square`, `Bevel`, `Round` and `Miter` joins and `Polygon`, `Joined`, `Butt`, `Square` and `Round` ends.
- `area` (signed by orientation) and `point_in_polygon`.

Coordinates are integers (`Point64`), as in Clipper2: scale your numbers first (for example by 1000 for millimeters) and keep them within `MAX_COORD`.

Not ported: rectangle clipping, triangulation, Minkowski sums and Z values.

## Matching the C++ library

Clipper2's output depends on the order `std::sort` leaves equal elements in, so this port carries libc++'s sort (`libcxx_sort.mbt`). The repository checks 10,720 clipping runs and 4,500 offset runs against the C++ library compiled to WebAssembly from the same commit (clipper2-wasm 0.4.0): all identical on the js and wasm-gc backends.

## License

Apache-2.0 for the port; Clipper2 is under the Boost Software License 1.0 (see `NOTICE`).
