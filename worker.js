// Echo origin: shows what reached the Worker after WAF rules ran.
const PATHS = ["/block", "/block?bypass=1", "/managed-challenge", "/non-interactive-challenge", "/interactive-challenge", "/ratelimit"];

const esc = (s) => s.replace(/[&<>"]/g, (c) => `&#${c.charCodeAt(0)};`);

export default {
  async fetch(req) {
    const url = new URL(req.url);
    const headers = [...req.headers].map(([k, v]) => `<tr><td>${esc(k)}</td><td>${esc(v)}</td></tr>`).join("");
    const links = PATHS.map((p) => `<li><a href="${p}">${p}</a></li>`).join("");
    const html = `<!doctype html><meta charset="utf-8"><title>CF action demo</title>
<style>body{font:14px system-ui;max-width:60em;margin:2em auto;padding:0 1em}td{border-bottom:1px solid #ccc;padding:2px 8px;word-break:break-all}</style>
<h1>Reached the Worker: ${esc(req.method)} ${esc(url.pathname + url.search)}</h1>
<p>Seeing this page means no WAF action stopped the request.</p>
<h2>Demo paths</h2><ul>${links}</ul>
<h2>Request headers</h2><table>${headers}</table>`;
    return new Response(html, { headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" } });
  },
};
