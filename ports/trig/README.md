# trig

The elementary functions a computation takes, as a value: `Trig` holds `sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `atan2`, `exp`, `ln`, `pow`, `cbrt` and `atanh`. `Trig::moonbit()` gives MoonBit's `@math`; a wasm build can pass its host's `Math` instead.

Two reasons to take the functions as an argument. A port of a JavaScript library only gives the library's results bit for bit if it computes with the same `Math` (the last digit of `sin` differs between implementations). And a wasm-gc module that imports the host's functions does not carry `@math`. [`t-ujiie-g/proj`](https://mooncakes.io/docs/t-ujiie-g/proj) and [`t-ujiie-g/geodesic`](https://mooncakes.io/docs/t-ujiie-g/geodesic) take a `Trig` for both.

Part of [mbt-map](https://github.com/t-ujiie-g/mbt-map), a WebGIS library, published on its own.

```sh
moon add t-ujiie-g/trig
```

```moonbit
/// The great-circle distance in radians, with the functions the caller chose.
fn arc(m : @trig.Trig, lat1 : Double, lat2 : Double, dlon : Double) -> Double {
  m.acos(
    m.sin(lat1) * m.sin(lat2) + m.cos(lat1) * m.cos(lat2) * m.cos(dlon),
  )
}

///|
/// MoonBit's functions, with one replaced.
fn with_pow(pow : (Double, Double) -> Double) -> @trig.Trig {
  { ..@trig.Trig::moonbit(), pow, }
}
```

## What it gives

- `Trig`: a struct of twelve function fields, public, so a host's functions go in with a record (`{ sin: host_sin, … }`) or replace some of MoonBit's (`{ ..Trig::moonbit(), pow }`).
- `Trig::moonbit()`: the functions of `moonbitlang/core/math`.
- A method for each field (`m.sin(x)`, `m.atan2(y, x)`, …), calling it.

For a wasm host, declare the imports (`fn host_sin(x : Double) -> Double = "math" "sin"`) and build the `Trig` once from them; the module then links no `@math` unless something else in it does.

## License

Apache-2.0 (see `NOTICE`). No third-party code.
