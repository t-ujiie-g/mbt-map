import path from "node:path";

const SPECIFIERS = [/\bfrom\s*"(\.{1,2}\/[^"]+)"/g, /\bimport\s*\(?\s*"(\.{1,2}\/[^"]+)"/g, /<reference\s+path="([^"]+)"/g];

/**
 * The declaration files `entries` reach through relative imports, exports and references, sorted.
 * Paths are relative to the package's dist, with forward slashes; `read(file)` gives a file's text,
 * or undefined when there is none, which is an error: a declaration that stays must resolve.
 */
export function reachableDeclarations(entries, read) {
  const seen = new Set();
  const queue = [...entries];
  while (queue.length > 0) {
    const file = queue.pop();
    if (seen.has(file)) continue;
    const text = read(file);
    if (text === undefined) throw new Error(`declaration ${file} is missing`);
    seen.add(file);
    for (const re of SPECIFIERS) {
      for (const [, spec] of text.matchAll(re)) {
        const target = path.posix.normalize(path.posix.join(path.posix.dirname(file), spec));
        if (target.startsWith("../")) throw new Error(`${file} imports ${spec}, outside dist`);
        queue.push(target.endsWith(".d.ts") ? target : target.replace(/\.js$/, "") + ".d.ts");
      }
    }
  }
  return [...seen].sort();
}

/** The `types` files of a package.json, relative to `dist/`. */
export function typeEntries(pkg) {
  const types = [pkg.types, ...Object.values(pkg.exports ?? {}).map((e) => e?.types)];
  return [...new Set(types.filter((t) => typeof t === "string").map((t) => path.posix.relative("dist", path.posix.normalize(t))))];
}
