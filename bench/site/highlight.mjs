// Highlights the code blocks of the site's pages at build time (highlight.js; MoonBit through its own grammar),
// so the pages load no script for it.
import hljs from "highlight.js/lib/core";
import bash from "highlight.js/lib/languages/bash";
import javascript from "highlight.js/lib/languages/javascript";
import json from "highlight.js/lib/languages/json";
import typescript from "highlight.js/lib/languages/typescript";
import xml from "highlight.js/lib/languages/xml";
import moonbit from "./moonbit-highlight.mjs";

for (const [name, lang] of Object.entries({ bash, javascript, json, typescript, xml, moonbit })) hljs.registerLanguage(name, lang);
/** Fence names the docs use, as highlight.js knows them. */
const LANGUAGES = { sh: "bash", js: "javascript", jsx: "javascript", ts: "typescript", html: "xml", json: "json", moonbit: "moonbit" };

const unescape = (s) => s.replace(/&(lt|gt|quot|#39|amp);/g, (_, e) => ({ lt: "<", gt: ">", quot: '"', "#39": "'", amp: "&" })[e]);

/** `html` with its `<pre><code class="language-…">` blocks highlighted (at build time: the pages load no script for it). */
export function highlight(html) {
  return html.replace(/<pre><code class="language-([\w-]+)">([\s\S]*?)<\/code><\/pre>/g, (whole, name, code) => {
    const language = LANGUAGES[name];
    if (!language) return whole;
    const out = hljs.highlight(unescape(code), { language, ignoreIllegals: true }).value;
    return `<pre><code class="hljs language-${name}">${out}</code></pre>`;
  });
}

