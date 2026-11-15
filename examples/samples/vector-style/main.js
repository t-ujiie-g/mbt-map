import { Map } from "mbt-map";

const cities = {
  Tokyo: [139.7671, 35.6812],
  Beijing: [116.3975, 39.9087],
  Paris: [2.3522, 48.8566],
  "New York": [-74.006, 40.7128],
};

const map = new Map({
  container: "map",
  style: "https://tiles.openfreemap.org/styles/liberty",
  center: cities.Tokyo,
  zoom: 12,
});

const row = document.getElementById("cities");
for (const [name, center] of Object.entries(cities)) {
  const button = document.createElement("button");
  button.textContent = name;
  button.onclick = () => map.flyTo({ center, zoom: 12 });
  row.append(button);
}
