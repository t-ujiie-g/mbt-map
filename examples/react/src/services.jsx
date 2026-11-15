// GIS Web services read with mbt-map/services in React, over the loader the plain-DOM examples draw with the DOM.
import { useEffect, useState } from "react";
import { createServiceLoader } from "../../shared/services.js";
import { useController } from "./use-controller.js";

/** The service's URL, its layers to add and the overlays added, the loader made once per map. */
export function ServicesPanel({ map }) {
  const [loader] = useState(() => createServiceLoader(map));
  const [url, setUrl] = useState("");
  const s = useController(loader);
  useEffect(() => {
    window.__services = loader;
  }, [loader]);
  const submit = (e) => {
    e.preventDefault();
    if (url) void loader.open(url);
  };
  return (
    <div id="services">
      <form className="service-form" onSubmit={submit}>
        <input type="url" placeholder="WMS, WMTS or ArcGIS URL" aria-label="Service URL" value={url} onChange={(e) => setUrl(e.target.value)} />
        <button>Open</button>
      </form>
      <div className="chips">
        <button disabled={s.loading} onClick={() => void loader.openSample()}>Open GSI tiles (WMTS)</button>
      </div>
      <p className="hint">{s.title ? `${s.title}: choose a layer to overlay` : ""}</p>
      <div className="chips service-layers">
        {s.choices.map((c) => <button key={c.id} onClick={() => void loader.add(c)}>{c.title}</button>)}
      </div>
      {s.error && <p className="data-error">{s.error}</p>}
      <ul className="datasets">
        {s.items.map((item) => (
          <li key={item.id}>
            <b>{item.name}</b>
            <div className="chips"><button onClick={() => loader.remove(item.id)}>Remove</button></div>
          </li>
        ))}
      </ul>
    </div>
  );
}
