// URL handling of the facade, kept free of imports so tests can run it as is.

/** What a `transformRequest` gives: the URL to fetch, and the headers and credentials to send. */
export interface TransformedRequest {
  url: string;
  headers?: Record<string, string>;
  credentials?: RequestCredentials;
}

/** `url` resolved against `base`, refused unless http(s), so a style cannot fetch data: or blob: URLs (AGENTS.md §8.3). */
export function httpUrl(url: string | URL, base: string | URL, what: string): string {
  const u = new URL(url, base);
  if (!/^https?:$/.test(u.protocol)) throw new Error(`mbt-map: ${what} must be an http(s) URL: ${u.href}`);
  return u.href;
}

/** The scheme prefix of PMTiles archives in source URLs and tile templates. */
export const PMTILES = "pmtiles://";

/** The archive URL of a `pmtiles://` URL, or null for any other. */
export function pmtilesArchive(url: string): string | null {
  return url.startsWith(PMTILES) ? url.slice(PMTILES.length) : null;
}

/** The tile URL placeholders the engine fills in, as MapLibre's `CanonicalTileID.url`. */
export const TILE_PLACEHOLDERS = ["z", "x", "y", "prefix", "ratio", "quadkey", "bbox-epsg-3857", "bbox"];

const ENCODED_PLACEHOLDER = new RegExp(`%7B(${TILE_PLACEHOLDERS.join("|")})%7D`, "g");

/** A tile template resolved against `base`, its placeholders kept: http(s), or `pmtiles://` and an http(s) archive. */
export function resolveTemplate(template: string, base: string | URL, what = "tiles"): string {
  const archive = pmtilesArchive(template);
  // URL() percent-encodes the placeholders' braces.
  const href = httpUrl(archive ?? template, base, what).replace(ENCODED_PLACEHOLDER, "{$1}");
  return archive === null ? href : PMTILES + href;
}

const BOOTSTRAPS = new Map<string, string>();

// The library's folder, cut from the string: bundlers take `new URL("./", import.meta.url)` for an asset.
const HOME = import.meta.url.slice(0, import.meta.url.lastIndexOf("/") + 1);

function bootstrap(key: string, script: () => BlobPart): string {
  let blob = BOOTSTRAPS.get(key);
  if (!blob) {
    blob = URL.createObjectURL(new Blob([script()], { type: "text/javascript" }));
    BOOTSTRAPS.set(key, blob);
  }
  return blob;
}

function dataUrlBody(href: string): BlobPart {
  const comma = href.indexOf(",");
  const body = href.slice(comma + 1).replace(/#.*$/s, "");
  return /;base64$/i.test(href.slice(0, comma)) ? Uint8Array.from(atob(decodeURIComponent(body)), (c) => c.charCodeAt(0)) : decodeURIComponent(body);
}

/**
 * Where to start a module worker. The page's `given` must be on its origin, or in `home` (the library's folder on a
 * CDN: started through a same-origin blob importing it); others are refused (§8.3). Without it, the library's `own`,
 * where a bundler put it: http(s) anywhere, or a `data:` URL (inlined), started from a blob of the same text.
 */
export function workerScriptUrl(given: string | URL | undefined, own: URL, base: URL, origin: string, home = HOME): string {
  const u = new URL(given ?? own, base);
  const http = /^https?:$/.test(u.protocol);
  if (given === undefined) {
    if (u.protocol === "data:") return bootstrap(u.href, () => dataUrlBody(u.href));
    if (!http) throw new Error(`mbt-map: the library's worker must be an http(s) or inlined URL: ${u.protocol}`);
  } else {
    const inHome = /^https?:$/.test(new URL(home).protocol) && u.href.startsWith(home);
    if (!http || (u.origin !== origin && !inHome)) {
      throw new Error(`mbt-map: the worker must be an http(s) URL on the page's origin or beside the library: ${u.href}`);
    }
  }
  return u.origin === origin ? u.href : bootstrap(u.href, () => `import ${JSON.stringify(u.href)};`);
}

/**
 * The URLs of a worker's parts (files it imports on first use), sent in its init message so that a bundler's
 * copies are found; undefined with the page's own worker (`given`), which imports the files beside itself.
 */
export function workerParts(given: unknown, parts: Record<string, URL>): Record<string, string> | undefined {
  if (given !== undefined) return undefined;
  return Object.fromEntries(Object.entries(parts).map(([name, url]) => [name, url.href]));
}

export function wasmUrl(url: string | URL, base: URL): string {
  return httpUrl(url, base, "the wasm");
}
