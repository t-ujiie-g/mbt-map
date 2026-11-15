// Builds the GitHub Pages site into _site/: the hand-written home page of site/, docs/*.md as HTML (marked),
// the package's files once under lib/, the sample gallery (examples/samples: each sample's page with its
// code) and the example apps on that copy.
// Usage: node site/build.mjs [--no-prepare] (from bench/; --no-prepare reuses examples packed already).
import { cp, mkdir, readdir, readFile, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { Marked } from "marked";
import { ROOT } from "../lib/root.mjs";
import { prepareExamples } from "../npm/prepare.mjs";
import { anchors, REPOSITORY, SITE_EXAMPLES, siteLink } from "./links.mjs";
import { highlight } from "./highlight.mjs";

const OUT = path.join(ROOT, "_site");
/** Files of an example folder the site leaves out: sources, build scripts, packages. */
const SKIP = new Set(["node_modules", "src", "main", "package.json", "package-lock.json", "build.mjs", "moon.mod", "README.md"]);

/** The example apps the gallery lists after the samples: folder, title, what it shows. */
const APPS = [
  ["html", "Showcase", "Search, layers, drawing, measurement, analysis, data and web services in one app."],
  ["plateau", "PLATEAU 3D city", "Tokyo's Chiyoda ward as 3D Tiles: attributes on click, measurement, lines of sight, viewsheds, clipping."],
  ["react", "Showcase in React", "The showcase written with React 19 and the <mbt-map> element."],
  ["rabbita", "MoonBit app (rabbita)", "A web app written in MoonBit with rabbita, its map events as messages."],
];

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

/** A site page around `main`: the header (with the theme button) and footer, paths relative to `root`. */
function page({ title, root, main, description = "" }) {
  const meta = description ? `\n<meta name="description" content="${escape(description)}">` : "";
  return `<!doctype html>
<html lang="en">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escape(title)} · mbt-map</title>${meta}
<link rel="icon" href="${root}icon.svg">
<link rel="stylesheet" href="${root}site.css">
<script src="${root}theme.js"></script>
<header class="top">
  <a class="brand" href="${root}">mbt-map</a>
  <nav><a href="${root}docs/">Docs</a><a href="${root}examples/">Examples</a><a href="${REPOSITORY}">GitHub</a><button class="theme" type="button" aria-label="Switch the color theme">☾</button></nav>
</header>
${main}
<footer class="foot">Apache License 2.0 · <a href="${REPOSITORY}">${REPOSITORY.replace("https://", "")}</a></footer>
</html>
`;
}

function docPage({ title, body, sidebar }) {
  return page({ title, root: "../", main: `<div class="doc">\n  <nav class="side" aria-label="Documentation">${sidebar}</nav>\n  <main class="content">${body}</main>\n</div>` });
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
    await writeFile(path.join(OUT, page), highlight(docPage({ title, body, sidebar })));
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

/** The title and description a sample's index.html declares. */
function sampleInfo(html, id) {
  const title = /<title>([^<]*)<\/title>/.exec(html)?.[1] ?? id;
  const description = /<meta name="description" content="([^"]*)">/.exec(html)?.[1] ?? "";
  return { title, description };
}

function card(href, title, description, tag) {
  return `<a class="card" href="${href}"><h3>${escape(title)}</h3><p>${escape(description)}</p><code>${escape(tag)}</code></a>`;
}

async function buildExamples() {
  const dir = path.join(ROOT, "examples");
  const out = path.join(OUT, "examples");
  await mkdir(out, { recursive: true });
  await cp(path.join(dir, "shared"), path.join(out, "shared"), { recursive: true });
  for (const name of SITE_EXAMPLES) await copyExample(path.join(dir, name), path.join(out, name));
  // Samples: each runs at examples/samples/<id>/, and examples/<id>.html shows it with its code.
  const samples = JSON.parse(await readFile(path.join(dir, "samples/index.json"), "utf8"));
  await mkdir(path.join(out, "samples"), { recursive: true });
  await cp(path.join(dir, "samples/sample.css"), path.join(out, "samples/sample.css"));
  const groups = new Map();
  for (const { id, group } of samples) {
    const src = path.join(dir, "samples", id);
    const html = await readFile(path.join(src, "index.html"), "utf8");
    const code = await readFile(path.join(src, "main.js"), "utf8");
    const { title, description } = sampleInfo(html, id);
    await mkdir(path.join(out, "samples", id), { recursive: true });
    for (const f of await readdir(src)) {
      const text = await readFile(path.join(src, f));
      await writeFile(path.join(out, "samples", id, f), f.endsWith(".html") ? text.toString().replaceAll("../node_modules/mbt-map/dist/", "../../../lib/") : text);
    }
    const imports = [...new Set([...code.matchAll(/(?:from|import) "(mbt-map[^"]*)"/g)].map((m) => m[1]))].join(" · ");
    if (!groups.has(group)) groups.set(group, []);
    groups.get(group).push(card(`./${id}.html`, title, description, imports));
    const markup = html.replace(/<script type="importmap">[\s\S]*?<\/script>\n/, "");
    const main = `<main class="wrap">
  <p class="crumbs"><a href="./">Examples</a> / ${escape(group)}</p>
  <div class="sample-head">
    <div><h1>${escape(title)}</h1><p>${escape(description)}</p></div>
    <div class="sample-links"><a href="./samples/${id}/">Open full page</a><a href="${REPOSITORY}/tree/main/examples/samples/${id}">Source on GitHub</a></div>
  </div>
  <iframe class="sample-frame" src="./samples/${id}/" title="${escape(title)}" loading="lazy"></iframe>
  <div class="sample-code">
    <h2>main.js</h2>
    <pre><code class="language-js">${escape(code)}</code></pre>
    <h2>index.html</h2>
    <pre><code class="language-html">${escape(markup)}</code></pre>
  </div>
</main>`;
    await writeFile(path.join(out, `${id}.html`), highlight(page({ title, root: "../", main, description })));
  }
  const sections = [...groups].map(([group, cards]) => `<section class="gallery-group"><h2>${escape(group)}</h2><div class="grid">${cards.join("")}</div></section>`);
  const apps = APPS.map(([name, title, description]) => card(`./${name}/`, title, description, `examples/${name}`));
  const index = `<main class="wrap">
  <div class="sample-head"><div><h1>Examples</h1><p>Small samples, each one thing with its whole code, and complete apps. They read GSI's (国土地理院) tiles, OpenFreeMap and PLATEAU live.</p></div></div>
  ${sections.join("\n  ")}
  <section class="gallery-group"><h2>Apps</h2><div class="grid">${apps.join("")}</div></section>
</main>`;
  await writeFile(path.join(out, "index.html"), page({ title: "Examples", root: "../", main: index }));
  return samples.length;
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
for (const page of ["index.html"]) await writeFile(path.join(OUT, page), highlight(await readFile(path.join(OUT, page), "utf8")));
await buildLib();
const samples = await buildExamples();
const pages = await buildDocs();
console.log(`site: ${pages} docs pages, ${samples} samples, ${SITE_EXAMPLES.length} apps in ${path.relative(ROOT, OUT)}/`);
