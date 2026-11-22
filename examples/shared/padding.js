// The map padding that keeps the map's center clear of the showcase's panel: the panel's right
// edge on wide screens, the sheet's height along the bottom on narrow ones, none while it is hidden.

/** A padding of nothing. */
export const NO_PADDING = { top: 0, right: 0, bottom: 0, left: 0 };

/** The padding the panel asks for as it is now (the map fills the window). */
export function panelPadding() {
  const card = document.querySelector(".panel-card");
  if (!card || card.classList.contains("collapsed") || card.offsetParent === null) return NO_PADDING;
  const box = card.getBoundingClientRect();
  return box.width >= window.innerWidth ? { ...NO_PADDING, bottom: Math.round(window.innerHeight - box.top) } : { ...NO_PADDING, left: Math.round(box.right) };
}

/** Calls `apply` with the panel's padding now and each time the panel's box changes; returns what stops it. */
export function watchPanel(apply) {
  const observer = new ResizeObserver(() => apply(panelPadding()));
  observer.observe(document.querySelector(".panel-card"));
  return () => observer.disconnect();
}

/** Wires `#clear-panel`: pressed, `apply` gets the panel's padding as it changes; released, none. */
export function mountPanelPadding(apply) {
  const button = document.getElementById("clear-panel");
  let stop = null;
  button.addEventListener("click", () => {
    const on = button.getAttribute("aria-pressed") !== "true";
    button.setAttribute("aria-pressed", String(on));
    stop?.();
    stop = on ? watchPanel(apply) : null;
    if (!on) apply(NO_PADDING);
  });
}
