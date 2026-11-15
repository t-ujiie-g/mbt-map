import assert from "node:assert/strict";
import test from "node:test";
import { normalize, staleFiles } from "../moonbit/gen-style.mjs";

test("the MoonBit API's generated style functions match the pinned style specification", async () => {
  assert.deepEqual(await staleFiles(), [], "run `node moonbit/gen-style.mjs` in bench/, then `moon fmt`");
});

test("normalize leaves out layout only", () => {
  assert.equal(normalize("f(\n  a,\n  b,\n)"), normalize("f(a, b)"));
  assert.notEqual(normalize("f(a, b)"), normalize("f(b, a)"));
});
