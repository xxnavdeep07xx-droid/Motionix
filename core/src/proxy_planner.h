// Motionix core — the proxy planner.
//
// The heart of the "4 GB RAM" promise: given a source clip and the device's
// memory class, decide the proxy ladder rung, bitrate budget and audio rate.
// A good proxy makes scrubbing buttery on cheap phones while the original
// file stays untouched for full-quality export.
#pragma once

#include <cstdint>
#include <string>

namespace motionix {

// src_json fields: width, height, fpsNum, fpsDen, durationUs, lowRam (bool).
// Returns a plan json string:
//   { ok, targetHeight, targetWidth, passthrough, videoBitrate,
//     audioBitrate, ladder, estimatedMb, reason }
std::string planProxy(const std::string& srcJson);

}  // namespace motionix
