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

veux_use_published_commit() (
    local path=$1 repository=$2 revision=$3 head url
    local -a fetch_options=(--no-tags --no-write-fetch-head)
    head=$(git -C "$path" rev-parse --verify HEAD) || return
    [[ "$head" != "$revision" ]] || return 0
    url="https://github.com/$repository.git"

    if [[ $(git -C "$path" rev-parse --is-shallow-repository) == true ]]; then
        fetch_options+=(--depth=32)
    fi
    if ! git -C "$path" cat-file -e "$revision^{commit}" 2>/dev/null ||
            { ! git -C "$path" merge-base --is-ancestor "$head" "$revision" &&
              ! git -C "$path" merge-base --is-ancestor "$revision" "$head"; }; then
        git -C "$path" fetch "${fetch_options[@]}" "$url" "$revision" || return
    fi
    if git -C "$path" merge-base --is-ancestor "$revision" "$head"; then
        return 0
    fi
    if ! git -C "$path" merge-base --is-ancestor "$head" "$revision"; then
        printf 'veux: %s cannot fast-forward from %s to the published %s.\n' "$path" "$head" "$revision" >&2
        return 1
    fi
    if ! git -C "$path" diff --cached --quiet; then
        printf 'veux: %s has staged changes. Resolve them before setup can update it.\n' "$path" >&2
        return 1
    fi
    if git -C "$path" diff --quiet; then
        git -C "$path" -c "lfs.url=$url/info/lfs" merge --quiet --ff-only "$revision" || return
    elif git -C "$path" diff --quiet "$revision" --; then
        # Earlier setup applied the published content as a patch. Record the
        # commit without rewriting that identical working tree.
        git -C "$path" reset --mixed --quiet "$revision" || return
    else
        printf 'veux: %s has local edits that differ from the published commit.\n' "$path" >&2
        return 1
    fi
    printf 'veux: %s is at published commit %s.\n' "$path" "$revision"
)

veux_sync_dependencies() (
    local top plan manifest pending project manifest_paths method repository branch revision record
    local full_sync=0
    local -a projects=() updates=()

    top=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P) || return
    cd -- "$top" || return
    if [[ ! -f .repo/manifest.xml ]]; then
        printf '%s\n' 'veux: Run repo init for AOSPA Calcite before setting up dependencies.' >&2
        return 1
    fi
    if [[ ${VEUX_USE_RBE_FORKS:-} == 1 ]] &&
            [[ ! -x prebuilts/remoteexecution-client/buildbuddyfix/rewrapper ||
               ! -x prebuilts/remoteexecution-client/buildbuddyfix/reproxy ]]; then
        printf '%s\n' 'veux: Install the BuildBuddy reclient before enabling the RBE forks.' >&2
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

def checked_out_commit(path):
    if not (Path(path) / ".git").exists():
        return None
    result = subprocess.run(
        ["git", "-C", path, "rev-parse", "--verify", "HEAD"],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
    )
    return result.stdout.strip() if result.returncode == 0 else None

projects = document.findall("project")
heads = {node.attrib["path"]: checked_out_commit(node.attrib["path"])
         for node in projects}
missing = {path for path, head in heads.items() if head is None}
if not missing and not full_sync and all(
    heads[node.attrib["path"]] == node.attrib["revision"] for node in projects
):
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

for node in projects:
    path = node.attrib["path"]
    revision = node.attrib["revision"]
    repository = node.attrib["name"]
    branch = node.attrib["upstream"].removeprefix("refs/heads/")
    if path in missing:
        if path in standalone:
            print("clone", path, repository, branch, revision, sep="\t")
        else:
            print("repo", path, sep="\t")
    if full_sync or heads[path] != revision:
        print("update", path, repository, branch, revision, sep="\t")
PY
    ) || return
    if [[ -n "$plan" ]]; then
        manifest_paths=$(repo list --all --path-only) || return
        while IFS=$'\t' read -r method project repository branch revision; do
            if [[ "$method" == clone ]]; then
                veux_clone_dependency "$project" "$repository" "$branch" "$revision" || return
            elif [[ "$method" == update ]]; then
                updates+=("$project"$'\t'"$repository"$'\t'"$revision")
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
        unlink "$pending" || return
    elif (( ${#projects[@]} )); then
        printf 'veux: Syncing %s missing device projects.\n' "${#projects[@]}"
        repo sync --no-manifest-update -c -j"${VEUX_SYNC_JOBS:-8}" "${projects[@]}" || return
    fi

    for record in "${updates[@]}"; do
        IFS=$'\t' read -r project repository revision <<< "$record"
        veux_use_published_commit "$project" "$repository" "$revision" || return
    done
    if [[ ${VEUX_USE_RBE_FORKS:-} == 1 ]]; then
        veux_use_published_commit build/make MxT404/android_build 657bbbf6175fa7451bae5eba518ef3055e3bc057 || return
        veux_use_published_commit build/soong MxT404/android_build_soong 8bd3b6bc033fe34ea1903c45e8e0f3dcd4508c27
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
