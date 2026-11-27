#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

veux_clone_dependency() (
    local path=$1 repository=$2 branch=$3 revision=$4 temporary
    if [[ -e "$path" || -L "$path" ]]; then
        printf 'veux: %s already exists without a usable Git checkout.\n' "$path" >&2
        return 1
    fi

    mkdir -p -- "${path%/*}" || return
    temporary=$(mktemp -d "${path%/*}/.veux-clone.XXXXXXXX") || return
    trap 'python3 -c "import shutil, sys; shutil.rmtree(sys.argv[1], ignore_errors=True)" "$temporary"' EXIT
    git clone --depth 1 --branch "$branch" "https://github.com/$repository.git" "$temporary" || return
    if [[ "$revision" != "$branch" && "$revision" != "refs/heads/$branch" ]]; then
        if ! git -C "$temporary" cat-file -e "$revision^{commit}" 2>/dev/null; then
            git -C "$temporary" fetch --depth 1 origin "$revision" || return
        fi
        git -C "$temporary" checkout --quiet --detach "$revision" || return
    fi
    mv -nT -- "$temporary" "$path" || return
    if [[ -d "$temporary" ]]; then
        printf 'veux: %s appeared while cloning. Its contents were preserved.\n' "$path" >&2
        return 1
    fi
)

veux_sync_dependencies() (
    local top plan manifest pending project manifest_paths method repository branch revision
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

# Clone device projects directly when the active Repo manifest does not own
# them. Repo handles platform overrides and their copyfile/linkfile entries.
registered = set(subprocess.check_output(
    ["repo", "list", "--all", "--path-only"], text=True,
).splitlines())
standalone = {
    "device/xiaomi/camera",
    "hardware/dolby",
    "hardware/qcom-caf/bt",
    "hardware/xiaomi",
    "kernel/xiaomi/veux",
    "packages/apps/LunarisDolby",
    "vendor/xiaomi/camera",
    "vendor/xiaomi/veux",
} - registered

if not manifest.exists():
    overlay = ET.Element("manifest")
    overlay.extend(node for node in document if node.get("path") not in standalone)
    manifest.parent.mkdir(parents=True, exist_ok=True)
    ET.indent(overlay, space="  ")
    with tempfile.NamedTemporaryFile(dir=manifest.parent, delete=False) as output:
        ET.ElementTree(overlay).write(output, encoding="utf-8", xml_declaration=True)
    try:
        os.link(output.name, manifest)
        print(f"veux: Installed {manifest}", file=sys.stderr)
    except FileExistsError:
        pass
    finally:
        os.unlink(output.name)

for node in document.findall("project"):
    path = node.attrib["path"]
    if path not in missing:
        continue
    if path in standalone:
        revision = node.attrib["revision"]
        branch = node.get("upstream", revision).removeprefix("refs/heads/")
        print("clone", path, node.attrib["name"], branch, revision, sep="\t")
    else:
        print("repo", path, sep="\t")
PY
    ) || return
    if [[ -z "$plan" && $full_sync == 0 ]]; then
        return 0
    fi

    manifest_paths=$(repo list --all --path-only) || return
    if [[ -n "$plan" ]]; then
        while IFS=$'\t' read -r method project repository branch revision; do
            if [[ "$method" == clone ]]; then
                veux_clone_dependency "$project" "$repository" "$branch" "$revision" || return
            elif grep -Fxq -- "$project" <<< "$manifest_paths"; then
                projects+=("$project")
            else
                printf 'veux: %s is missing from the active Repo manifest. Check %s.\n' "$project" "$manifest" >&2
                return 1
            fi
        done <<< "$plan"
    fi

    if (( full_sync )); then
        printf '%s\n' 'veux: Syncing AOSPA Calcite and the device dependencies.'
        : > "$pending"
        repo sync --no-manifest-update -c -j"${VEUX_SYNC_JOBS:-8}" || return
        unlink "$pending"
    elif (( ${#projects[@]} )); then
        printf 'veux: Syncing %s missing device projects.\n' "${#projects[@]}"
        repo sync --no-manifest-update -c -j"${VEUX_SYNC_JOBS:-8}" "${projects[@]}"
    fi
)

veux_build() {
    local top
    top=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P) || return
    "$top/device/xiaomi/veux/tools/build-calcite.sh" "$@"
}

veux_setup() {
    local result
    if [[ ${VEUX_VENDORSETUP_SYNCED:-} == 1 ]]; then
        return 0
    fi
    veux_sync_dependencies || return
    if [[ "${1:-}" == --sync-only ]]; then
        return 0
    fi
    if ! result=$(VEUX_VENDORSETUP_SYNCED=1 veux_build --apply-only 2>&1); then
        printf '%s\n' "$result" >&2
        return 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    veux_setup "$@"
else
    veux_setup
fi
