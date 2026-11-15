// The pointer's coordinates in four systems from `mbt-map/ui`'s controller:
// degrees and DMS as it writes them, Japan's plane rectangular system (the
// nearest zone) and UTM through mbt-map/analysis's `transform`.
import { transform } from "mbt-map/analysis";
import { createCoordinates, degrees, degreesMinutesSeconds, utm } from "mbt-map/ui";
import { nearestZone } from "./analysis.js";

/** A system of the page's own: the zone's name, then X (northing) and Y (easting). */
const plane = {
  id: "plane",
  title: "Plane",
  async format(p) {
    const z = nearestZone(p.lng, p.lat);
    const [x, y] = await transform([p.lng, p.lat], 4326, z.epsg);
    return `${z.name} X ${y.toFixed(1)} Y ${x.toFixed(1)}`;
  },
};

export function createCoordinateReadout(map) {
  const c = createCoordinates(map, {
    systems: [{ ...degrees(), title: "Lat, lng" }, { ...degreesMinutesSeconds(), title: "DMS" }, plane, { ...utm(transform), title: "UTM" }],
  });
  window.__coordinates = c;
  return c;
}

/** The readout in the status bar `parent`, for the plain-DOM examples. */
export function mountCoordinates(map, parent) {
  const c = createCoordinateReadout(map);
  const box = document.createElement("dl");
  box.className = "coordinates";
  parent.append(box);
  const draw = () =>
    box.replaceChildren(
      ...c.state.values.map((v) => {
        const item = document.createElement("div");
        item.append(Object.assign(document.createElement("dt"), { textContent: v.title }), Object.assign(document.createElement("dd"), { textContent: v.text }));
        return item;
      }),
    );
  c.subscribe(draw);
  draw();
  return c;
}
