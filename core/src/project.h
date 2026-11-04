// Motionix core — project model v0.
//
// The .motionix project format is forward-compatible JSON: a format tag plus
// a monotonically increasing version. Phase 1 carries a single media item
// with a trim range; later phases grow the timeline, tracks and the effect
// graph inside the same envelope. Files written today must open in five
// years — that is the whole point of having the model in C++.
#pragma once

#include <cstdint>
#include <string>

namespace motionix {

// Create an empty project envelope.
std::string projectNew(const std::string& name, int64_t nowMs);

// Add a media item (json with name, sourcePath, probe fields). Returns the
// updated project json. First added media seeds the timeline fps.
std::string projectAddMedia(const std::string& projectJson,
                            const std::string& mediaJson);

// Set the trim range of a media item (microseconds, inclusive start /
// exclusive end). Validated against the media duration.
std::string projectSetTrim(const std::string& projectJson, int64_t mediaId,
                           int64_t inUs, int64_t outUs);

// Structural validation: { ok: true } or { ok: false, error: "..." }.
std::string projectValidate(const std::string& projectJson);

}  // namespace motionix
