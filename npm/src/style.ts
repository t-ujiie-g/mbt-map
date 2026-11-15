// The style document's types and the few helpers the facade keeps in TypeScript; the document
// itself and its edits are MoonBit's (`web/style_doc.mbt`).


/** A MapLibre style document; anything moonmap cannot draw faithfully is an error. */
export interface StyleSpecification {
  version: 8;
  sources: Record<string, unknown>;
  layers: unknown[];
  [key: string]: unknown;
}

/** A style layer as MapLibre's `LayerSpecification`; `paint` and `layout` hold its properties by name. */
export interface LayerSpecification {
  id: string;
  type: string;
  source?: string;
  "source-layer"?: string;
  minzoom?: number;
  maxzoom?: number;
  filter?: unknown;
  layout?: Record<string, unknown>;
  paint?: Record<string, unknown>;
  [key: string]: unknown;
}

/**
 * The global state after a style loads, as MapLibre's `setGlobalState`: each key of the style's `state`
 * (`defaults`) or of `initial` takes `initial`'s value, else its default, else null; other keys of `current` stay.
 */
export function loadedState(current: Record<string, unknown>, defaults: unknown, initial: Record<string, unknown>): Record<string, unknown> {
  const state = (defaults && typeof defaults === "object" ? defaults : {}) as Record<string, { default?: unknown } | undefined>;
  const out = { ...current };
  for (const k of new Set([...Object.keys(state), ...Object.keys(initial)])) out[k] = initial[k] ?? state[k]?.default ?? null;
  return out;
}

/** A plain copy, so that later changes by the caller do not reach the map. */
export function copy<T>(value: T): T {
  return value === undefined ? value : (JSON.parse(JSON.stringify(value)) as T);
}

/** Why `layer` is not a custom layer MapLibre would take (its `validateCustomStyleLayer`), or "". */
export function invalidCustomLayer(layer: { id?: unknown; render?: unknown; renderingMode?: unknown }): string {
  if (typeof layer.id !== "string") return 'missing required property "id"';
  if (typeof layer.render !== "function") return 'missing required method "render"';
  if (layer.renderingMode !== undefined && layer.renderingMode !== "2d" && layer.renderingMode !== "3d") {
    return 'property "renderingMode" must be either "2d" or "3d"';
  }
  return "";
}

/** The deepest expression nesting the engine takes; mirrors `MAX_EXPR_DEPTH` in style/expr.mbt. */
export const MAX_EXPR_DEPTH = 32;
