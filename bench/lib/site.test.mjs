import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, readdirSync, readFileSync, existsSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { anchors, siteLink, slug, REPOSITORY } from "../site/links.mjs";
import { deadLinks } from "../site/dead-links.mjs";
import { ROOT } from "./root.mjs";

test("slug follows GitHub's heading anchors", () => {
  assert.equal(slug("How files are loaded"), "how-files-are-loaded");
  assert.equal(slug("Drawing and geodesics (`mbt-map/draw`)"), "drawing-and-geodesics-mbt-mapdraw");
  const a = anchors();
  assert.deepEqual([a("Options"), a("Options"), a("Other")], ["options", "options-1", "other"]);
});

test("siteLink keeps docs and published examples on the site and sends the rest to GitHub", () => {
  assert.equal(siteLink("./map.md#events", "docs/getting-started.md", "docs/getting-started.html"), "map.html#events");
  assert.equal(siteLink("./README.md", "docs/map.md", "docs/map.html"), "index.html");
  assert.equal(siteLink("../examples/", "docs/getting-started.md", "docs/getting-started.html"), "../examples/");
  assert.equal(siteLink("../examples/rabbita/", "docs/moonbit.md", "docs/moonbit.html"), "../examples/rabbita/");
  assert.equal(siteLink("../examples/react/build.mjs", "docs/getting-started.md", "docs/getting-started.html"), `${REPOSITORY}/blob/main/examples/react/build.mjs`);
  assert.equal(siteLink("./dev/", "docs/README.md", "docs/index.html"), `${REPOSITORY}/tree/main/docs/dev/`);
  assert.equal(siteLink("https://example.com/a.md", "docs/map.md", "docs/map.html"), "https://example.com/a.md");
  assert.equal(siteLink("#events", "docs/map.md", "docs/map.html"), "#events");
});

test("the user documentation's relative links and anchors resolve", () => {
  const dir = path.join(ROOT, "docs");
  const headings = (file) => {
    const a = anchors();
    const text = readFileSync(file, "utf8").replace(/```[\s\S]*?```/g, "");
    return new Set([...text.matchAll(/^#+ (.*)$/gm)].map((m) => a(m[1])));
  };
  const bad = [];
  for (const f of readdirSync(dir).filter((f) => f.endsWith(".md"))) {
    const file = path.join(dir, f);
    const text = readFileSync(file, "utf8").replace(/```[\s\S]*?```/g, "");
    for (const [, link] of text.matchAll(/\]\(([^)\s]+)\)/g)) {
      if (/^[a-z][a-z0-9+.-]*:/i.test(link)) continue;
      const [p, hash] = link.split("#");
      const target = p ? path.resolve(dir, p) : file;
      if (!existsSync(target)) bad.push(`${f}: ${link}`);
      else if (hash && target.endsWith(".md") && !headings(target).has(hash)) bad.push(`${f}: ${link}`);
    }
  }
  assert.deepEqual(bad, []);
});

test("highlight colors code blocks by their language, MoonBit included, and leaves others alone", async () => {
  const { highlight } = await import("../site/highlight.mjs");
  const js = highlight('<pre><code class="language-js">const a = &quot;x&quot;;</code></pre>');
  assert.match(js, /<code class="hljs language-js"><span class="hljs-keyword">const<\/span> a = <span class="hljs-string">&quot;x&quot;<\/span>;<\/code>/);
  const mbt = highlight('<pre><code class="language-moonbit">let m = @mbtmap.lnglat(1.0, 2.0) // here</code></pre>');
  assert.match(mbt, /<span class="hljs-keyword">let<\/span>/);
  assert.match(mbt, /<span class="hljs-symbol">@mbtmap<\/span>/);
  assert.match(mbt, /<span class="hljs-comment">\/\/ here<\/span>/);
  const plain = '<pre><code class="language-text">a &lt; b</code></pre>';
  assert.equal(highlight(plain), plain);
});

test("deadLinks lists a built site's links to missing files, folders without an index and missing ids", () => {
  const dir = mkdtempSync(path.join(os.tmpdir(), "site-"));
  try {
    mkdirSync(path.join(dir, "docs"));
    mkdirSync(path.join(dir, "examples/html"), { recursive: true });
    mkdirSync(path.join(dir, "examples/empty"));
    writeFileSync(path.join(dir, "site.css"), "");
    writeFileSync(path.join(dir, "examples/html/index.html"), '<html lang="en" data-variants="html,element">');
    writeFileSync(path.join(dir, "docs/map.html"), '<h2 id="events">Events</h2><a href="#events">ok</a><a href="#none">dead</a>');
    writeFileSync(
      path.join(dir, "index.html"),
      '<link rel="stylesheet" href="./site.css"><a href="./docs/map.html#events">ok</a><a href="./examples/html/?local=1">ok</a>' +
        '<a href="https://example.com/x">ok</a><a href="./docs/map.html#gone">dead</a><a href="./examples/element/">dead</a>' +
        '<a href="./examples/empty/">dead</a><script src="./missing.js"></script><pre><code>&lt;a href="./shown.html"&gt;</code><a href="./in-code.html">x</a></pre>',
    );
    assert.deepEqual(deadLinks(dir).sort(), [
      "docs/map.html: #none",
      "examples/html/index.html: ../element/",
      "index.html: ./docs/map.html#gone",
      "index.html: ./examples/element/",
      "index.html: ./examples/empty/",
      "index.html: ./missing.js",
    ]);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
