import assert from "node:assert/strict";
import test from "node:test";
import { filterText } from "../src/engine-style.ts";

test("filterText: empty for no filter, JSON otherwise, legacy filters converted only when a converter is given", () => {
  const isLegacy = (f: unknown) => Array.isArray(f) && f[0] === "==" && typeof f[1] === "string";
  assert.equal(filterText(undefined, null, isLegacy), "");
  assert.equal(filterText(["==", ["get", "a"], 1], null, isLegacy), '["==",["get","a"],1]');
  const legacy = ["==", "a", 1];
  assert.equal(filterText(legacy, null, isLegacy), '["==","a",1]');
  assert.equal(filterText(legacy, () => ["converted"], isLegacy), '["converted"]');
  assert.equal(filterText(["==", ["get", "a"], 1], () => ["converted"], isLegacy), '["==",["get","a"],1]');
});
