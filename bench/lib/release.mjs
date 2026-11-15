// Checks that a release tag (vX.Y.Z) agrees with what it publishes: npm/package.json, the MoonBit API modules
// (moonbit/mbtmap, moonbit/mbtmap_rabbita and its dependency on mbtmap) and a CHANGELOG.md section.
// Usage: node lib/release.mjs vX.Y.Z (from bench/); exits 1 and lists the problems otherwise.
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { ROOT } from "./root.mjs";

/** The problems of releasing `tag` given the files' texts (`read(path)`, paths from the repository root). */
export function releaseProblems(tag, read) {
  const problems = [];
  const m = /^v(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)$/.exec(tag);
  if (!m) return [`tag ${tag} is not vX.Y.Z`];
  const version = m[1];
  const npm = JSON.parse(read("npm/package.json")).version;
  if (npm !== version) problems.push(`npm/package.json is ${npm}`);
  for (const mod of ["moonbit/mbtmap/moon.mod", "moonbit/mbtmap_rabbita/moon.mod"]) {
    const v = /^version = "([^"]+)"/m.exec(read(mod))?.[1];
    if (v !== version) problems.push(`${mod} is ${v}`);
  }
  const dep = /"t-ujiie-g\/mbtmap@([^"]+)"/.exec(read("moonbit/mbtmap_rabbita/moon.mod"))?.[1];
  if (dep !== version) problems.push(`moonbit/mbtmap_rabbita imports mbtmap@${dep}`);
  if (!new RegExp(`^## ${version.replace(/\./g, "\\.")}\\b`, "m").test(read("CHANGELOG.md"))) problems.push(`CHANGELOG.md has no "## ${version}" section`);
  return problems;
}

/** The CHANGELOG.md section of `version`, without its heading (the GitHub release's notes). */
export function releaseNotes(changelog, version) {
  const start = changelog.search(new RegExp(`^## ${version.replace(/\./g, "\\.")}\\b.*$`, "m"));
  if (start < 0) return "";
  const body = changelog.slice(changelog.indexOf("\n", start) + 1);
  const end = body.search(/^## /m);
  return (end < 0 ? body : body.slice(0, end)).trim() + "\n";
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  const [tag, notes] = process.argv.slice(2);
  const read = (p) => readFileSync(path.join(ROOT, p), "utf8");
  if (notes === "--notes") {
    process.stdout.write(releaseNotes(read("CHANGELOG.md"), tag.replace(/^v/, "")));
  } else {
    const problems = releaseProblems(tag ?? "", read);
    for (const p of problems) console.error(`release ${tag}: ${p}`);
    if (problems.length) process.exit(1);
    console.log(`release ${tag}: versions and changelog agree`);
  }
}
