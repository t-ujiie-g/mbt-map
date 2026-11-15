// What the site build does to the documentation's Markdown: GitHub's heading anchors, and relative links
// turned into the site's pages or, for files the site does not carry, into the repository on GitHub.
import path from "node:path";

export const REPOSITORY = "https://github.com/t-ujiie-g/mbt-map";

/** The example apps the site publishes (their folders, under examples/); the samples come besides. */
export const SITE_EXAMPLES = ["html", "react", "plateau", "rabbita"];

/** GitHub's anchor for a heading's text (before numbering repeats). */
export const slug = (text) =>
  text
    .trim()
    .toLowerCase()
    .replace(/<[^>]*>/g, "")
    .replace(/[^\p{L}\p{N} _-]/gu, "")
    .replace(/ /g, "-");

/** A function giving each heading its anchor, numbering repeats as GitHub does (`a`, `a-1`, …). */
export function anchors() {
  const seen = new Map();
  return (text) => {
    const a = slug(text);
    const n = seen.get(a) ?? 0;
    seen.set(a, n + 1);
    return n ? `${a}-${n}` : a;
  };
}

/**
 * Where `href`, written in the repository file `from` (a path from the repository root), goes on the site,
 * given that the site's page for `from` is at `page` (from the site root): docs/*.md become docs/*.html
 * (README.md the index), published examples stay examples, anything else goes to GitHub.
 */
export function siteLink(href, from, page) {
  if (/^[a-z][a-z0-9+.-]*:/i.test(href) || href.startsWith("#")) return href;
  const [file, hash] = href.split("#");
  const target = path.posix.normalize(path.posix.join(path.posix.dirname(from), file));
  const suffix = hash ? `#${hash}` : "";
  let site = null;
  const doc = /^docs\/([^/]+)\.md$/.exec(target);
  if (doc) site = `docs/${doc[1] === "README" ? "index" : doc[1]}.html`;
  else if (target === "examples" || target === "examples/") site = "examples/";
  else {
    const ex = /^examples\/([^/]+)\/?$/.exec(target);
    if (ex && SITE_EXAMPLES.includes(ex[1])) site = `examples/${ex[1]}/`;
  }
  if (site === null) {
    const isDir = href.split("#")[0].endsWith("/");
    return `${REPOSITORY}/${isDir ? "tree" : "blob"}/main/${target.replace(/\/$/, "")}${isDir ? "/" : ""}${suffix}`;
  }
  const rel = path.posix.relative(path.posix.dirname(page), site) || ".";
  return `${rel}${site.endsWith("/") && !rel.endsWith("/") ? "/" : ""}${suffix}`;
}
