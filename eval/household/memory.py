"""Peak memory of each setup, and which Mac sizes it fits: results/memory.json.

For each answer model, runs one real question through `holdfast ask` (plain: 8
passages) and `holdfast ask --research` (tool loop: the longest prompts the app
makes) under /usr/bin/time -l, and records macOS's "peak memory footprint" for
the process. On Apple silicon that includes MLX's GPU buffers (unified memory),
the embedder, the reranker and the KV cache, so it is the whole app's model
cost. Stdlib only.

  python3 eval/household/memory.py                 # every model in MODELS
  python3 eval/household/memory.py --only qwen35-4b

Fit rule (assumptions, documented here because they decide the verdict):
- GPU_SHARE: macOS lets the GPU wire about 2/3 of RAM on Macs up to 36 GB
  (Metal's recommendedMaxWorkingSetSize), e.g. ~10.7 GB on a 16 GB Mac.
- OS_AND_APPS_GB: memory left for macOS and a browser/mail at the same time.
- A setup fits a Mac when its peak is under both limits; "tight" within 10%.
Speed on smaller Macs is not measured here: page.py scales tok/s by memory
bandwidth (BANDWIDTH) as a rough estimate.
"""
import argparse, json, os, pathlib, re, subprocess

HERE = pathlib.Path(__file__).parent
ROOT = HERE.parent.parent
BIN = ROOT / ".build/xcode/Build/Products/Release/holdfast"
VAULT = HERE / "vault"
GPU_SHARE = 2 / 3
OS_AND_APPS_GB = 4.0
MACS_GB = [8, 16, 24, 32, 64]
QUESTION = "How much did we spend on groceries in September 2026?"

MODELS = {  # label: repo
    "qwen35-2b": "mlx-community/Qwen3.5-2B-4bit",
    "qwen35-4b": "mlx-community/Qwen3.5-4B-4bit",
    "gemmae2b": "mlx-community/gemma-4-e2b-it-4bit",
    "gemmae4b": "mlx-community/gemma-4-e4b-it-4bit",
    "qwen35-9b": "mlx-community/Qwen3.5-9B-4bit",
    "gptoss20b": "mlx-community/gpt-oss-20b-MXFP4-Q8",
    "gemma26b": "mlx-community/gemma-4-26b-a4b-it-4bit",
    "qwen27b": "mlx-community/Qwen3.8-27B-4bit",
    "gemma31b": "mlx-community/gemma-4-31b-it-4bit",
    "qwen36moe": "mlx-community/Qwen3.6-35B-A3B-4bit",
}


def peak(args, env):
    p = subprocess.run(["/usr/bin/time", "-l", str(BIN), *args], env=env, capture_output=True, text=True, timeout=1800)
    m = re.search(r"(\d+)\s+peak memory footprint", p.stderr)
    tok = re.search(r"answer (\d+) tok at ([\d.]+) tok/s", p.stderr + p.stdout)
    return {"peakGB": int(m.group(1)) / 1e9 if m else None, "tokPerSec": float(tok.group(2)) if tok else None,
            "ok": p.returncode == 0, "tail": (p.stderr or "")[-300:] if p.returncode else ""}


def budget(ram):
    return min(ram * GPU_SHARE, ram - OS_AND_APPS_GB)


def verdict(gb, ram):
    if gb is None:
        return "?"
    b = budget(ram)
    return "fits" if gb <= b * 0.9 else "tight" if gb <= b else "no"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*", default=[])
    a = ap.parse_args()
    out_path = HERE / "results" / "memory.json"
    res = json.loads(out_path.read_text()) if out_path.exists() else {}
    env = dict(os.environ, HOLDFAST_VAULT=str(VAULT), HOLDFAST_TODAY="2026-11-05", HOLDFAST_BACKEND="mlx")
    # Search alone: the floor every setup pays (embedder + reranker + index).
    if not a.only or "search" in a.only:
        res["search"] = {"repo": "Qwen3-Embedding-0.6B + Qwen3-Reranker-0.6B", "plain": peak(["search", QUESTION], env)}
        print("search", res["search"]["plain"]["peakGB"])
    for lab, repo in MODELS.items():
        if a.only and lab not in a.only:
            continue
        e = dict(env, HOLDFAST_MLX_REPO=repo)
        r = {"repo": repo, "plain": peak(["ask", QUESTION], e), "research": peak(["ask", "--research", QUESTION], e)}
        worst = max([x["peakGB"] for x in (r["plain"], r["research"]) if x["peakGB"]] or [0]) or None
        r["fit"] = {str(ram): verdict(worst, ram) for ram in MACS_GB}
        res[lab] = r
        print(lab, f"plain {r['plain']['peakGB']}", f"research {r['research']['peakGB']}", r["fit"])
        out_path.write_text(json.dumps(res, indent=2, sort_keys=True))
    out_path.write_text(json.dumps(res, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
