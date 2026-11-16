# robust

Robust geometric predicates in MoonBit: `orient2d` of [robust-predicates](https://github.com/mourner/robust-predicates) 3.0.3, after Jonathan Shewchuk's adaptive-precision arithmetic. The result is bit for bit the JavaScript library's, on every MoonBit backend (wasm, wasm-gc, js, native). No dependencies besides `moonbitlang/core`.

Part of [mbt-map](https://github.com/t-ujiie-g/mbt-map), a WebGIS library, published on its own.

```sh
moon add t-ujiie-g/robust
```

```moonbit
test "orient2d" {
  // Twice the signed area of the triangle a, b, c; the sign is exact.
  assert_true(@robust.orient2d(0, 0, 1, 0, 0, 1) < 0) // counter-clockwise (y up)
  assert_true(@robust.orient2d(0, 0, 0, 1, 1, 0) > 0) // clockwise
  assert_true(@robust.orient2d(0, 0, 1, 1, 2, 2) == 0) // collinear
}
```

`orient2d(ax, ay, bx, by, cx, cy)` is positive when a, b, c turn clockwise in a y-up frame, negative when counter-clockwise and 0 when collinear, also where plain floating-point arithmetic would get the sign wrong. Only `orient2d` is ported (not `orient3d`, `incircle` or `insphere`).

## License

Apache-2.0 for the port; robust-predicates is under the Unlicense (see `NOTICE`).
