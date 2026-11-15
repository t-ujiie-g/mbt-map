// The built site's internal links: every href and src of its pages must lead to a file of the site, and a
// link's fragment to an id of that page. Shown code (inside <pre>) is not a link.
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import path from "node:path";

function pages(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
    const file = path.join(dir, e.name);
    if (e.isDirectory()) return pages(file);
    return e.name.endsWith(".html") ? [file] : [];
  });
}

/** The site file a page's link leads to (a folder's index.html), or null when there is none. */
function target(page, link) {
  const file = link ? path.resolve(path.dirname(page), decodeURIComponent(link)) : page;
  if (!existsSync(file)) return null;
  if (!statSync(file).isDirectory()) return file;
  const index = path.join(file, "index.html");
  return existsSync(index) ? index : null;
}

/** The internal links of the site built in `dir` that lead nowhere, each as "page: link". */
export function deadLinks(dir) {
  const ids = new Map();
  const idsOf = (file) => {
    if (!ids.has(file)) ids.set(file, new Set([...readFileSync(file, "utf8").matchAll(/\sid="([^"]*)"/g)].map((m) => m[1])));
    return ids.get(file);
  };
  const dead = [];
  for (const page of pages(dir)) {
    const html = readFileSync(page, "utf8").replace(/<pre>[\s\S]*?<\/pre>/g, "");
    const links = [...html.matchAll(/\s(?:href|src)="([^"]*)"/g)].map((m) => m[1].replaceAll("&amp;", "&"));
    // The showcase's variant links are written by its script from this list.
    const variants = /\sdata-variants="([^"]*)"/.exec(html)?.[1].split(",") ?? [];
    for (const link of [...links, ...variants.map((v) => `../${v}/`)]) {
      if (/^([a-z][a-z0-9+.-]*:|\/\/)/i.test(link)) continue;
      const [file, hash] = link.split("#");
      const to = target(page, file.split("?")[0]);
      const found = to !== null && (!hash || !to.endsWith(".html") || idsOf(to).has(decodeURIComponent(hash)));
      if (!found) dead.push(`${path.relative(dir, page)}: ${link}`);
    }
  }
  return dead;
}
