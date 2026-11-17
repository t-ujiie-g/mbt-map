import assert from "node:assert/strict";
import test from "node:test";
import { Packer } from "../src/pack.ts";

const bytes = (p: Packer) => Array.from(new Uint8Array(p.finish()));
const f64 = (v: number) => Array.from(new Uint8Array(new Float64Array([v]).buffer));

test("json packs each kind of JSON value by its tag", () => {
  assert.deepEqual(bytes(new Packer().json(null).json(false).json(true)), [0, 1, 2]);
  assert.deepEqual(bytes(new Packer().json(1.5)), [3, ...f64(1.5)]);
  assert.deepEqual(bytes(new Packer().json("é")), [4, 2, 0, 0, 0, 0xc3, 0xa9]);
  assert.deepEqual(bytes(new Packer().json(["get", "a"])), [5, 2, 0, 0, 0, 4, 3, 0, 0, 0, 103, 101, 116, 4, 1, 0, 0, 0, 97]);
  assert.deepEqual(bytes(new Packer().json({ a: [] })), [6, 1, 0, 0, 0, 1, 0, 0, 0, 97, 5, 0, 0, 0, 0]);
});

test("json refuses what JSON does not hold", () => {
  for (const v of [undefined, () => 1, new Date(0), new Float64Array(1), 1n]) assert.throws(() => new Packer().json(v), /not JSON/);
  assert.throws(() => new Packer().json(["get", undefined]), /not JSON/);
});

test("value packs property values: undefined is absent, NaN null, objects their JSON text", () => {
  assert.deepEqual(bytes(new Packer().value(undefined).value(null).value(NaN).value(false).value(true)), [5, 0, 0, 1, 2]);
  assert.deepEqual(bytes(new Packer().value(-2)), [3, ...f64(-2)]);
  assert.deepEqual(bytes(new Packer().value("a")), [4, 1, 0, 0, 0, 97]);
  assert.deepEqual(bytes(new Packer().value({ a: 1 })), [4, 7, 0, 0, 0, ...new TextEncoder().encode('{"a":1}')]);
  assert.deepEqual(bytes(new Packer().value(7n)), [4, 1, 0, 0, 0, 55]);
});

test("a packer grows past its first buffer", () => {
  const p = new Packer();
  for (let i = 0; i < 1000; i++) p.u32(i);
  const out = new Uint32Array(p.finish());
  assert.equal(out.length, 1000);
  assert.equal(out[999], 999);
  assert.deepEqual(bytes(new Packer().u8(7).utf8("x".repeat(300))).length, 305);
});
