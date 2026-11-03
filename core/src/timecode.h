// Motionix core — SMPTE-style timecode formatting.
#pragma once

#include <cstdint>

#include "rational.h"

namespace motionix {

// Format microseconds as HH:MM:SS:FF at the given frame rate.
// Frame count is rounded, then decomposed — the classic NLE behaviour.
const char* formatTimecode(int64_t us, const Rational& fps);

}  // namespace motionix
