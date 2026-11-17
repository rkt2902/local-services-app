#!/usr/bin/env python3
"""Gera as páginas web estáticas dos textos legais a partir de assets/legal/.

    python3 tool/build_legal_pages.py          # escreve web/termos/ e web/privacidade/
    python3 tool/build_legal_pages.py --check  # falha se estiverem desatualizadas (CI)

A app mostra os mesmos ficheiros Markdown nos ecrãs /termos e /privacidade.
Na web, projardim.pt/termos e projardim.pt/privacidade servem estas páginas
estáticas (rápidas, legíveis sem JavaScript, para as lojas e a Meta).
Só o subconjunto de Markdown que os textos usam (ver legal_document.dart).
"""
import html
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PAGES = [
    ("termos-de-utilizacao.md", "termos", "Termos de utilização",
     "privacidade", "Política de Privacidade"),
    ("politica-de-privacidade.md", "privacidade", "Política de Privacidade",
     "termos", "Termos de utilização"),
]

INLINE = re.compile(r"\*\*(.+?)\*\*|\[([^\]]+)\]\(([^)\s]+)\)")
EMAIL = re.compile(r"[\w.+-]+@[\w-]+(?:\.[\w-]+)+")


def emails(text):
    out, i = [], 0
    for m in EMAIL.finditer(text):
        out.append(html.escape(text[i:m.start()]))
        e = html.escape(m.group(0))
        out.append(f'<a href="mailto:{e}">{e}</a>')
        i = m.end()
    out.append(html.escape(text[i:]))
    return "".join(out)


def inline(text):
    out, i = [], 0
    for m in INLINE.finditer(text):
        out.append(emails(text[i:m.start()]))
        if m.group(1) is not None:
            out.append(f"<strong>{emails(m.group(1))}</strong>")
        else:
            url = html.escape(m.group(3), quote=True)
            out.append(f'<a href="{url}" rel="noopener">{html.escape(m.group(2))}</a>')
        i = m.end()
    out.append(emails(text[i:]))
    return "".join(out)


def cells(line):
    body = line.strip()
    if body.startswith("|"):
        body = body[1:]
    if body.endswith("|"):
        body = body[:-1]
    return [c.strip() for c in body.split("|")]


def slug(title):
    m = re.match(r"^(\d+)\.", title)
    return f"s{m.group(1)}" if m else re.sub(r"\W+", "-", title.lower()).strip("-")


def render(md):
    title, updated = "", None
    body, toc = [], []
    para, bullets, table = [], [], []
    in_section = False

    def flush():
        nonlocal para, bullets, table
        if para:
            body.append(f"<p>{inline(' '.join(para))}</p>")
            para = []
        if bullets:
            items = "".join(f"<li>{inline(b)}</li>" for b in bullets)
            body.append(f"<ul>{items}</ul>")
            bullets = []
        if table:
            rows = [cells(l) for l in table if not re.match(r"^\|[\s\-:|]+\|?$", l)]
            if rows:
                head = "".join(f"<th>{inline(c)}</th>" for c in rows[0])
                trs = "".join(
                    "<tr>" + "".join(
                        f'<td data-label="{html.escape(re.sub(r"[*]", "", rows[0][i]) if i < len(rows[0]) else "", quote=True)}">{inline(c)}</td>'
                        for i, c in enumerate(r)) + "</tr>"
                    for r in rows[1:])
                body.append(f'<div class="table"><table><thead><tr>{head}</tr></thead><tbody>{trs}</tbody></table></div>')
            table = []

    for raw in md.split("\n"):
        line = raw.rstrip()
        t = line.strip()
        if t.startswith("# "):
            flush()
            title = t[2:].strip()
            if title.startswith("ProJardim: "):
                title = title[len("ProJardim: "):]
            continue
        m = re.match(r"^\*\*Última atualização:\*\*\s*(.+)$", t)
        if m:
            flush()
            updated = m.group(1).strip()
            continue
        if t.startswith("## "):
            flush()
            if in_section:
                body.append("</section>")
            st = t[3:].strip()
            toc.append((slug(st), st))
            body.append(f'<section class="card" id="{slug(st)}"><h2>{inline(st)}</h2>')
            in_section = True
            continue
        if t.startswith("### "):
            flush()
            body.append(f"<h3>{inline(t[4:].strip())}</h3>")
            continue
        if t in ("---", ""):
            flush()
            continue
        if t.startswith("|"):
            if para or bullets:
                saved, table = table, []
                flush()
                table = saved
            table.append(t)
            continue
        if t.startswith("- "):
            if para or table:
                saved, bullets = bullets, []
                flush()
                bullets = saved
            bullets.append(t[2:].strip())
            continue
        if bullets and line.startswith("  "):
            bullets[-1] += " " + t
            continue
        if bullets or table:
            flush()
        para.append(t)
    flush()
    if in_section:
        body.append("</section>")
    return title, updated, toc, body


STYLE = """
  :root { --primary:#2E7D32; --container:#EBF5E9; --tint:#F5FAF4; --bg:#F6F8F6;
          --surface:#fff; --text:#1A1C1A; --strong:#3B463D; --muted:#5F6B62; --divider:#E6EBE7; }
  * { box-sizing: border-box; }
  body { margin:0; background:var(--bg); color:var(--strong);
         font:16px/1.6 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Arial, sans-serif; }
  main { max-width:760px; margin:0 auto; padding:24px 16px 48px; }
  .top { display:flex; justify-content:space-between; align-items:center; margin-bottom:16px; }
  .brand { font-weight:800; color:var(--primary); text-decoration:none; font-size:18px; }
  .top a.app { color:var(--primary); font-weight:700; text-decoration:none; font-size:14px;
               border:1px solid var(--divider); background:var(--surface); padding:8px 14px; border-radius:999px; }
  .hero { background:var(--container); border-radius:16px; padding:24px; }
  h1 { color:var(--text); font-size:26px; line-height:1.25; margin:0 0 12px; }
  .updated { display:inline-block; background:var(--surface); color:var(--primary); font-weight:700;
             font-size:13px; padding:4px 12px; border-radius:999px; margin-bottom:8px; }
  .card { background:var(--surface); border:1px solid var(--divider); border-radius:16px;
          padding:20px 24px; margin-top:12px; scroll-margin-top:12px; }
  details.card summary { cursor:pointer; font-weight:700; color:var(--text); }
  details.card ol { margin:12px 0 0; padding-left:0; list-style:none; }
  details.card li a { display:block; padding:8px 0; color:var(--strong); text-decoration:none;
                      border-bottom:1px solid var(--divider); }
  details.card li:last-child a { border-bottom:0; }
  h2 { color:var(--text); font-size:19px; margin:0 0 8px; }
  h3 { color:var(--text); font-size:16px; margin:18px 0 6px; }
  p { margin:8px 0; }
  ul { padding-left:20px; margin:8px 0; }
  li { margin:6px 0; }
  li::marker { color:#43A047; }
  strong { color:var(--text); }
  a { color:var(--primary); }
  .table { overflow-x:auto; margin:8px 0; }
  table { width:100%; border-collapse:collapse; font-size:15px; }
  th, td { text-align:left; vertical-align:top; padding:10px 12px; border-bottom:1px solid var(--divider); }
  th { background:var(--tint); color:var(--text); }
  footer { text-align:center; font-size:14px; color:var(--muted); margin-top:24px; }
  footer a { font-weight:700; }
  @media (max-width:600px) {
    .hero, .card { padding:18px 16px; }
    table, thead, tbody, tr, td { display:block; }
    thead { display:none; }
    tr { background:var(--tint); border:1px solid var(--divider); border-radius:12px; margin:8px 0; padding:8px 12px; }
    td { border:0; padding:4px 0; }
    td:first-child { font-weight:700; color:var(--text); }
    td:not(:first-child)::before { content:attr(data-label); display:block; font-size:12px;
                                   font-weight:700; color:var(--muted); }
  }
"""


def page(md_name, path, label, other_path, other_label):
    md = (ROOT / "assets" / "legal" / md_name).read_text(encoding="utf-8")
    title, updated, toc, body = render(md)
    # A introdução (antes da primeira secção) vai para o cartão de topo.
    first = next((i for i, b in enumerate(body) if b.startswith("<section")), len(body))
    intro, sections = body[:first], body[first:]
    toc_html = "".join(f'<li><a href="#{s}">{html.escape(t)}</a></li>' for s, t in toc)
    updated_html = f'<div class="updated">Última atualização: {html.escape(updated)}</div>' if updated else ""
    return f"""<!DOCTYPE html>
<html lang="pt-PT">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(label)} | ProJardim</title>
<meta name="description" content="{html.escape(label)} da ProJardim, plataforma que liga clientes a jardineiros.">
<link rel="canonical" href="https://projardim.pt/{path}">
<link rel="icon" type="image/png" href="/favicon.png">
<!-- Gerado por tool/build_legal_pages.py a partir de assets/legal/{md_name}. Não editar à mão. -->
<style>{STYLE}</style>
</head>
<body>
<main>
  <div class="top"><a class="brand" href="/">ProJardim</a><a class="app" href="/">Abrir a app</a></div>
  <div class="hero">
    <h1>{html.escape(title or label)}</h1>
    {updated_html}
    {''.join(intro)}
  </div>
  <details class="card"><summary>Índice ({len(toc)} secções)</summary><ol>{toc_html}</ol></details>
  {''.join(sections)}
  <footer><p>Ler também: <a href="/{other_path}">{html.escape(other_label)}</a> · <a href="/eliminar-conta.html">Eliminar conta</a></p>
  <p>ProJardim, jardineiros de confiança perto de ti.</p></footer>
</main>
</body>
</html>
"""


def main():
    check = "--check" in sys.argv
    stale = []
    for md_name, path, label, other_path, other_label in PAGES:
        out = ROOT / "web" / path / "index.html"
        content = page(md_name, path, label, other_path, other_label)
        if check:
            if not out.exists() or out.read_text(encoding="utf-8") != content:
                stale.append(str(out.relative_to(ROOT)))
        else:
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_text(content, encoding="utf-8")
            print(f"escrito {out.relative_to(ROOT)}")
    if stale:
        print("Páginas legais desatualizadas, corre: python3 tool/build_legal_pages.py")
        for s in stale:
            print(f"  {s}")
        sys.exit(1)


if __name__ == "__main__":
    main()
