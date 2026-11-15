// Builds the GitHub Pages site into _site/: the hand-written home pages of site/ (English and Japanese),
// docs/*.md as HTML (marked), the package's files once under lib/, and the examples on that copy.
// Usage: node site/build.mjs [--no-prepare] (from bench/; --no-prepare reuses examples packed already).
import { cp, mkdir, readdir, readFile, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { Marked } from "marked";
import { ROOT } from "../lib/root.mjs";
import { prepareExamples } from "../npm/prepare.mjs";
import { anchors, REPOSITORY, SITE_EXAMPLES, siteLink } from "./links.mjs";

const OUT = path.join(ROOT, "_site");
/** Files of an example folder the site leaves out: sources, build scripts, packages. */
const SKIP = new Set(["node_modules", "src", "main", "package.json", "package-lock.json", "build.mjs", "moon.mod", "README.md"]);

const escape = (s) => s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);

/** `markdown` of the repository file `from` as HTML for the site page `page`. */
function render(markdown, from, page) {
  const anchor = anchors();
  const marked = new Marked({
    renderer: {
      heading({ tokens, depth, text }) {
        return `<h${depth} id="${anchor(text)}">${this.parser.parseInline(tokens)}</h${depth}>\n`;
      },
      link({ href, title, tokens }) {
        const t = title ? ` title="${escape(title)}"` : "";
        return `<a href="${escape(siteLink(href, from, page))}"${t}>${this.parser.parseInline(tokens)}</a>`;
      },
    },
  });
  return marked.parse(markdown);
}

function docPage({ title, body, sidebar }) {
  return `<!doctype html>
<html lang="en">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escape(title)} · mbt-map</title>
<link rel="icon" href="../icon.svg">
<link rel="stylesheet" href="../site.css">
<header class="top">
  <a class="brand" href="../">mbt-map</a>
  <nav><a href="./">Docs</a><a href="../examples/">Examples</a><a href="${REPOSITORY}">GitHub</a></nav>
</header>
<div class="doc">
  <nav class="side" aria-label="Documentation">${sidebar}</nav>
  <main class="content">${body}</main>
</div>
<footer class="foot">Apache License 2.0 · <a href="${REPOSITORY}">${REPOSITORY.replace("https://", "")}</a></footer>
</html>
`;
}

async function buildDocs() {
  const dir = path.join(ROOT, "docs");
  const files = (await readdir(dir)).filter((f) => f.endsWith(".md"));
  const index = await readFile(path.join(dir, "README.md"), "utf8");
  // The index without its descriptions: each item's link alone.
  const titles = index.replace(/^# .*\n/, '<a class="side-home" href="./">Documentation</a>\n').replace(/^(- \[[^\]]+\]\([^)]+\)):.*$/gm, "$1");
  const sidebar = render(titles, "docs/README.md", "docs/index.html").replace(/ id="[^"]*"/g, "");
  await mkdir(path.join(OUT, "docs"), { recursive: true });
  for (const f of files) {
    const name = f === "README.md" ? "index" : f.slice(0, -3);
    const page = `docs/${name}.html`;
    const markdown = await readFile(path.join(dir, f), "utf8");
    const title = /^# (.*)$/m.exec(markdown)?.[1].replace(/`/g, "") ?? name;
    const body = render(markdown, `docs/${f}`, page);
    await writeFile(path.join(OUT, page), docPage({ title, body, sidebar }));
  }
  return files.length;
}

/** Copies example folder `src` to `dest` without its sources, pointing its import map at the shared lib/. */
async function copyExample(src, dest) {
  await mkdir(dest, { recursive: true });
  for (const entry of await readdir(src, { withFileTypes: true })) {
    if (SKIP.has(entry.name) || entry.name.endsWith(".mbt")) continue;
    const from = path.join(src, entry.name);
    const to = path.join(dest, entry.name);
    if (entry.isDirectory()) await cp(from, to, { recursive: true });
    else if (entry.name.endsWith(".html")) {
      const html = await readFile(from, "utf8");
      await writeFile(to, html.replaceAll("./node_modules/mbt-map/dist/", "../../lib/"));
    } else await cp(from, to);
  }
}

async function buildExamples() {
  const dir = path.join(ROOT, "examples");
  const out = path.join(OUT, "examples");
  await mkdir(out, { recursive: true });
  await cp(path.join(dir, "index.html"), path.join(out, "index.html"));
  await cp(path.join(dir, "shared"), path.join(out, "shared"), { recursive: true });
  for (const name of SITE_EXAMPLES) await copyExample(path.join(dir, name), path.join(out, name));
}

/** The package's modules, workers and wasm (no type declarations), once for every page. */
async function buildLib() {
  const dist = path.join(ROOT, "npm/dist");
  const out = path.join(OUT, "lib");
  await mkdir(out, { recursive: true });
  for (const f of await readdir(dist)) if (/\.(js|wasm)$/.test(f)) await cp(path.join(dist, f), path.join(out, f));
}

if (!process.argv.includes("--no-prepare")) await prepareExamples();
await rm(OUT, { recursive: true, force: true });
await cp(path.join(ROOT, "site"), OUT, { recursive: true });
await buildLib();
await buildExamples();
const pages = await buildDocs();
console.log(`site: ${pages} docs pages, ${SITE_EXAMPLES.length} examples in ${path.relative(ROOT, OUT)}/`);
