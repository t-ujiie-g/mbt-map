// What the panel reads out of the camera, shared by the three examples.
import { RADIUS_METERS } from "./analysis.js";

const fixed = (v, n) => v.toFixed(n);

/** The rows of `#camera` for a `{ center, zoom, bearing, pitch }` and the center's plane rectangular coordinates. */
export function cameraRows({ center, zoom, bearing, pitch }, plane) {
  const rows = [
    ["Longitude", fixed(center.lng, 5)],
    ["Latitude", fixed(center.lat, 5)],
    ["Zoom", fixed(zoom, 2)],
    ["Bearing", `${fixed(bearing, 1)}°`],
    ["Pitch", `${fixed(pitch, 1)}°`],
  ];
  if (plane) rows.push([`Plane ${plane.zone}`, `X ${fixed(plane.y, 1)} m`], ["", `Y ${fixed(plane.x, 1)} m`]);
  return rows;
}

/** The lines of `#near`: the places, or that there are none. */
export const nearLines = (near) => (near.length ? near : [`None within ${RADIUS_METERS / 1000} km`]);

/** Fills `dl` with `[label, value]` rows. */
export function showRows(dl, rows) {
  dl.replaceChildren(...rows.flatMap(([k, v]) => [Object.assign(document.createElement("dt"), { textContent: k }), Object.assign(document.createElement("dd"), { textContent: v })]));
}
