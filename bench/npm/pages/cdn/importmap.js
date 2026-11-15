// The import map to the package on the origin ?cdn= names (another 127.0.0.1 port, standing in for a CDN).
const cdn = new URLSearchParams(location.search).get("cdn") ?? "";
if (!/^http:\/\/127\.0\.0\.1:\d+$/.test(cdn)) throw new Error(`cdn page: bad ?cdn=${cdn}`);
const dist = `${cdn}/bench/npm/pages/npm/node_modules/mbt-map/dist/`;
const map = document.createElement("script");
map.type = "importmap";
map.textContent = JSON.stringify({ imports: { "mbt-map": `${dist}index.js`, "mbt-map/analysis": `${dist}analysis.js` } });
document.currentScript.after(map);
