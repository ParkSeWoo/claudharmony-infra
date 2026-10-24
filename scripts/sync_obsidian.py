#!/usr/bin/env python3
"""docs/*.md → docs/index.html 생성 후, Obsidian 볼트로 md(위키링크 변환 + 실제 값 치환) 와 html 을 복사한다.

설정: ~/.claudharmony/private.json (저장소 밖, 커밋 안 함)
  { "obsidian_dir": "...", "replacements": { "<PUBLIC_IP>": "x.x.x.x", ... } }
사용: python3 scripts/sync_obsidian.py
"""
import json
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"
CONF = json.loads((pathlib.Path.home() / ".claudharmony/private.json").read_text())
VAULT = pathlib.Path(CONF["obsidian_dir"])

subprocess.run([sys.executable, str(ROOT / "scripts/build_docs.py")], check=True)

pages = sorted(DOCS.glob("[0-9][0-9]-*.md"))
# 01-architecture.md → "01 아키텍처" (첫 줄 '# 01. 아키텍처' 에서 이름을 만든다)
titles = {}
for p in pages:
    h1 = re.search(r"^# (.+)$", p.read_text(encoding="utf-8"), re.M).group(1)
    titles[p.stem] = re.sub(r"^(\d+)\.\s*", r"\1 ", h1).split(" — ")[0].strip().replace("/", "·")

VAULT.mkdir(parents=True, exist_ok=True)
for p in pages:
    md = p.read_text(encoding="utf-8")
    md = re.sub(r"\[([^\]]+)\]\(([0-9]{2}[^)/]+)\.md\)", lambda m: f"[[{titles[m.group(2)]}|{m.group(1)}]]", md)
    for k, v in CONF.get("replacements", {}).items():
        md = md.replace(k, v)
    md = re.sub(r"^> 이 저장소는 \*\*public\*\*.*?\n(> .*\n)*", "> 🔒 개인 노트 — 실제 IP / MAC 포함 (GitHub 문서는 placeholder).\n", md, flags=re.M)
    front = f"---\ntags: [클라우드하모니, 인프라]\nsource: ~/infra/docs/{p.name}\n---\n\n"
    (VAULT / f"{titles[p.stem]}.md").write_text(front + md, encoding="utf-8")

# 이름이 바뀐 옛 노트 정리 (MOC 와 html 은 유지)
keep = {f"{t}.md" for t in titles.values()} | {"00 인프라 구성 (MOC).md"}
for old in VAULT.glob("[0-9][0-9] *.md"):
    if old.name not in keep:
        old.unlink()

html = (DOCS / "index.html").read_text(encoding="utf-8")
for k, v in CONF.get("replacements", {}).items():
    html = html.replace(k, v)
(VAULT / "인프라 문서.html").write_text(html, encoding="utf-8")
print(f"synced {len(pages)} pages + html → {VAULT}")
