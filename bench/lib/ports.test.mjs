import assert from "node:assert/strict";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import path from "node:path";
import test from "node:test";
import { ROOT } from "./root.mjs";

const read = (...p) => readFileSync(path.join(ROOT, ...p), "utf8");

test("each port is a workspace module the engine imports at its version, with a README, LICENSE and NOTICE", () => {
  const ports = readdirSync(path.join(ROOT, "ports"));
  assert.ok(ports.length > 0);
  for (const name of ports) {
    const mod = read("ports", name, "moon.mod");
    assert.match(mod, new RegExp(`^name = "t-ujiie-g/${name}"$`, "m"), name);
    const version = /^version = "([^"]+)"$/m.exec(mod)?.[1];
    assert.ok(read("moon.mod").includes(`"t-ujiie-g/${name}@${version}"`), `moon.mod imports ${name}@${version}`);
    assert.ok(read("moon.work").includes(`"./ports/${name}"`), `moon.work lists ${name}`);
    for (const f of ["README.md", "LICENSE", "NOTICE"]) assert.ok(existsSync(path.join(ROOT, "ports", name, f)), `${name}/${f}`);
    assert.doesNotMatch(mod + read("ports", name, "moon.pkg"), /mbtmap_engine/, `${name} imports nothing of the engine`);
  }
});
