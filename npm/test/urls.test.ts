import assert from "node:assert/strict";
import test from "node:test";
import { PMTILES, httpUrl, pmtilesArchive, resolveTemplate, wasmUrl, workerParts, workerScriptUrl } from "../src/urls.ts";

const OWN = new URL("https://example.com/lib/worker.js");

const base = new URL("https://example.com/styles/style.json");

test("tile templates resolve against the style and keep their placeholders", () => {
  assert.equal(resolveTemplate("tiles/{z}/{x}/{y}.pbf", base), "https://example.com/styles/tiles/{z}/{x}/{y}.pbf");
  assert.equal(resolveTemplate("/t/{z}/{x}/{y}.pbf", base), "https://example.com/t/{z}/{x}/{y}.pbf");
  assert.equal(resolveTemplate("https://cdn.test/{z}/{x}/{y}", base), "https://cdn.test/{z}/{x}/{y}");
  // Only the engine's placeholders are restored.
  assert.equal(resolveTemplate("t/{a}/{z}", base), "https://example.com/styles/t/%7Ba%7D/{z}");
  assert.equal(
    resolveTemplate("/{prefix}/{quadkey}{ratio}.png?bbox={bbox-epsg-3857}&b={bbox}", base),
    "https://example.com/{prefix}/{quadkey}{ratio}.png?bbox={bbox-epsg-3857}&b={bbox}",
  );
  assert.equal(resolveTemplate("/q/{quadkey}/{bbox-epsg-3857}", base), "https://example.com/q/{quadkey}/{bbox-epsg-3857}");
});

test("httpUrl resolves against the base and refuses other schemes", () => {
  assert.equal(httpUrl("sprite", base, "the sprite"), "https://example.com/styles/sprite");
  assert.equal(httpUrl("http://a.test/s.json", "https://b.test/", "the style"), "http://a.test/s.json");
  for (const bad of ["data:image/png;base64,AA==", "blob:https://example.com/x", "file:///etc/passwd", "javascript:1"]) {
    assert.throws(() => httpUrl(bad, base, "the sprite"), /the sprite must be an http\(s\) URL/);
  }
});

test("tile templates must be http(s), PMTiles archives too", () => {
  assert.equal(resolveTemplate("pmtiles://https://cdn.test/a.pmtiles/{z}/{x}/{y}", base), "pmtiles://https://cdn.test/a.pmtiles/{z}/{x}/{y}");
  assert.equal(resolveTemplate("pmtiles://a.pmtiles/{z}/{x}/{y}", base), "pmtiles://https://example.com/styles/a.pmtiles/{z}/{x}/{y}");
  for (const bad of ["data:application/x-protobuf;base64,AA==#{z}", "blob:https://example.com/{z}", "pmtiles://data:,x/{z}/{x}/{y}"]) {
    assert.throws(() => resolveTemplate(bad, base), /tiles must be an http\(s\) URL/);
  }
});

test("workers load only from same-origin http(s) URLs", () => {
  const origin = "https://example.com";
  assert.equal(workerScriptUrl("./worker.js", OWN, base, origin), "https://example.com/styles/worker.js");
  assert.equal(workerScriptUrl(new URL("https://example.com/w.js"), OWN, base, origin), "https://example.com/w.js");
  assert.equal(workerScriptUrl(undefined, OWN, base, origin), OWN.href);
  const bad = ["data:text/javascript,1", "blob:https://example.com/x", "https://evil.test/w.js", "javascript:1"];
  for (const url of [...bad, ...bad.map((b) => new URL(b))]) {
    assert.throws(() => workerScriptUrl(url, OWN, base, origin, "https://cdn.test/npm/mbt-map@0.1.0/dist/"), /on the page's origin or beside the library/);
  }
});

test("the library's own worker starts where a bundler put it: inlined from a blob of its text, another origin's through an importing blob", async () => {
  const origin = "https://example.com";
  const script = 'postMessage("é#1");';
  const plain = new URL(`data:text/javascript,${encodeURIComponent(script)}`);
  const base64 = new URL(`data:text/javascript;base64,${Buffer.from(script).toString("base64")}`);
  for (const inlined of [plain, base64]) {
    const url = workerScriptUrl(undefined, inlined, base, origin);
    assert.match(url, /^blob:/);
    assert.equal(await (await fetch(url)).text(), script);
    assert.equal(workerScriptUrl(undefined, inlined, base, origin), url);
  }
  const asset = "https://static.test/assets/worker-abc123.js";
  const url = workerScriptUrl(undefined, new URL(asset), base, origin, "file:///app/node_modules/mbt-map/dist/");
  assert.equal(await (await fetch(url)).text(), `import "${asset}";`);
  for (const bad of ["blob:https://example.com/x", "file:///w.js", "javascript:1"]) {
    assert.throws(() => workerScriptUrl(undefined, new URL(bad), base, origin), /the library's worker must be/);
  }
});

test("worker parts are sent only with the library's own worker", () => {
  const parts = { query: new URL("https://example.com/assets/worker-query-abc.js") };
  assert.deepEqual(workerParts(undefined, parts), { query: "https://example.com/assets/worker-query-abc.js" });
  assert.equal(workerParts("/static/worker.js", parts), undefined);
});

test("a worker beside the library on a CDN starts through a same-origin blob; other folders of the CDN are refused", async () => {
  const origin = "https://example.com";
  const home = "https://cdn.test/npm/mbt-map@0.1.0/dist/";
  const cdn = `${home}worker.js`;
  const url = workerScriptUrl(cdn, OWN, base, origin, home);
  assert.match(url, /^blob:/);
  assert.equal(await (await fetch(url)).text(), `import "${cdn}";`);
  assert.equal(workerScriptUrl(cdn, OWN, base, origin, home), url);
  for (const bad of ["https://cdn.test/npm/evil@1.0.0/worker.js", `${home}../../evil/worker.js`, "https://cdn.test.evil.example/npm/mbt-map@0.1.0/dist/worker.js"]) {
    assert.throws(() => workerScriptUrl(bad, OWN, base, origin, home), /beside the library/);
  }
});

test("wasm loads only from http(s) URLs", () => {
  assert.equal(wasmUrl("https://cdn.test/mbt-map.wasm", base), "https://cdn.test/mbt-map.wasm");
  for (const bad of ["data:application/wasm;base64,AA==", "file:///x.wasm"]) {
    assert.throws(() => wasmUrl(bad, base), /http\(s\)/);
  }
});

test("pmtilesArchive: the archive URL after the pmtiles:// prefix, null without it", () => {
  assert.equal(pmtilesArchive(PMTILES + "https://example.com/a.pmtiles"), "https://example.com/a.pmtiles");
  assert.equal(pmtilesArchive("https://example.com/a.pmtiles"), null);
});
