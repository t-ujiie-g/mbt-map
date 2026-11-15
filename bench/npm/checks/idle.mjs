// `idle` on the npm example's map, as MapLibre fires it: once after every frame that leaves nothing to load, move
// or draw (one-frame changes included: triggerRepaint, setClipping, setViewshed), never while the map rests or an
// animation runs, and once, not per frame, while something keeps repainting.
export async function idleChecks(page) {
  const r = await page.evaluate(async () => {
    const map = window.__map;
    const frames = (n) => new Promise((done) => {
      const next = () => (n-- > 0 ? requestAnimationFrame(next) : done());
      next();
    });
    map.triggerRepaint();
    await map.once("idle");
    let idles = 0;
    let renders = 0;
    const count = () => idles++;
    const drawn = () => renders++;
    map.on("idle", count);
    map.on("render", drawn);
    await frames(5);
    const resting = [idles, renders];
    const oneFrame = [];
    const changes = [
      () => map.triggerRepaint(),
      () => map.setClipping({ origin: [139.7671, 35.6812], planes: [[1, 0, 0, 0]] }),
      () => map.setClipping(null),
      () => map.setViewshed({ position: [139.7671, 35.6812, 30] }),
      () => map.setViewshed(null),
    ];
    for (const change of changes) {
      const before = [idles, renders];
      change();
      await frames(4);
      oneFrame.push([idles - before[0], renders - before[1]]);
    }
    // An animation: no `idle` until it has ended.
    const start = map.getBearing();
    const before = idles;
    let atEnd = -1;
    map.once("moveend", () => (atEnd = idles - before));
    const settled = map.once("idle");
    map.easeTo({ bearing: start + 20, duration: 200 });
    await settled;
    const moving = map.isMoving();
    // A listener that repaints every frame: one `idle` when it stops.
    const during = idles;
    let left = 10;
    const again = () => left-- > 0 && map.triggerRepaint();
    map.on("render", again);
    map.triggerRepaint();
    await frames(15);
    map.off("render", again);
    const repainting = idles - during;
    const blob = await map.toBlob();
    map.off("idle", count);
    map.off("render", drawn);
    map.jumpTo({ bearing: start });
    await map.once("idle");
    return { resting, oneFrame, atEnd, moving, repainting, blob: blob.size > 0 };
  });
  const ok =
    r.resting.join() === "0,0" && r.oneFrame.every(([idles, renders]) => idles === 1 && renders === 1) &&
    r.atEnd === 0 && !r.moving && r.repainting === 1 && r.blob;
  return { ok, ...r };
}
