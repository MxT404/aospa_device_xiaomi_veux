#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

case ${1:-} in
    --help|-h)
        cat <<'HELP'
Usage: build-calcite.sh [AOSPA build options]
       build-calcite.sh --check
       build-calcite.sh --apply-only

Run repo sync before this script. Use --check to inspect patches without
applying them, or --apply-only to prepare the checkout without building.
HELP
        exit 0
        ;;
    --check|--apply-only)
        mode=$1
        shift
        if (( $# )); then
            printf 'Unexpected arguments after %s\n' "$mode" >&2
            exit 2
        fi
        ;;
    *) mode=build ;;
esac

for arg in "$@"; do
    case $arg in
        -r|--repo-sync)
            printf 'Run repo sync separately so the patches are applied after syncing.\n' >&2
            exit 2
            ;;
    esac
done

top=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../../.." && pwd -P)
cd -- "$top"
if [[ ! -d .repo || ! -f build/envsetup.sh || ! -x rom-build.sh ]] ||
        ! grep -qFx 'AOSPA_MAJOR_VERSION := calcite' vendor/aospa/target/product/version.mk; then
    printf 'Expected a synced AOSPA Calcite checkout at %s\n' "$top" >&2
    exit 2
fi

exec 9>.repo/veux-calcite-build.lock
if ! flock -n 9; then
    printf 'Another veux build or patch check is using this checkout.\n' >&2
    exit 1
fi

patch_dir=device/xiaomi/veux/patches/calcite
mapfile -d '' patches < <(find "$patch_dir" -name '*.patch' -type f -print0 | sort -z)
if (( ${#patches[@]} == 0 )); then
    printf 'No Calcite patches found in %s\n' "$patch_dir" >&2
    exit 1
fi

pending_projects=()
pending_patches=()
conflicts=0
for patch in "${patches[@]}"; do
    project=${patch#"$patch_dir"/}
    project=${project%.patch}
    update_patch=device/xiaomi/veux/patches/calcite-update/$project.patch
    if ! project_root=$(git -C "$project" rev-parse --show-toplevel 2>/dev/null) ||
            [[ "$project_root" != "$top/$project" ]]; then
        printf 'Missing source project: %s\n' "$project" >&2
        conflicts=1
    elif git -C "$project" apply --whitespace=nowarn --reverse --check "$top/$patch" 2>/dev/null; then
        printf 'Already present: %s\n' "$project"
    elif details=$(git -C "$project" apply --whitespace=nowarn --check "$top/$patch" 2>&1); then
        printf 'Ready to apply: %s\n' "$project"
        pending_projects+=("$project")
        pending_patches+=("$patch")
    elif [[ -f $update_patch ]] &&
            git -C "$project" apply --whitespace=nowarn --check "$top/$update_patch" 2>/dev/null; then
        printf 'Ready to update: %s\n' "$project"
        pending_projects+=("$project")
        pending_patches+=("$update_patch")
    else
        printf 'Cannot apply %s\n%s\n' "$patch" "$details" >&2
        conflicts=1
    fi
done

if (( conflicts )); then
    printf 'Patch check failed before any changes were applied.\n' >&2
    exit 1
fi

miuicamera=vendor/xiaomi/camera/proprietary/system/priv-app/MiuiCamera/MiuiCamera.apk
camera_patch=device/xiaomi/veux/tools/patch-miuicamera.py
python3 "$camera_patch" --check "$miuicamera"

if [[ $mode == --check ]]; then
    exit 0
fi

for i in "${!pending_projects[@]}"; do
    project=${pending_projects[i]}
    patch=${pending_patches[i]}
    git -C "$project" apply --whitespace=nowarn "$top/$patch"
    printf 'Applied: %s\n' "$project"
done

python3 "$camera_patch" "$miuicamera"

if [[ $mode == --apply-only ]]; then
    exit 0
fi

exec ./rom-build.sh veux "$@"
