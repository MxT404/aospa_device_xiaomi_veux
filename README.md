Xiaomi POCO X4 Pro 5G / Redmi Note 11E Pro / Redmi Note 11 Pro 5G / Redmi Note 11 Pro+ 5G were announced and released in February 2022.

## Credits

- [acerhizmq](https://github.com/acerhizmq) for the veux device tree and kernel.
- The RisingOS team for its work on the veux base.
- [dereference23](https://github.com/dereference23) for the base device tree.

## Building AOSPA Calcite

Initialize AOSPA Calcite and install the local manifests for this branch.
Git LFS is required for the Xiaomi vendor prebuilts.

```bash
repo init -u https://github.com/AOSPA/manifest -b calcite --depth=1 --git-lfs
mkdir -p .repo/local_manifests/platforms
base=https://raw.githubusercontent.com/MxT404/aospa_device_xiaomi_veux/veux-calcite/local_manifests
curl -fsSL "$base/veux.xml" -o .repo/local_manifests/veux.xml
curl -fsSL "$base/platforms/holi.xml" -o .repo/local_manifests/platforms/holi.xml
repo sync -c
```

Run the device build script from the checkout root.

```bash
device/xiaomi/veux/tools/build-calcite.sh -t userdebug -j24
```

The script applies [the Calcite patches](patches/calcite) and the MIUI Camera
lens-switch fix before invoking `rom-build.sh`. It checks each project and the
camera APK first and skips patches already applied.
If a source revision conflicts, the script reports the affected project before
writing any patches. Run `repo sync` separately before running the script.

Use `--check` to preview the patch status or `--apply-only` to prepare the tree
for a manual `lunch` and `m` build. When the environment loads this device's
`vendorsetup.sh`, `veux_build` invokes the same script.

Device configuration and patches are portable across build machines. Remote
build execution uses the configuration of the machine running the build.

### Signing a release OTA

From the AOSPA checkout root, clone the private signing backup into
`.repo/veux-signing-backup/`. Authenticate with `gh auth login` first if needed.
On a fresh checkout, restore the keys and helper using the passphrase from your
separate backup. If you already restored them on this machine, reuse the
existing `.repo/veux-release-signing/` directory.

```bash
umask 077
set -o pipefail
gh repo clone MxT404/veux-release-signing-backup .repo/veux-signing-backup
mkdir -m 700 .repo/veux-release-signing
gpg --decrypt .repo/veux-signing-backup/veux-release-signing.tar.gpg \
    | tar -xf - -C .repo/veux-release-signing
```

The restore places the full key set in `.repo/veux-release-signing/keys/` and
the helper at `.repo/veux-release-signing/sign-release.py`. Keep the restored
keys private and reuse them for future releases.

Prepare the source and build the target files from the same checkout root.

```bash
device/xiaomi/veux/tools/build-calcite.sh --apply-only
source build/envsetup.sh
lunch aospa_veux-cp2a-user
m otatools target-files-package
```

Sign the target files and generate the OTA.

```bash
umask 077
sign="$PWD/.repo/veux-release-signing"
run=$(mktemp -d "$sign/build.XXXXXXXX")
targets=out/target/product/veux/obj/PACKAGING/target_files_intermediates/aospa_veux-target_files.zip
python3 "$sign/sign-release.py" "$targets" "$run/signed-target_files.zip"

export PATH="$PWD/out/host/linux-x86/bin:$PWD/prebuilts/jdk/jdk21/linux-x86/bin:$PATH"
ota_from_target_files -k "$sign/keys/releasekey" \
    "$run/signed-target_files.zip" "$run/aospa-veux-user-release.zip"
```

The signed OTA is at `$run/aospa-veux-user-release.zip`.

## Dolby

Calcite uses the Dolby audio stack in `hardware/dolby` with the app in
`packages/apps/LunarisDolby`. Dolby Vision is optional and defaults to disabled.
Use `TARGET_INCLUDES_DolbyVision=true` only when bringing up a display that
reports Dolby Vision support.

## Device specifications

| Device           | Xiaomi POCO X4 Pro 5G / Redmi Note 11E Pro / Redmi Note 11 Pro 5G / Redmi Note 11 Pro+ 5G |
| :--------------- | :---------------------------------------------------------------------------------------- |
| CPU              | Octa-core (2x2.2 GHz Kryo 660 Gold & 6x1.7 GHz Kryo 660 Silver)                           |
| SoC              | Qualcomm SM6375 Snapdragon 695 5G (6 nm)                                                  |
| GPU              | Adreno 619                                                                                |
| Memory           | 6 GB / 8 GB                                                                               |
| Shipped Software | Android 11–based MIUI 13                                                                  |
| Storage          | 128 GB / 256 GB                                                                           |
| Battery          | 5000 mAh                                                                                  |
| Dimensions       | 165.1 x 76.4 x 9.3 mm (6.5 x 3.01 x 0.37 in)                                              |
| Display          | 6.67 inches, 107.4 cm2 (~86.0% screen-to-body ratio)                                      |
| Rear Camera      | 108 MP, f/1.9, 26mm (wide), 1/1.52", 0.7µm, PDAF                                          |
|                  | 8 MP, f/2.2, 118˚ (ultrawide)                                                             |
|                  | 2 MP, f/2.4, (macro)                                                                      |
| Front Camera     | 16 MP, f/2.5, (wide), 1/3.06" 1.0µm                                                       |

## Device Picture

![Xiaomi POCO X4 Pro 5G / Redmi Note 11E Pro / Redmi Note 11 Pro 5G / Redmi Note 11 Pro+ 5G](https://raw.githubusercontent.com/Karan-Frost/images/refs/heads/main/veux.png "Xiaomi POCO X4 Pro 5G / Redmi Note 11E Pro / Redmi Note 11 Pro 5G / Redmi Note 11 Pro+ 5G")

## Copyright

```
#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#
```
