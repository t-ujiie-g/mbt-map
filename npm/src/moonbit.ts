// The entry the MoonBit API (mooncakes t-ujiie-g/moonmap) imports. MoonBit's `#module` imports call
// what they import, so the constructor is handed over as a function; the rest are methods of `Map`.
import { Map, type MapOptions } from "./index";

/** `new Map(options)`. */
export function createMap(options: MapOptions): Map {
  return new Map(options);
}
