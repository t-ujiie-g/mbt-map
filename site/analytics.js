// Google Tag Manager for the published site only (not local previews or CI): the container and the gtag
// bootstrap as given, with GTM's own `gtm.start` event so its page-view triggers fire.
if (location.hostname === "t-ujiie-g.github.io") {
  window.dataLayer = window.dataLayer || [];
  window.dataLayer.push({ "gtm.start": Date.now(), event: "gtm.js" });
  function gtag() {
    window.dataLayer.push(arguments);
  }
  window.gtag = gtag;
  gtag("js", new Date());
  const script = document.createElement("script");
  script.async = true;
  script.src = "https://www.googletagmanager.com/gtm.js?id=GTM-MWGLDWNP";
  document.head.append(script);
}
