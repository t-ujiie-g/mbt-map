// Steps of the pack-test checks that wait for a map event: the listener goes in before the step acts, and a
// step whose event does not come fails after `timeout` ms with its label. `trail` keeps the labels entered last.
export const trail = [];

/** Records that the check entered step `label`. */
export function crumb(label) {
  trail.push(label);
  if (trail.length > 10) trail.shift();
}

/**
 * Runs `body` (a function body over `map`; it may await and return a value) on `window.__map`, then waits
 * for the map's `event`.
 */
export async function step(page, label, body, { event = "idle", timeout = 30_000 } = {}) {
  crumb(label);
  return page.evaluate(async ([b, event, timeout, label]) => {
    const map = window.__map;
    let timer;
    const done = new Promise((resolve, reject) => {
      map.once(event).then(resolve);
      timer = setTimeout(() => reject(new Error(`${label}: no ${event} after ${timeout} ms`)), timeout);
    });
    try {
      const out = await new Function("map", `return (async () => { ${b} })()`)(map);
      await done;
      return out;
    } finally {
      clearTimeout(timer);
    }
  }, [body, event, timeout, label]);
}

/** Like `step`, for an `action` done from outside the page (a click, a key press). */
export async function awaitAfter(page, label, action, { event = "idle", timeout = 30_000 } = {}) {
  crumb(label);
  await page.evaluate((event) => {
    window.__awaited = window.__map.once(event);
  }, event);
  await action();
  await page.evaluate(([event, timeout, label]) => {
    let timer;
    const late = new Promise((_, reject) => {
      timer = setTimeout(() => reject(new Error(`${label}: no ${event} after ${timeout} ms`)), timeout);
    });
    return Promise.race([window.__awaited, late]).then(() => clearTimeout(timer), (e) => { clearTimeout(timer); throw e; });
  }, [event, timeout, label]);
}

/** What the page's map says it is doing (moving, loaded), or why it did not answer within 5 s. */
export async function mapState(page) {
  const state = page.evaluate(() => {
    const map = window.__map;
    return map ? { moving: map.isMoving(), loaded: map.loaded() } : "no map";
  });
  const late = new Promise((resolve) => setTimeout(() => resolve("no answer after 5 s"), 5000));
  return Promise.race([state.catch((e) => `failed: ${e.message}`), late]);
}

/** Opens the showcase panel's tab `id`. */
export const openTab = (page, id) => page.click(`.tabs button[data-tab=${id}]`);

// 404s are expected (missing style, missing fixtures); so are the rejections the element and style checks provoke,
// and Firefox's report of the malformed XML the services check parses.
const EXPECTED = /404|mbt-map: invalid|no layer "nope"|"gsi" is used by layer|expression properties|'nope' does not exist|sourceLayer parameter must be provided|image named "swatch" already exists|width \* height \* 4 bytes|media must be http|Invalid layer|no layer named nope|missing required method|not compatible with updateData|XML Parsing Error/;

// Firefox and WebKit give `console.error(error)` as the bare "Error" (Chromium as its message and stack), so the
// text is taken from the error object.
const consoleText = (m) =>
  Promise.all(m.args().map((a) => a.evaluate((v) => (v instanceof Error ? `${v.message}\n${v.stack}` : String(v))).catch(() => m.text())))
    .then((t) => t.join(" ") || m.text());

/** Collects `page`'s uncaught errors and unexpected console errors; `settled` waits for the console texts read. */
export function watchErrors(page) {
  const errors = [];
  const logged = [];
  page.on("pageerror", (e) => errors.push(e.message));
  page.on("console", (m) => {
    if (m.type() === "error") logged.push(consoleText(m).then((t) => !EXPECTED.test(t) && errors.push(t)));
  });
  return { errors, settled: () => Promise.all(logged) };
}
