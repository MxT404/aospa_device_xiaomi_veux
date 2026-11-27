// SPDX-License-Identifier: Apache-2.0

#include "CameraProviderExtension.h"

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>

#define LOG_TAG "CameraProviderExtension"
#include <log/log.h>

namespace {

// Only the main rear camera drives the torch through this flash controller.
constexpr char kTorchStrengthPath[] =
        "/sys/devices/platform/soc/5c1b000.qcom,cci0/"
        "5c1b000.qcom,cci0:qcom,camera-flash@0/torch_strength";

// The stock HAL programs register 0x04 to 0x2c. Allow dimming from that level.
constexpr int32_t kStockTorchStrength = 0x2c;

} // namespace

bool supportsTorchStrengthControlExt(const std::string& cameraId) {
    return cameraId == "0" && access(kTorchStrengthPath, W_OK) == 0;
}

int32_t getTorchMaxStrengthLevelExt() {
    return kStockTorchStrength;
}

int setTorchStrengthLevelExt(int32_t torchStrength) {
    if (torchStrength < 1 || torchStrength > kStockTorchStrength) {
        return -EINVAL;
    }

    const int fd = TEMP_FAILURE_RETRY(open(kTorchStrengthPath, O_WRONLY | O_CLOEXEC));
    if (fd < 0) {
        const int error = errno;
        ALOGE("Could not open torch strength control: %d", error);
        return -error;
    }

    char buffer[16];
    const int length = snprintf(buffer, sizeof(buffer), "%d", torchStrength);
    const ssize_t written = TEMP_FAILURE_RETRY(write(fd, buffer, length));
    const int result = written < 0 ? -errno : (written == length ? 0 : -EIO);
    close(fd);
    if (result != 0) {
        ALOGE("Could not set torch strength %d: %d", torchStrength, result);
    }
    return result;
}
