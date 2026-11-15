// Applies the remembered color theme before the page paints (default: the device's), and lets the header's
// button switch between light and dark.
(() => {
  const KEY = "mbt-map-theme";
  const root = document.documentElement;
  try {
    const saved = localStorage.getItem(KEY);
    if (saved === "light" || saved === "dark") root.dataset.theme = saved;
  } catch {}
  const current = () => root.dataset.theme ?? (matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");
  addEventListener("DOMContentLoaded", () => {
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
