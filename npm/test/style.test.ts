import assert from "node:assert/strict";
import test from "node:test";
import { copy, invalidCustomLayer, loadedState } from "../src/style.ts";

test("invalidCustomLayer is MapLibre's validateCustomStyleLayer", () => {
  assert.equal(invalidCustomLayer({ id: "c", render() {} }), "");
  assert.equal(invalidCustomLayer({ render() {} }), 'missing required property "id"');
  assert.equal(invalidCustomLayer({ id: "c" }), 'missing required method "render"');
  assert.equal(invalidCustomLayer({ id: "c", render() {}, renderingMode: "4d" }), 'property "renderingMode" must be either "2d" or "3d"');
});

test("loadedState takes initial values over the style's defaults and keeps other keys", () => {
  assert.deepEqual(loadedState({ a: 5, x: true }, { a: { default: 1 }, b: {}, c: { default: [2] } }, { c: "init", d: 0 }), { a: 1, b: null, c: "init", d: 0, x: true });
  assert.deepEqual(loadedState({}, undefined, {}), {});
});

test("copy is a plain JSON copy, undefined kept", () => {
  const o = { a: [1, { b: 2 }] };
  const c = copy(o);
  assert.deepEqual(c, o);
  assert.notEqual(c.a, o.a);
  assert.equal(copy(undefined), undefined);
});
