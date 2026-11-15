// Applies the remembered color theme before the page paints (default: the device's), lets the header's
// button switch between light and dark, and folds the documentation's navigation on phones.
(() => {
  const KEY = "mbt-map-theme";
  const root = document.documentElement;
  try {
    const saved = localStorage.getItem(KEY);
    if (saved === "light" || saved === "dark") root.dataset.theme = saved;
  } catch {}
  const current = () => root.dataset.theme ?? (matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");
  addEventListener("DOMContentLoaded", () => {
    // On phones the documentation's navigation starts folded, so that the page's title is on the first screen.
    const menu = document.querySelector("details.side-menu");
    if (menu && matchMedia("(max-width: 860px)").matches) menu.open = false;
    const button = document.querySelector("button.theme");
    if (!button) return;
    const show = () => {
      const dark = current() === "dark";
      button.textContent = dark ? "☀" : "☾";
      button.setAttribute("aria-label", dark ? "Switch to the light theme" : "Switch to the dark theme");
      button.title = button.getAttribute("aria-label");
    };
    show();
    button.addEventListener("click", () => {
      root.dataset.theme = current() === "dark" ? "light" : "dark";
      try {
        localStorage.setItem(KEY, root.dataset.theme);
      } catch {}
      show();
    });
  });
})();
