// Motionix core — stable C ABI consumed by Dart through dart:ffi.
//
// Contract:
//   * every string-returning function returns a malloc'd UTF-8 buffer;
//     the Dart side releases it with mx_free_string.
//   * functions never throw across the boundary; failures come back as
//     JSON payloads with ok:false.
#include <cstdlib>
#include <cstring>
#include <string>

#include "proxy_planner.h"
#include "project.h"
#include "rational.h"
#include "timecode.h"

extern "C" {

const char* mx_version() {
    return "motionix-core 0.1.0 (phase 1: engine proof)";
}

void mx_free_string(char* s) {
    std::free(s);
}

static char* dupStr(const std::string& s) {
    char* out = static_cast<char*>(std::malloc(s.size() + 1));
    if (out == nullptr) return nullptr;
    std::memcpy(out, s.c_str(), s.size() + 1);
    return out;
}

const char* mx_timecode(int64_t us, int64_t fpsNum, int64_t fpsDen) {
    // Returns a small static buffer owned by the core; Dart copies it
    // immediately after the call (see bindings.dart).
    thread_local char buf[64];
    std::snprintf(buf, sizeof(buf), "%s", "");
    try {
        auto fps = motionix::Rational::make(fpsNum, fpsDen);
        std::snprintf(buf, sizeof(buf), "%s",
                      motionix::formatTimecode(us, fps));
    } catch (...) {
        std::snprintf(buf, sizeof(buf), "--:--:--:--");
    }
    return buf;
}

char* mx_probe_plan(const char* srcJson) {
    if (srcJson == nullptr)
        return dupStr(R"({"ok":false,"error":"null input"})");
    try {
        return dupStr(motionix::planProxy(srcJson));
    } catch (const std::exception& e) {
        return dupStr(std::string(R"({"ok":false,"error":")") + e.what() + "\"}");
    } catch (...) {
        return dupStr(R"({"ok":false,"error":"unknown"})");
    }
}

char* mx_project_new(const char* name, int64_t nowMs) {
    try {
        return dupStr(motionix::projectNew(name ? name : "", nowMs));
    } catch (const std::exception& e) {
        return dupStr(std::string(R"({"ok":false,"error":")") + e.what() + "\"}");
    }
}

char* mx_project_add_media(const char* projectJson, const char* mediaJson) {
    try {
        return dupStr(motionix::projectAddMedia(projectJson ? projectJson : "",
                                                mediaJson ? mediaJson : ""));
    } catch (const std::exception& e) {
        return dupStr(std::string(R"({"ok":false,"error":")") + e.what() + "\"}");
    }
}

char* mx_project_set_trim(const char* projectJson, int64_t mediaId,
                          int64_t inUs, int64_t outUs) {
    try {
        return dupStr(
            motionix::projectSetTrim(projectJson ? projectJson : "", mediaId,
                                     inUs, outUs));
    } catch (const std::exception& e) {
        return dupStr(std::string(R"({"ok":false,"error":")") + e.what() + "\"}");
    }
}

char* mx_project_validate(const char* projectJson) {
    try {
        return dupStr(motionix::projectValidate(projectJson ? projectJson : ""));
    } catch (const std::exception& e) {
        return dupStr(std::string(R"({"ok":false,"error":")") + e.what() + "\"}");
    }
}

}  // extern "C"
