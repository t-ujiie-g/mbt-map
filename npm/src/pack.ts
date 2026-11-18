// What mbt-map/table sends table.wasm with an operation (docs/dev/FORMATS.md "Table operations"):
// JSON packed so that the wasm needs no JSON parser, names and property values. Import-free.

const encoder = new TextEncoder();

/** Bytes written one value after another, little-endian. */
export class Packer {
  #bytes = new Uint8Array(256);
  #view = new DataView(this.#bytes.buffer);
  #at = 0;

  #room(n: number): number {
    if (this.#at + n > this.#bytes.length) {
      const grown = new Uint8Array(Math.max(this.#bytes.length * 2, this.#at + n));
      grown.set(this.#bytes);
      this.#bytes = grown;
      this.#view = new DataView(grown.buffer);
    }
    const at = this.#at;
    this.#at += n;
    return at;
  }

  u8(v: number): this {
    const at = this.#room(1);
    this.#view.setUint8(at, v);
    return this;
  }

  u32(v: number): this {
    const at = this.#room(4);
    this.#view.setUint32(at, v, true);
    return this;
  }

  f64(v: number): this {
    const at = this.#room(8);
    this.#view.setFloat64(at, v, true);
    return this;
  }

  /** A u32 byte length and the UTF-8 bytes. */
  utf8(s: string): this {
    const b = encoder.encode(s);
    this.u32(b.length);
    const at = this.#room(b.length);
    this.#bytes.set(b, at);
    return this;
  }

  /**
   * JSON: a tag (0 null, 1 false, 2 true, 3 number, 4 string, 5 array, 6 object), then an f64, a
   * string, a u32 count and the items, or a count and key, value pairs. What JSON does not hold throws.
   */
  json(v: unknown): this {
    if (v === null) return this.u8(0);
    if (typeof v === "boolean") return this.u8(v ? 2 : 1);
    if (typeof v === "number") return this.u8(3).f64(v);
    if (typeof v === "string") return this.u8(4).utf8(v);
    if (Array.isArray(v)) {
      this.u8(5).u32(v.length);
      for (const item of v) this.json(item);
      return this;
    }
    if (typeof v === "object" && Object.getPrototypeOf(v) === Object.prototype) {
      const entries = Object.entries(v);
      this.u8(6).u32(entries.length);
      for (const [key, value] of entries) this.utf8(key).json(value);
      return this;
    }
    throw new Error(`mbt-map: analysis: not JSON: ${String(v)}`);
  }

  /**
   * A property value (docs/dev/FORMATS.md "Property values"): null, a boolean, a number or a string;
   * `undefined` leaves the row without the key, NaN is null, and other values are their JSON text.
   */
  value(v: unknown): this {
    if (v === undefined) return this.u8(5);
    if (v === null || (typeof v === "number" && Number.isNaN(v))) return this.u8(0);
    if (typeof v === "boolean") return this.u8(v ? 2 : 1);
    if (typeof v === "number") return this.u8(3).f64(v);
    return this.u8(4).utf8(typeof v === "string" ? v : typeof v === "bigint" ? String(v) : JSON.stringify(v) ?? "");
  }

  /** The bytes of `view` as they are. */
  bytes(view: ArrayBufferView): this {
    const at = this.#room(view.byteLength);
    this.#bytes.set(new Uint8Array(view.buffer, view.byteOffset, view.byteLength), at);
    return this;
  }

  /** The bytes written, as a buffer of their own. */
  finish(): ArrayBuffer {
    return this.#bytes.slice(0, this.#at).buffer;
  }
}
