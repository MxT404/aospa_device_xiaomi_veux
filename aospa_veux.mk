#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#

# Inherit from framework configuration.
TARGET_BUILD_VANILLA ?= false
TARGET_USES_AOSP_WEBVIEW := true
PRODUCT_GMS_CLIENTID_BASE := android-xiaomi
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)
TARGET_SUPPORTS_OMX_SERVICE := false
$(call inherit-product, $(SRC_TARGET_DIR)/product/aosp_base_telephony.mk)

# Inherit from veux device configuration.
$(call inherit-product, device/xiaomi/veux/device.mk)

# Inherit from common AOSPA configuration.
$(call inherit-product, vendor/aospa/target/product/aospa-target.mk)

PRODUCT_PRODUCT_PROPERTIES += \
    ro.product.mod_device=veux_global \
    ro.miui.ui.version.name=V140 \
    ro.miui.ui.version.code=13 \
    ro.build.product=veux

# Boot animation
TARGET_SCREEN_HEIGHT := 2400
TARGET_SCREEN_WIDTH := 1080
TARGET_BOOT_ANIMATION_RES := 1080

PRODUCT_BRAND := Redmi
PRODUCT_DEVICE := veux
PRODUCT_MANUFACTURER := Xiaomi
PRODUCT_MODEL := 2201116SG
PRODUCT_NAME := aospa_veux

PRODUCT_BUILD_PROP_OVERRIDES += \
    BuildDesc="veux_eea-user 13 TKQ1.221114.001 V816.0.13.0.TKCEUXM release-keys" \
    BuildFingerprint=Redmi/veux_eea/veux:13/TKQ1.221114.001/V816.0.13.0.TKCEUXM:user/release-keys \
    DeviceProduct=veux_eea
