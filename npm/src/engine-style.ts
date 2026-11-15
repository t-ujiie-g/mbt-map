// A query's filter as the engine takes it. Import-free, so that `npm test` can load it.

/**
 * `filter` as JSON text (empty for none), a legacy filter (by `isLegacy`, the engine's
 * `is_legacy_filter`) converted by `convert` once it has loaded.
 */
export function filterText(filter: unknown, convert: ((filter: unknown) => unknown) | null, isLegacy: (filter: unknown) => boolean): string {
  if (filter === undefined) return "";
  return JSON.stringify(convert && isLegacy(filter) ? convert(filter) : filter);
}
