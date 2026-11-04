#include "proxy_planner.h"

#include <algorithm>
#include <string>

#include "nlohmann/json.hpp"

using nlohmann::json;

namespace motionix {

namespace {

int64_t clampi(int64_t v, int64_t lo, int64_t hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

int64_t roundEven(int64_t v) {
    return (v / 2) * 2;  // encoders want even dimensions
}

}  // namespace

std::string planProxy(const std::string& srcJson) {
    json out;
    try {
        json in = json::parse(srcJson);
        int64_t srcW = in.value("width", int64_t{0});
        int64_t srcH = in.value("height", int64_t{0});
        int64_t fpsNum = in.value("fpsNum", int64_t{30});
        int64_t fpsDen = in.value("fpsDen", int64_t{1});
        int64_t durUs = in.value("durationUs", int64_t{0});
        bool lowRam = in.value("lowRam", false);

        if (srcW <= 0 || srcH <= 0) throw std::runtime_error("bad dimensions");

        double fps = fpsDen > 0 ? double(fpsNum) / double(fpsDen) : 30.0;
        if (fps <= 0) fps = 30.0;

        // Ladder: pick the rung for this device class.
        int64_t rung = lowRam ? 540 : 720;

        // Passthrough: source already light enough — edit it directly.
        bool passthrough = (srcH <= rung);
        int64_t targetH = passthrough ? srcH : std::min(srcH, rung);
        int64_t targetW = passthrough
                              ? srcW
                              : roundEven(srcW * targetH / std::max<int64_t>(srcH, 1));
        targetH = roundEven(targetH);

        // Bitrate from a bits-per-pixel-per-frame budget. 0.10 bpp keeps
        // proxies visually clean for editing without wasting RAM on decode.
        double bpp = lowRam ? 0.085 : 0.10;
        int64_t vbr = clampi(int64_t(double(targetW) * double(targetH) * fps * bpp),
                             1'200'000, 6'000'000);
        int64_t abr = lowRam ? 96'000 : 128'000;

        double durSec = double(durUs) / 1e6;
        double mb = (double(vbr) + double(abr)) * durSec / 8.0 / 1000.0 / 1000.0;

        out["ok"] = true;
        out["targetHeight"] = targetH;
        out["targetWidth"] = targetW;
        out["passthrough"] = passthrough;
        out["videoBitrate"] = vbr;
        out["audioBitrate"] = abr;
        out["ladder"] = passthrough ? "source"
                                    : (std::to_string(targetH) + "p" +
                                       (lowRam ? " (low-RAM)" : ""));
        out["estimatedMb"] = std::lround(mb * 10.0) / 10.0;
        out["reason"] = passthrough
                            ? "source is already within the proxy ladder — editing directly"
                            : (lowRam ? "4GB-class device: 540p proxy, lean bitrate"
                                      : "720p proxy for buttery scrubbing");
    } catch (const std::exception& e) {
        out = json{{"ok", false}, {"error", e.what()}};
    }
    return out.dump();
}

}  // namespace motionix
