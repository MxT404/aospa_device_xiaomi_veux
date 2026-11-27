#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

veux_sync_dependencies() (
    local top plan manifest pending project manifest_paths
    local full_sync=0
    local -a projects=()

    top=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P) || return
    cd -- "$top" || return
    if [[ ! -f .repo/manifest.xml ]]; then
        printf '%s\n' 'veux: Run repo init for AOSPA Calcite before setting up dependencies.' >&2
        return 1
    fi

    # Serialize concurrent envsetup calls while installing the local manifest.
    exec 8>.repo/veux-dependencies.lock
    flock 8 || return
    manifest=.repo/local_manifests/veux.xml
    pending=.repo/veux-full-sync-pending
    if [[ ! -f build/envsetup.sh || -f "$pending" ]]; then
        full_sync=1
    fi
    plan=$(python3 - "$manifest" "$full_sync" <<'PY'
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from xml.etree import ElementTree as ET

source = Path("device/xiaomi/veux")
manifest = Path(sys.argv[1])
full_sync = sys.argv[2] == "1"
document = ET.Element("manifest")

for node in ET.parse(source / "local_manifests/veux.xml").getroot():
    if node.tag == "include":
        document.extend(ET.parse(source / node.attrib["name"]).getroot())
    elif node.get("path") not in {"device/xiaomi/veux", "device/xiaomi/spes"}:
        document.append(node)

def is_checked_out(path):
    checkout = Path(path)
    return (checkout / ".git").exists() and subprocess.run(
        ["git", "-C", path, "rev-parse", "--verify", "HEAD"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    ).returncode == 0

missing = [node.attrib["path"] for node in document.findall("project")
           if not is_checked_out(node.attrib["path"])]
if not missing and not full_sync:
    sys.exit(0)

if not manifest.exists():
    manifest.parent.mkdir(parents=True, exist_ok=True)
    ET.indent(document, space="  ")
    with tempfile.NamedTemporaryFile(dir=manifest.parent, delete=False) as output:
        ET.ElementTree(document).write(output, encoding="utf-8", xml_declaration=True)
    try:
        os.link(output.name, manifest)
        print(f"veux: Installed {manifest}", file=sys.stderr)
    except FileExistsError:
        pass
    finally:
        os.unlink(output.name)

print("\n".join(missing))
PY
    ) || return
    if [[ -z "$plan" && $full_sync == 0 ]]; then
        return 0
    fi

    manifest_paths=$(repo list --all --path-only) || return
    if [[ -n "$plan" ]]; then
        mapfile -t projects <<< "$plan"
        for project in "${projects[@]}"; do
            if ! grep -Fxq -- "$project" <<< "$manifest_paths"; then
                printf 'veux: %s is missing from the active Repo manifest. Check %s.\n' "$project" "$manifest" >&2
                return 1
            fi
        done
    fi

    if (( full_sync )); then
        printf '%s\n' 'veux: Syncing AOSPA Calcite and the device dependencies.'
        : > "$pending"
        repo sync --no-manifest-update -c -j"${VEUX_SYNC_JOBS:-8}" || return
        unlink "$pending"
    else
        printf 'veux: Syncing %s missing device projects.\n' "${#projects[@]}"
        repo sync --no-manifest-update -c -j"${VEUX_SYNC_JOBS:-8}" "${projects[@]}"
    fi
)

veux_build() {
    local top
    top=$(gettop) || return
    "$top/device/xiaomi/veux/tools/build-calcite.sh" "$@"
}

veux_sync_dependencies
