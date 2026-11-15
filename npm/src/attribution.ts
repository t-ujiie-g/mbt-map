// The attributions MapLibre GL JS 6.16.0's AttributionControl shows
// (`_updateAttributions`, BSD-3-Clause, Copyright (c) 2020 MapLibre contributors;
// see NOTICE). Import-free, so that `npm test` can load it.

interface StyleLike {
  sources?: Record<string, unknown>;
  layers?: unknown[];
  terrain?: unknown;
}

/** Whether `zoom` lies in a layer's zoom range, as MapLibre's `isHidden` reads `minzoom` and `maxzoom`. */
export function inZoomRange(layer: object, zoom: number): boolean {
  const l = layer as { minzoom?: unknown; maxzoom?: unknown };
  const min = Number(l.minzoom ?? 0);
  const max = Number(l.maxzoom ?? 0);
  return !(min && zoom < min) && !(max && zoom >= max);
}

/** Whether a layer is drawn at `zoom` (MapLibre's `isHidden`, inverted): in range and not `visibility: none`. */
export function layerShown(layer: object, zoom: number): boolean {
  return inZoomRange(layer, zoom) && (layer as { layout?: { visibility?: unknown } }).layout?.visibility !== "none";
}

/**
 * The attributions of the sources a layer shown at `zoom` or the terrain uses, in source order,
 * then shortest first with any contained in another left out (MapLibre's order).
 */
export function attributionsOf(style: StyleLike, zoom: number): string[] {
  const used = new Set<string>();
  for (const l of style.layers ?? []) {
    const layer = l as Record<string, unknown>;
    if (typeof layer.source === "string" && layerShown(layer, zoom)) used.add(layer.source);
  }
  const terrain = (style.terrain as { source?: unknown } | undefined)?.source;
  if (typeof terrain === "string") used.add(terrain);
  let out: string[] = [];
  for (const [id, s] of Object.entries(style.sources ?? {})) {
    const a = (s as { attribution?: unknown })?.attribution;
    if (used.has(id) && typeof a === "string" && !out.includes(a)) out.push(a);
  }
  out = out.filter((a) => a.trim());
  out.sort((a, b) => a.length - b.length);
  return out.filter((a, i) => !out.slice(i + 1).some((b) => b.includes(a)));
}

/** A piece of an attribution: its text, and the http(s) link it belongs to, if any. */
export interface AttributionPart {
  text: string;
  href?: string;
}

const ENTITIES: Record<string, string> = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " ", copy: "©", reg: "®" };

function decode(s: string): string {
  return s.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (whole, e: string) => {
    if (e[0] !== "#") return ENTITIES[e.toLowerCase()] ?? whole;
    const code = e[1] === "x" || e[1] === "X" ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10);
    return code > 0 && code <= 0x10ffff ? String.fromCodePoint(code) : whole;
  });
}

/**
 * An attribution written as HTML (as styles and TileJSON write them) read without the DOM: text, with the
 * links of `<a href="http(s)://…">` kept and every other tag dropped (`<br>` as a space).
 */
export function attributionParts(html: string): AttributionPart[] {
  const parts: AttributionPart[] = [];
  let href: string | undefined;
  const push = (text: string) => {
    if (!text) return;
    const last = parts[parts.length - 1];
    if (last && last.href === href) last.text += text;
    else parts.push(href ? { text, href } : { text });
  };
  for (const m of html.matchAll(/<(\/?)([a-z][a-z0-9]*)\b([^>]*)>|[^<]+|</gi)) {
    if (m[2] === undefined) push(decode(m[0]));
    else if (m[2].toLowerCase() === "br") push(" ");
    else if (m[2].toLowerCase() === "a") {
      if (m[1]) href = undefined;
      else {
        const h = /\bhref\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/i.exec(m[3]);
        const url = decode(h?.[1] ?? h?.[2] ?? h?.[3] ?? "").trim();
        href = /^https?:\/\//i.test(url) ? url : undefined;
      }
    }
  }
  return parts;
}

/** The text of an attribution written as HTML (`attributionParts` without the links). */
export function attributionText(html: string): string {
  return attributionParts(html)
    .map((p) => p.text)
    .join("");
}
