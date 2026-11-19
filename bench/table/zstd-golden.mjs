// zstd.wasm vs Node's zlib (libzstd) on seeded data: what libzstd compresses at several levels must inflate
// to the same bytes, and damaged input must be refused without a trap.
// Usage: node table/zstd-golden.mjs [--cases=N]; writes bench/results/zstd-golden.json.
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import zlib from "node:zlib";
import { ROOT } from "../lib/root.mjs";
import { arg } from "../lib/args.mjs";

const CASES = Number(arg("cases", 60));
const w = (await WebAssembly.instantiate(await readFile(path.join(ROOT, "_build/wasm-gc/release/build/t-ujiie-g/mbtmap_engine/zstd_worker/zstd_worker.wasm")), {})).instance.exports;
// The frames `bytes` inflated to at most `limit` bytes, or null where the module refuses them.
function inflate(bytes, limit = 2 ** 30) {
  const at = w.prepare_input(bytes.length);
  new Uint8Array(w.memory.buffer, at, bytes.length).set(bytes);
  const n = w.inflate(limit);
  return n < 0 ? null : new Uint8Array(w.memory.buffer.slice(w.output_addr(), w.output_addr() + n));
}

// Seeded xorshift32, so that every run compares the same data.
let seed = 0x7e11a9;
function random() {
  seed ^= seed << 13;
  seed ^= seed >>> 17;
  seed ^= seed << 5;
  return (seed >>> 0) / 4294967296;
}
const int = (n) => Math.floor(random() * n);
const pick = (xs) => xs[int(xs.length)];
const WORDS = ["park", "school", "東京", "station", "0.0001", "geometry", " ", "\n", "{\"type\":\"Feature\"}", "aaaaaaaa"];
// Data of several kinds: noise, runs, text, numbers that repeat far back, and mixes of them.
const MAKERS = {
  noise: (n) => Uint8Array.from({ length: n }, () => int(256)),
  run: (n) => new Uint8Array(n).fill(int(256)),
  text: (n) => new TextEncoder().encode(Array.from({ length: Math.ceil(n / 5) }, () => pick(WORDS)).join("")).subarray(0, n),
  few: (n) => Uint8Array.from({ length: n }, () => pick([0, 0, 0, 1, 2, 255])),
  doubles: (n) => new Uint8Array(Float64Array.from({ length: Math.ceil(n / 8) }, (_, i) => 139 + (i % 97) * 1e-4 + int(3) * 1e-7).buffer).subarray(0, n),
  far: (n) => {
    const block = Uint8Array.from({ length: Math.min(n, 5000) }, () => int(256));
    return Uint8Array.from({ length: n }, (_, i) => block[i % block.length] ^ (i % 70000 === 0 ? 1 : 0));
  },
};
const results = {};
const failures = [];
function check(group, label, want, got) {
  const r = (results[group] ??= { cases: 0, differ: 0 });
  r.cases++;
  if (want === got) return;
  r.differ++;
  if (failures.length < 12) failures.push({ group, label, want: String(want).slice(0, 120), got: String(got).slice(0, 120) });
}
const same = (a, b) => a !== null && a.length === b.length && Buffer.compare(Buffer.from(a.buffer, a.byteOffset, a.length), Buffer.from(b.buffer, b.byteOffset, b.length)) === 0;
const compress = (data, level, extra = {}) => new Uint8Array(zlib.zstdCompressSync(data, { params: { [zlib.constants.ZSTD_c_compressionLevel]: level, ...extra } }));

for (let k = 0; k < CASES; k++) {
  const kind = Object.keys(MAKERS)[k % Object.keys(MAKERS).length];
  const size = pick([0, 1, 2, 17, 300, 5000, 70000, 140000, 400000, 3000000]);
  const data = MAKERS[kind](size);
  for (const level of [-5, 1, 3, 9, 19]) {
    for (const extra of [{}, { [zlib.constants.ZSTD_c_checksumFlag]: 1 }, { [zlib.constants.ZSTD_c_contentSizeFlag]: 0, [zlib.constants.ZSTD_c_windowLog]: 12 }]) {
      const packed = compress(data, level, extra);
      check("inflate", `${kind} ${size} bytes, level ${level} ${JSON.stringify(extra)}`, "true", String(same(inflate(packed), data)));
    }
  }
}
// Frames one after another, a skippable frame between them, and a limit.
const first = MAKERS.text(4000);
const second = MAKERS.doubles(9000);
const skippable = Uint8Array.of(0x53, 0x2a, 0x4d, 0x18, 3, 0, 0, 0, 9, 9, 9);
const joined = Buffer.concat([compress(first, 3), skippable, compress(second, 19)]);
check("frames", "two frames and a skippable one", "true", String(same(inflate(joined), Buffer.concat([first, second]))));
check("frames", "nothing", "true", String(same(inflate(new Uint8Array(0)), new Uint8Array(0))));
check("frames", "a limit of the size", "true", String(same(inflate(joined, 13000), Buffer.concat([first, second]))));
check("frames", "a limit below the size", "null", String(inflate(joined, 12999)));
check("frames", "a dictionary id", "null", String(inflate(Uint8Array.of(0x28, 0xb5, 0x2f, 0xfd, 0x21, 7, 0, 1, 0, 0))));
check("frames", "another magic", "null", String(inflate(Uint8Array.of(1, 2, 3, 4, 5, 6, 7, 8))));

// Damaged input: cut anywhere or with bytes changed, it is refused or inflated, never a trap.
function survives(bytes) {
  try {
    inflate(bytes, 2 ** 24);
    return true;
  } catch {
    return false;
  }
}
for (const [name, data, level] of [["text", MAKERS.text(60000), 19], ["doubles", MAKERS.doubles(60000), 3], ["few", MAKERS.few(200000), 9], ["far", MAKERS.far(150000), 1]]) {
  const bytes = compress(data, level);
  let trapped = 0;
  for (let cut = 0; cut < bytes.length; cut += 1 + int(Math.ceil(bytes.length / 400))) if (!survives(bytes.subarray(0, cut))) trapped++;
  check("damaged", `${name} cut short`, 0, trapped);
  trapped = 0;
  for (let i = 0; i < 3000; i++) {
    const damaged = bytes.slice();
    // Half of the changes near the start, where the tables are.
    const span = i % 2 ? damaged.length : Math.min(damaged.length, 400);
    for (let m = 1 + int(3); m > 0; m--) damaged[int(span)] = pick([0, 1, 0x7f, 0x80, 0xff, int(256)]);
    if (!survives(damaged)) trapped++;
  }
  check("damaged", `${name} bytes changed`, 0, trapped);
}

console.table(Object.entries(results).map(([group, r]) => ({ group, cases: r.cases, differ: r.differ })));
if (failures.length) console.log(JSON.stringify(failures, null, 1));
await writeFile(path.join(ROOT, "bench/results/zstd-golden.json"), `${JSON.stringify({ node: process.version, zstd: process.versions.zstd, cases: CASES, results }, null, 2)}\n`);
const differ = Object.values(results).reduce((sum, r) => sum + r.differ, 0);
console.log(differ === 0 ? "0 differ" : `${differ} differ`);
process.exit(differ === 0 ? 0 : 1);
