import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { hostText } from "../../wasmio/js/host.mjs";

const MAX_PACKED_BYTES = 64 * 1024 * 1024;
const PAGE = 65536;

// The display worker's wasm as `npm run build` writes it, instantiated as worker.mjs does.
async function worker() {
  const bytes = await readFile(new URL("../../npm/dist/mbt-map.wasm", import.meta.url)).catch(() => assert.fail("npm/dist/mbt-map.wasm is missing: run `npm run build` in npm/ first"));
  const { instance } = await WebAssembly.instantiate(bytes, { host: hostText(), Math });
  return instance.exports;
}

function message(wasm, n) {
  assert.ok(n < 0, `expected an error, got ${n}`);
  return new TextDecoder().decode(new Uint8Array(wasm.memory.buffer, wasm.output_addr(), -n));
}

function withInput(wasm, bytes) {
  const addr = wasm.prepare_input(bytes.length);
  new Uint8Array(wasm.memory.buffer, addr, bytes.length).set(bytes);
}

test("prepare_input refuses lengths out of range and grows memory to hold the input", async () => {
  const wasm = await worker();
  for (const bad of [-1, MAX_PACKED_BYTES + 1, 0x7fffffff, -0x80000000]) assert.equal(wasm.prepare_input(bad), -1);
  assert.equal(wasm.prepare_input(5), PAGE);
  assert.equal(wasm.output_addr(), PAGE + 8);
  const large = 3 * PAGE + 1;
  assert.equal(wasm.prepare_input(large), PAGE);
  assert.ok(wasm.memory.buffer.byteLength >= PAGE + large);
  assert.equal(wasm.prepare_input(MAX_PACKED_BYTES), PAGE);
  assert.ok(wasm.memory.buffer.byteLength >= PAGE + MAX_PACKED_BYTES);
});

test("every export answers with a message before a style is set", async () => {
  const wasm = await worker();
  withInput(wasm, new Uint8Array(7).fill(0xff));
  assert.equal(message(wasm, wasm.process_tile(0, 0, 0, 0, 0)), "style not initialized");
  assert.equal(message(wasm, wasm.process_dem(0, 0, 256)), "style not initialized");
  assert.equal(message(wasm, wasm.query_tile(0, 0, 7, 0, 0)), "style not initialized");
  assert.equal(message(wasm, wasm.source_features(0, 0, 7, 0, 0)), "style not initialized");
  assert.equal(wasm.output_addr(), PAGE + 8);
});

test("init_style refuses bytes that are no compiled style, without trapping", async () => {
  const wasm = await worker();
  let seed = 7;
  const rand = () => (seed = (Math.imul(seed, 1103515245) + 12345) >>> 0) / 4294967296;
  for (const length of [0, 1, 3, 4, 64, 1000]) {
    for (const fill of [() => 0, () => 0xff, () => Math.floor(rand() * 256)]) {
      withInput(wasm, Uint8Array.from({ length }, fill));
      assert.notEqual(message(wasm, wasm.init_style()), "");
    }
  }
  withInput(wasm, new Uint8Array(4));
  assert.equal(message(wasm, wasm.process_tile(0, 0, 0, 0, 0)), "style not initialized");
});
