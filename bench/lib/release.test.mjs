import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";
import test from "node:test";
import { releaseNotes, releaseProblems } from "./release.mjs";
import { ROOT } from "./root.mjs";

const files = (version, dep = version, changelog = `# Changelog\n\n## ${version} (2026-11-20)\n\n- First.\n\n## 0.0.9\n\n- Old.\n`) => ({
  "npm/package.json": JSON.stringify({ version }),
  "moonbit/mbtmap/moon.mod": `name = "t-ujiie-g/mbtmap"\n\nversion = "${version}"\n`,
  "moonbit/mbtmap_rabbita/moon.mod": `version = "${version}"\n\nimport {\n  "t-ujiie-g/mbtmap@${dep}",\n}\n`,
  "CHANGELOG.md": changelog,
});

test("releaseProblems accepts a tag that every version and the changelog agree with", () => {
  const f = files("1.2.3");
  assert.deepEqual(releaseProblems("v1.2.3", (p) => f[p]), []);
});

test("releaseProblems names each disagreement", () => {
  const f = { ...files("1.2.3", "1.2.2", "# Changelog\n"), "npm/package.json": JSON.stringify({ version: "1.2.4" }) };
  assert.deepEqual(releaseProblems("v1.2.3", (p) => f[p]), [
    "npm/package.json is 1.2.4",
    "moonbit/mbtmap_rabbita imports mbtmap@1.2.2",
    'CHANGELOG.md has no "## 1.2.3" section',
  ]);
  assert.deepEqual(releaseProblems("1.2.3", (p) => f[p]), ["tag 1.2.3 is not vX.Y.Z"]);
});

test("releaseNotes takes one version's section of the changelog", () => {
  assert.equal(releaseNotes(files("1.2.3")["CHANGELOG.md"], "1.2.3"), "- First.\n");
  assert.equal(releaseNotes(files("1.2.3")["CHANGELOG.md"], "0.0.9"), "- Old.\n");
  assert.equal(releaseNotes("# Changelog\n", "1.0.0"), "");
});

test("the repository's versions agree with the npm package's", () => {
  const read = (p) => readFileSync(path.join(ROOT, p), "utf8");
  const version = JSON.parse(read("npm/package.json")).version;
  assert.deepEqual(releaseProblems(`v${version}`, read), []);
});
