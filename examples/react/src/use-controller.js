// A controller's state in a component: `mbt-map/ui` and `mbt-map/search` controllers
// fit `useSyncExternalStore` as they are.
import { useSyncExternalStore } from "react";

export function useController(c) {
  return useSyncExternalStore(c.subscribe, () => c.state);
}
