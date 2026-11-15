// Lists the samples of index.json with links (the local page; the site makes the gallery).
const samples = await (await fetch("./index.json")).json();
const list = document.getElementById("list");
for (const { id, group } of samples) {
  const li = document.createElement("li");
  const a = document.createElement("a");
  a.href = `./${id}/`;
  a.textContent = `${group}: ${id}`;
  li.append(a);
  list.append(li);
}
window.__loaded = performance.now();
