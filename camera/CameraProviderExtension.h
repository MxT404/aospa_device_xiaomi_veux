// SPDX-License-Identifier: Apache-2.0

#pragma once

#include <cstdint>
#include <string>

bool supportsTorchStrengthControlExt(const std::string& cameraId);
int32_t getTorchMaxStrengthLevelExt();
int setTorchStrengthLevelExt(int32_t torchStrength);
