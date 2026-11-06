"""Shared helpers for the household-hard fixture generator.

Every generator module writes into VAULT with w(path, text). Text is dedented and
stripped of the leading newline so modules can use triple-quoted blocks.
"""
import os
import textwrap

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))  # eval/household-hard
VAULT = os.path.join(ROOT, "vault")
DROPS = os.path.join(ROOT, "drops")


def _write(base, rel, text, dedent=True):
    if dedent:
        text = textwrap.dedent(text)
    text = text.lstrip("\n")
    if not text.endswith("\n"):
        text += "\n"
    path = os.path.join(base, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    return path


def w(rel, text, dedent=True):
    return _write(VAULT, rel, text, dedent)


def d(rel, text, dedent=True):
    return _write(DROPS, rel, text, dedent)


def table(header, rows):
    out = ["| " + " | ".join(header) + " |", "| " + " | ".join("---" for _ in header) + " |"]
    for r in rows:
        out.append("| " + " | ".join(str(c) for c in r) + " |")
    return "\n".join(out)


def money(x):
    return f"${x:,.2f}" if round(x) != x else f"${x:,.0f}"
