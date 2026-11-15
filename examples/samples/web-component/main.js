import "mbt-map/element";

const el = document.querySelector("mbt-map");
const event = document.getElementById("event");
const detail = document.getElementById("detail");

function show(e) {
  const { center, zoom, lngLat } = e.detail;
  event.textContent = e.type;
  detail.textContent = [
    `center ${center.lng.toFixed(4)}, ${center.lat.toFixed(4)}`,
    `zoom ${zoom.toFixed(2)}`,
    lngLat && `clicked ${lngLat.lng.toFixed(4)}, ${lngLat.lat.toFixed(4)}`,
  ]
    .filter(Boolean)
    .join("\n");
}

el.addEventListener("mbt-map-moveend", show);
el.addEventListener("mbt-map-click", show);
el.addEventListener("mbt-map-error", (e) => (event.textContent = e.detail.error.message));

// The camera properties take the attributes' strings too.
for (const button of document.querySelectorAll("[data-center]")) {
  button.addEventListener("click", () => {
    el.center = button.dataset.center;
    el.zoom = button.dataset.zoom;
  });
}
// The element refuses zooms outside 0 to 22 (it fires mbt-map-error), so the buttons stop there.
document.getElementById("zoom-in").addEventListener("click", () => (el.zoom = Math.min(el.zoom + 1, 22)));
document.getElementById("zoom-out").addEventListener("click", () => (el.zoom = Math.max(el.zoom - 1, 0)));
