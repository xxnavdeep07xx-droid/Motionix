#include "timecode.h"

#include <cmath>
#include <cstdio>

namespace motionix {

const char* formatTimecode(int64_t us, const Rational& fps) {
    // Thread-local buffer: returned pointer is valid until the next call
    // on the same thread. Callers copy into Dart strings immediately.
    thread_local char buf[32];

    double fpsD = fps.toDouble();
    if (fpsD <= 0.0) fpsD = 30.0;
    int fpsInt = static_cast<int>(std::lround(fpsD));
    if (fpsInt <= 0) fpsInt = 30;

    double seconds = static_cast<double>(us) / 1000000.0;
    int64_t totalFrames = static_cast<int64_t>(std::llround(seconds * fpsD));
    if (totalFrames < 0) totalFrames = 0;

    int64_t ff = totalFrames % fpsInt;
    int64_t totalSecs = totalFrames / fpsInt;
    int64_t ss = totalSecs % 60;
    int64_t mm = (totalSecs / 60) % 60;
    int64_t hh = totalSecs / 3600;

    std::snprintf(buf, sizeof(buf), "%02lld:%02lld:%02lld:%02lld",
                  static_cast<long long>(hh), static_cast<long long>(mm),
                  static_cast<long long>(ss), static_cast<long long>(ff));
    return buf;
}

}  // namespace motionix
