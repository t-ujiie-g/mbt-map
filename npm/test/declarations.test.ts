import assert from "node:assert/strict";
import test from "node:test";
import { reachableDeclarations, typeEntries } from "../scripts/declarations.mjs";

const reader = (files: Record<string, string>) => (file: string) => files[file];

test("declarations are followed through imports, re-exports, import types and references", () => {
  const files = {
    "index.d.ts": 'import type { A } from "./a.js";\nexport * from "./ui/b.js";\nexport declare const c: import("./c.js").C;',
    "a.d.ts": '/// <reference path="./globals.d.ts" />\nexport interface A {}',
    "ui/b.d.ts": 'export { D } from "../d.js";\nimport "./side.js";',
    "ui/side.d.ts": "export {};",
    "c.d.ts": "export interface C {}",
    "d.d.ts": 'import { A } from "./a.js";\nexport declare class D implements A {}',
    "globals.d.ts": "declare const g: number;",
    "internal.d.ts": 'export * from "./a.js";',
  };
  assert.deepEqual(reachableDeclarations(["index.d.ts"], reader(files)), ["a.d.ts", "c.d.ts", "d.d.ts", "globals.d.ts", "index.d.ts", "ui/b.d.ts", "ui/side.d.ts"]);
  assert.deepEqual(reachableDeclarations(["c.d.ts", "internal.d.ts"], reader(files)), ["a.d.ts", "c.d.ts", "globals.d.ts", "internal.d.ts"]);
});

test("bare specifiers are left alone and cycles end", () => {
  const files = { "a.d.ts": 'import "react";\nexport * from "./b.js";', "b.d.ts": 'export * from "./a.js";' };
  assert.deepEqual(reachableDeclarations(["a.d.ts"], reader(files)), ["a.d.ts", "b.d.ts"]);
});

test("a missing declaration or one outside dist is an error", () => {
  assert.throws(() => reachableDeclarations(["a.d.ts"], reader({ "a.d.ts": 'export * from "./gone.js";' })), /gone\.d\.ts is missing/);
  assert.throws(() => reachableDeclarations(["a.d.ts"], reader({ "a.d.ts": 'export * from "../../x.js";' })), /outside dist/);
  assert.throws(() => reachableDeclarations(["entry.d.ts"], reader({})), /entry\.d\.ts is missing/);
});

test("type entries come from types and the exports' types", () => {
  const pkg = { types: "./dist/index.d.ts", exports: { ".": { types: "./dist/index.d.ts", default: "./dist/index.js" }, "./ui": { types: "./dist/ui.d.ts" }, "./worker.js": "./dist/worker.js" } };
  assert.deepEqual(typeEntries(pkg), ["index.d.ts", "ui.d.ts"]);
});
