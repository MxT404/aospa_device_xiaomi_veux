#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0

"""Make the bundled MIUI Camera's lens-switch animation tolerate a missing flag."""

import argparse
from copy import copy
import hashlib
import os
from pathlib import Path
import shutil
import struct
import tempfile
import zipfile
import zlib


DEX_ENTRY = "classes2.dex"
ORIGINAL_SHA256 = "2ddacf05215f13bc4df1dbd1919faf8cadd3f187f3c7357876ddfe1b1b9aed3b"
PATCHED_SHA256 = "3bad4cfe65ec729eedf70293c0886ba432bb992afb01771bf31cabb0959e41aa"
SIGNATURE_ENTRIES = {"META-INF/MANIFEST.MF", "META-INF/PLATFORM.SF", "META-INF/PLATFORM.RSA"}

# RenderEngineV1.t0, ANIMATION_MODULE_SWITCH, in the hash-pinned vendor DEX.
# Replace check-cast and Boolean.booleanValue() with Boolean.TRUE.equals(flag).
# The same-width instructions preserve all code offsets and the call to p3.P(Z).
ORIGINAL_CODE = bytes.fromhex("1f03 0b24 6e10 c1f6 0300 0a01 6e20 dd80 1200")
PATCHED_CODE = bytes.fromhex("6200 cde8 6e20 c2f6 3000 0a01 6e20 dd80 1200")


def patch(apk, check):
    with zipfile.ZipFile(apk) as original:
        dex = original.read(DEX_ENTRY)
        checksum = hashlib.sha256(dex).hexdigest()
        if checksum == PATCHED_SHA256:
            print("Already present: MIUI Camera lens-switch fix")
            return
        if checksum != ORIGINAL_SHA256:
            raise ValueError(f"Unsupported MIUI Camera {DEX_ENTRY} SHA-256 {checksum}")
        if check:
            print("Ready to apply: MIUI Camera lens-switch fix")
            return

        if dex.count(ORIGINAL_CODE) != 1:
            raise ValueError("Expected one match for the MIUI Camera animation code")
        modified = bytearray(dex.replace(ORIGINAL_CODE, PATCHED_CODE))
        modified[12:32] = hashlib.sha1(memoryview(modified)[32:]).digest()
        struct.pack_into("<I", modified, 8, zlib.adler32(memoryview(modified)[12:]))
        if hashlib.sha256(modified).hexdigest() != PATCHED_SHA256:
            raise ValueError("Unexpected SHA-256 after patching the MIUI Camera DEX")

        with tempfile.TemporaryDirectory(prefix=".veux-camera-", dir=apk.parent) as temp:
            staged = Path(temp) / apk.name
            with zipfile.ZipFile(staged, "w") as output:
                output.comment = original.comment
                for entry in original.infolist():
                    # Soong aligns the archive and signs it with the platform key.
                    if entry.filename in SIGNATURE_ENTRIES:
                        continue
                    if entry.filename == DEX_ENTRY:
                        output.writestr(copy(entry), modified)
                        continue
                    with original.open(entry) as source, output.open(copy(entry), "w") as dest:
                        shutil.copyfileobj(source, dest)
            with zipfile.ZipFile(staged) as output:
                if output.testzip() is not None:
                    raise ValueError("The patched MIUI Camera APK failed ZIP validation")
            shutil.copymode(apk, staged)
            os.replace(staged, apk)
    print("Applied: MIUI Camera lens-switch fix")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("apk", type=Path)
    args = parser.parse_args()
    try:
        patch(args.apk, args.check)
    except (OSError, ValueError, KeyError, zipfile.BadZipFile) as error:
        parser.exit(1, f"{args.apk}: {error}\n")


if __name__ == "__main__":
    main()
