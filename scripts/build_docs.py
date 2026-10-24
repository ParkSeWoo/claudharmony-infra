#!/usr/bin/env python3
"""docs/*.md 를 한 페이지 HTML(docs/index.html)로 묶는다. 사용: python3 scripts/build_docs.py"""
import json
import pathlib

DOCS = pathlib.Path(__file__).resolve().parent.parent / "docs"
pages = [{"id": p.stem, "md": p.read_text(encoding="utf-8")}
         for p in sorted(DOCS.glob("[0-9][0-9]-*.md"))]

TEMPLATE = """<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Claud Harmony Infra</title>
<style>
:root{--bg:#fbfbfa;--panel:#fff;--fg:#1d1f23;--muted:#6b7079;--line:#e6e6e3;--accent:#2f6f5e;--code:#f3f3f1;color-scheme:light}
@media (prefers-color-scheme:dark){:root{--bg:#141517;--panel:#1b1d20;--fg:#e7e7e4;--muted:#9a9ea6;--line:#2c2f34;--accent:#7cc4ad;--code:#23262a;color-scheme:dark}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.7 -apple-system,BlinkMacSystemFont,"Apple SD Gothic Neo","Pretendard","Noto Sans KR",sans-serif}
.layout{display:grid;grid-template-columns:240px minmax(0,1fr);max-width:1180px;margin:0 auto;min-height:100vh}
nav{position:sticky;top:0;height:100vh;padding:32px 20px;border-right:1px solid var(--line)}
nav .brand{font-weight:700;letter-spacing:-.01em;margin-bottom:4px}
nav .sub{color:var(--muted);font-size:12px;margin-bottom:24px}
nav a{display:block;padding:6px 10px;border-radius:6px;color:var(--fg);text-decoration:none;font-size:14px}
nav a:hover{background:var(--code)}
nav a.on{background:var(--accent);color:var(--bg)}
main{padding:40px 48px 120px;min-width:0}
h1{font-size:28px;letter-spacing:-.02em;margin:0 0 24px}
h2{font-size:20px;margin:40px 0 12px;padding-top:12px;border-top:1px solid var(--line)}
h3{font-size:16px;margin:28px 0 8px}
a{color:var(--accent)}
code{background:var(--code);padding:1px 5px;border-radius:4px;font:13px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace}
pre{background:var(--code);padding:14px 16px;border-radius:8px;overflow-x:auto}
pre code{padding:0;background:none}
.tbl{overflow-x:auto}
table{border-collapse:collapse;width:100%;font-size:14px;margin:8px 0 16px}
th,td{border-bottom:1px solid var(--line);padding:8px 10px;text-align:left;vertical-align:top}
th{color:var(--muted);font-weight:600}
blockquote{margin:16px 0;padding:10px 16px;border-left:3px solid var(--accent);background:var(--panel);color:var(--muted)}
.mermaid{background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:16px;overflow-x:auto;text-align:center}
@media (max-width:760px){.layout{grid-template-columns:1fr}nav{position:static;height:auto;border-right:0;border-bottom:1px solid var(--line);padding:16px}main{padding:24px 16px 80px}}
</style>
</head>
<body>
<div class="layout">
  <nav><div class="brand">Claud Harmony Infra</div><div class="sub">사무실 인프라 · Terraform</div><div id="toc"></div></nav>
  <main id="content"></main>
</div>
<script src="https://cdn.jsdelivr.net/npm/marked@12.0.2/marked.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/mermaid@10.9.1/dist/mermaid.min.js"></script>
<script>
const PAGES = __PAGES__;
const dark = matchMedia('(prefers-color-scheme: dark)').matches;
mermaid.initialize({startOnLoad:false, theme: dark ? 'dark' : 'neutral'});
const renderer = new marked.Renderer();
renderer.code = (code, lang) => lang === 'mermaid'
  ? `<pre class="mermaid">${code}</pre>`
  : `<pre><code>${code.replace(/&/g,'&amp;').replace(/</g,'&lt;')}</code></pre>`;
renderer.table = (h, b) => `<div class="tbl"><table><thead>${h}</thead><tbody>${b}</tbody></table></div>`;
// md 간 링크(01-architecture.md) → 페이지 전환
renderer.link = (href, title, text) => {
  const m = href && href.match(/^([0-9]{2}[^/]*)\\.md$/);
  return m ? `<a href="#${m[1]}">${text}</a>` : `<a href="${href}">${text}</a>`;
};
marked.setOptions({renderer});
const toc = document.getElementById('toc'), content = document.getElementById('content');
PAGES.forEach(p => {
  const title = (p.md.match(/^# (.+)$/m) || [, p.id])[1];
  const a = Object.assign(document.createElement('a'), {href: '#' + p.id, textContent: title});
  a.dataset.id = p.id; toc.appendChild(a);
});
async function show(){
  const id = location.hash.slice(1) || PAGES[0].id;
  const p = PAGES.find(x => x.id === id) || PAGES[0];
  content.innerHTML = marked.parse(p.md);
  toc.querySelectorAll('a').forEach(a => a.classList.toggle('on', a.dataset.id === p.id));
  await mermaid.run({nodes: content.querySelectorAll('.mermaid')});
  scrollTo(0, 0);
}
addEventListener('hashchange', show); show();
</script>
</body>
</html>
"""

out = DOCS / "index.html"
out.write_text(TEMPLATE.replace("__PAGES__", json.dumps(pages, ensure_ascii=False).replace("</", "<\\/")), encoding="utf-8")
print(f"wrote {out} ({len(pages)} pages)")
