"""Render the synthetic case reports (cases/*.md) to Word files (docx/*.docx),
so the eval exercises the same .docx import a reviewer's real reports would.
Uses macOS textutil (HTML -> docx); stdlib only."""
import html, pathlib, re, subprocess

HERE = pathlib.Path(__file__).parent
OUT = HERE / "docx"
OUT.mkdir(exist_ok=True)

def md_to_html(md: str) -> str:
    out = []
    for block in re.split(r"\n\s*\n", md.strip()):
        b = block.strip()
        if b.startswith("# "):
            out.append(f"<h1>{html.escape(b[2:])}</h1>")
        elif b.startswith("## "):
            out.append(f"<h2>{html.escape(b[3:])}</h2>")
        elif re.match(r"^\d+\. ", b):
            items = re.split(r"\n(?=\d+\. )", b)
            lis = ["<li>" + html.escape(re.sub(r"^\d+\. ", "", i)) + "</li>" for i in items]
            out.append("<ol>" + "".join(lis) + "</ol>")
        else:
            t = html.escape(b).replace("\n", " ")
            t = re.sub(r"\*(.+?)\*", r"<i>\1</i>", t)
            out.append(f"<p>{t}</p>")
    return "<html><body>" + "\n".join(out) + "</body></html>"

for md in sorted((HERE / "cases").glob("*.md")):
    tmp = OUT / (md.stem + ".html")
    tmp.write_text(md_to_html(md.read_text()))
    subprocess.run(["textutil", "-inputencoding", "UTF-8", "-convert", "docx", str(tmp), "-output", str(OUT / (md.stem + ".docx"))], check=True)
    tmp.unlink()
    print(OUT / (md.stem + ".docx"))
