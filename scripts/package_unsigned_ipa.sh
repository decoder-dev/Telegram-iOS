#!/usr/bin/env bash
# Package an unsigned .ipa from a .app (PrivateMusic2-compatible layout).
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <path-to-app> <output-ipa>" >&2
  exit 2
fi

app_path="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
output_path="$2"

if [[ ! -d "$app_path" || "$app_path" != *.app ]]; then
  echo "invalid .app path: $app_path" >&2
  exit 3
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

mkdir -p "$work_dir/Payload" "$(dirname "$output_path")"
ditto "$app_path" "$work_dir/Payload/$(basename "$app_path")"

(
  cd "$work_dir"
  # Store without compression — same compatibility mode as PrivateMusic2.
  /usr/bin/zip -0 -qry "$output_path" Payload
)

/usr/bin/unzip -t "$output_path" >/dev/null
python3 - "$output_path" <<'PY'
import sys
import zipfile

path = sys.argv[1]
with zipfile.ZipFile(path) as archive:
    if archive.testzip() is not None:
        raise SystemExit("IPA contains a corrupted ZIP entry")
    names = archive.namelist()
    if not names or not all(name.startswith("Payload/") for name in names):
        raise SystemExit("IPA contains files outside Payload")
    if not any(name.endswith(".app/Info.plist") for name in names):
        raise SystemExit("IPA is missing application Info.plist")
    unsupported = [
        info.filename
        for info in archive.infolist()
        if info.compress_type != zipfile.ZIP_STORED
    ]
    if unsupported:
        raise SystemExit(
            "IPA compatibility mode contains compressed entries: "
            + ", ".join(unsupported[:5])
        )
PY
echo "Created $output_path"
