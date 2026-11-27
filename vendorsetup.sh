#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

veux_build() {
    local top
    top=$(gettop) || return
    "$top/device/xiaomi/veux/tools/build-calcite.sh" "$@"
}
