#!/usr/bin/env python3
"""Check the saved search preference and index transitions in an isolated CLI domain.

Pass --live to exercise the installed embedding model, including interrupted rebuilds.
Only synthetic notes are used; no answer model or network server is contacted.
"""
import argparse
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import tempfile
import threading
import uuid

parser = argparse.ArgumentParser()
parser.add_argument("binary", type=Path)
parser.add_argument("--live", action="store_true")
args = parser.parse_args()
binary = args.binary.resolve()
assert binary.is_file(), binary
domain = "holdfast-meaning-check-" + uuid.uuid4().hex

with tempfile.TemporaryDirectory(prefix=domain + "-") as directory:
    scratch = Path(directory)
    executable = scratch / domain
    shutil.copy2(binary, executable)
    for bundle in binary.parent.glob("*.bundle"):
        (scratch / bundle.name).symlink_to(bundle, target_is_directory=True)
    vault = scratch / "vault"
    sources = vault / "sources"
    sources.mkdir(parents=True)
    first = sources / "orchard.md"
    first.write_text("# Orchard\n\nOrchardquartz: the pear trees need watering every morning during summer.\n")
    stable = sources / "bicycle.md"
    stable.write_text("# Bicycle\n\nThe bicycle chain needs cleaning and a fresh coat of lubricant every month.\n")
    env = {k: v for k, v in os.environ.items() if not k.startswith(("HOLDFAST_", "MACKB_"))}
    env.update(HOLDFAST_VAULT=str(vault), HOLDFAST_PACKS="none", HOLDFAST_RERANK="0")
    index = vault / ".holdfast/index.sqlite"
    missing_model = {"HOLDFAST_EMBED_DIR": str(scratch / "no-model-here")}

    def defaults(*values):
        return subprocess.run(["defaults", *values], capture_output=True, text=True, check=True)

    def run(*values, overrides=None, check=True):
        result = subprocess.run([str(executable), *values], env={**env, **(overrides or {})},
                                capture_output=True, text=True, timeout=180)
        if check:
            assert result.returncode == 0, result.stdout + result.stderr
        return result

    def rows():
        with sqlite3.connect(index) as db:
            return db.execute("SELECT rel_path, ord, text, vec, mtime FROM chunks ORDER BY rel_path, ord").fetchall()

    try:
        defaults("write", domain, "migratedFromMacKB", "-bool", "true")
        # An unconfigured install tries to load the embedding model: the default is on.
        result = run("index", overrides=missing_model, check=False)
        assert result.returncode != 0, "Meaning search should be enabled by default"
        defaults("write", domain, "rerankerOn", "-bool", "true")
        defaults("write", domain, "searchByMeaning", "-bool", "false")
        run("index", overrides=missing_model)
        assert rows() and all(row[3] is None for row in rows())
        assert "Orchardquartz" in run("search", "Orchardquartz", overrides=missing_model).stdout
        run("index", overrides=missing_model)  # A new process must retain the off setting.
        assert defaults("read", domain, "rerankerOn").stdout.strip() == "1"
        print("PASS: default on; saved off survives restart; keyword search works; reranker preference is separate")

        defaults("write", domain, "searchByMeaning", "-bool", "true")
        run("index", overrides={**missing_model, "HOLDFAST_EMBED": "none"})
        assert all(row[3] is None for row in rows())
        print("PASS: HOLDFAST_EMBED=none remains an override")

        if args.live:
            run("index")
            before = rows()
            assert before and all(row[3] for row in before), "Unchanged keyword-only notes need backfill"
            kept = [row for row in before if row[0].endswith("bicycle.md")]
            defaults("write", domain, "searchByMeaning", "-bool", "false")
            first.write_text(first.read_text() + "\nGraftcobalt: prune the pear branches after the harvest.\n")
            timestamp = first.stat().st_mtime + 2
            os.utime(first, (timestamp, timestamp))
            (sources / "rain.md").write_text("# Rain\n\nRain barrels collect water from the roof for the vegetable garden.\n")
            run("index", overrides=missing_model)
            off = rows()
            assert [row for row in off if row[0].endswith("bicycle.md")] == kept
            assert all(row[3] is None for row in off if not row[0].endswith("bicycle.md"))
            assert "Graftcobalt" in run("search", "Graftcobalt", overrides=missing_model).stdout
            print("PASS: off preserves unchanged vectors and indexes new/edited notes by keyword")

            defaults("write", domain, "searchByMeaning", "-bool", "true")
            run("index")
            restored = rows()
            assert all(row[3] for row in restored)
            assert [row for row in restored if row[0].endswith("bicycle.md")] == kept
            assert "Orchard" in run("search", "watering pear trees").stdout
            print("PASS: re-enabling fills missing vectors without re-embedding unchanged complete notes")

            # A stopped full rebuild must retain the last usable keyword and vector index.
            first.write_text(first.read_text() + ("\nThe orchard has trees that need careful watering and pruning. " * 2000))
            process = subprocess.Popen([str(executable), "index", "--force"], env=env,
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            timeout = threading.Timer(180, process.kill)
            timeout.daemon = True
            timeout.start()
            interrupted = False
            try:
                for line in process.stderr:
                    if "indexing " in line:
                        interrupted = True
                        process.terminate()
                        break
                process.communicate(timeout=30)
                assert interrupted, "The test must reach the rebuild before interrupting it"
                assert process.returncode != 0, "The rebuild should have been interrupted"
            finally:
                timeout.cancel()
                if process.poll() is None:
                    process.kill()
                    process.wait()
            assert rows() == restored, "An interrupted rebuild must preserve the prior index"
            assert "Graftcobalt" in run("search", "Graftcobalt", overrides={"HOLDFAST_EMBED": "none"}).stdout
            print("PASS: interrupted rebuild rolls back keyword and vector changes")
    finally:
        subprocess.run(["defaults", "delete", domain], capture_output=True)
