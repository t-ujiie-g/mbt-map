# tiff

TIFF, BigTIFF and GeoTIFF reading in MoonBit, following [geotiff.js](https://github.com/geotiffjs/geotiff.js) 3.0.5: the image directories with their geo tags, and blocks (tiles or strips) decoded and copied into a window of pixels. Pure MoonBit on every backend (wasm, wasm-gc, js, native).

Part of [mbt-map](https://github.com/t-ujiie-g/mbt-map), a WebGIS library, published on its own.

```sh
moon add t-ujiie-g/tiff
```

```moonbit
/// The first sample of the first image of an uncompressed, LZW or PackBits TIFF held whole in `file`.
fn first_band(file : Bytes) -> FixedArray[Byte] raise @tiff.TiffError {
  let (images, little) = @tiff.read_tiff(file[:])
  let image = images[0]
  let window = @tiff.Window::new(image, little, 0, 0, image.width, image.height, [0], 0.0)
  for i in 0..<(image.across() * image.down()) {
    let start = image.offsets[i].to_int()
    let end = start + image.counts[i].to_int()
    window.block(i, file[start:end], false)
  }
  window.bands[0]
}
```

## How it reads

- `read_tiff(bytes)` reads the IFDs from the start of a file. It raises `Truncated(need)` when they lie past the bytes given, so a reader over HTTP range requests can fetch `need` bytes and try again.
- `Image` is one IFD: size, tiling, bits and sample formats, compression and predictor, block `offsets` and `counts`, and the geo tags (`pixel_scale`, `tiepoint`, `transform`, `epsg`, `nodata`).
- `Window::new(image, little, x0, y0, x1, y1, samples, fill)` is a rectangle of pixels to fill; `Window::block(index, data, decoded)` decodes one block and copies its part; `Window::empty(index, value)` fills a block the file leaves out. `bands` then holds one little-endian buffer per sample.
- The caller fetches the bytes: the module does no I/O, which is how one reads only the blocks a window needs from a Cloud Optimized GeoTIFF.

Decoded here: uncompressed, LZW and PackBits blocks, predictors 2 and 3, bit depths under a byte. Blocks compressed otherwise (Deflate, JPEG, …) are for the caller to decode first: pass the decoded bytes with `decoded = true`. Writing TIFFs is not covered.

## Matching geotiff.js

The repository compares rasters read through this module with geotiff 3.0.5's `readRasters` on TIFFs of every layout read (strips, tiles, planar 2, LZW, Deflate, PackBits, predictors, sample formats, BigTIFF) (`geotiff:golden`).

## License

Apache-2.0 for the port; geotiff.js is under the MIT License (see `NOTICE`).
