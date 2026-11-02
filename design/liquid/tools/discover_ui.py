"""List UI declarations outside the initial 54-scene map for further review."""

import csv
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parents[1]
SHA = json.loads((ROOT / "research/baseline.json").read_text())["source_commit"]


def discover():
    output = subprocess.run(
        ["git", "grep", "-n", "-E", r"(class|func) [A-Za-z0-9_]*(Controller|Screen)", SHA, "--", "Telegram", "submodules", "*.swift"],
        cwd=REPO, text=True, capture_output=True, check=False,
    )
    if output.returncode not in (0, 1):
        raise RuntimeError(output.stderr)
    known = {row["file"] for row in csv.DictReader((ROOT / "research/CODE_TO_SCREEN_MAP.csv").open())}
    rows = []
    for record in output.stdout.splitlines():
        _, path, line, source = record.split(":", 3)
        declaration = re.search(r"\b(class|func)\s+(\w+(?:Controller|Screen)(?:Impl)?)\b", source)
        if not declaration or source.lstrip().startswith("//"):
            continue
        if declaration[1] == "func" and "ViewController" not in source:
            continue
        rows.append(dict(file=path, line=line, symbol=declaration[2], declaration=declaration[1], mapped_file="YES" if path in known else "NO", status="DISCOVERY_CANDIDATE", source_commit=SHA))
    with (ROOT / "research/UI_DISCOVERY_CANDIDATES.csv").open("w", newline="") as file:
        writer = csv.DictWriter(file, fieldnames=list(rows[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    print(json.dumps({"ui_declarations":len(rows), "outside_mapped_files":sum(row["mapped_file"] == "NO" for row in rows)}))


if __name__ == "__main__":
    discover()
