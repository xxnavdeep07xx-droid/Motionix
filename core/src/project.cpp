#include "project.h"

#include <string>

#include "nlohmann/json.hpp"

using nlohmann::json;

namespace motionix {

namespace {

json parseOrThrow(const std::string& s) {
    return json::parse(s);
}

void touch(json& p, int64_t nowMs) {
    p["modifiedMs"] = nowMs;
}

}  // namespace

std::string projectNew(const std::string& name, int64_t nowMs) {
    json p;
    p["format"] = "motionix-project";
    p["version"] = 1;
    p["name"] = name.empty() ? "Untitled" : name;
    p["createdMs"] = nowMs;
    p["modifiedMs"] = nowMs;
    p["timeline"] = json{{"fps", "30/1"}, {"durationUs", int64_t{0}}};
    p["media"] = json::array();
    return p.dump();
}

std::string projectAddMedia(const std::string& projectJson,
                            const std::string& mediaJson) {
    json p = parseOrThrow(projectJson);
    json m = parseOrThrow(mediaJson);

    if (!m.contains("name") || !m.contains("sourcePath") ||
        m["sourcePath"].get<std::string>().empty()) {
        throw std::runtime_error("media item needs name and sourcePath");
    }

    int64_t id = 1;
    for (const auto& existing : p["media"]) {
        id = std::max(id, existing.value("id", int64_t{0}) + 1);
    }
    m["id"] = id;
    int64_t durUs = m.value("durationUs", int64_t{0});
    m["trimInUs"] = int64_t{0};
    m["trimOutUs"] = durUs;
    if (!m.contains("proxyPath")) m["proxyPath"] = "";

    p["media"].push_back(m);

    // First media sets the timeline rate.
    if (p["media"].size() == 1 && m.contains("fpsNum") && m.contains("fpsDen")) {
        p["timeline"]["fps"] =
            std::to_string(m["fpsNum"].get<int64_t>()) + "/" +
            std::to_string(m["fpsDen"].get<int64_t>());
    }
    p["timeline"]["durationUs"] = durUs;
    touch(p, m.value("nowMs", int64_t{0}));
    return p.dump();
}

std::string projectSetTrim(const std::string& projectJson, int64_t mediaId,
                           int64_t inUs, int64_t outUs) {
    json p = parseOrThrow(projectJson);
    bool found = false;
    for (auto& m : p["media"]) {
        if (m.value("id", int64_t{-1}) != mediaId) continue;
        found = true;
        int64_t durUs = m.value("durationUs", int64_t{0});
        int64_t inC = std::clamp(inUs, int64_t{0}, std::max<int64_t>(durUs - 1, 0));
        int64_t outC = std::clamp(outUs, inC + 1, durUs);
        m["trimInUs"] = inC;
        m["trimOutUs"] = outC;
        p["timeline"]["durationUs"] = outC - inC;
        break;
    }
    if (!found) throw std::runtime_error("media id not found");
    return p.dump();
}

std::string projectValidate(const std::string& projectJson) {
    json out;
    try {
        json p = parseOrThrow(projectJson);
        if (p.value("format", "") != "motionix-project")
            throw std::runtime_error("not a motionix-project file");
        if (p.value("version", int64_t{0}) > 1)
            throw std::runtime_error("project version from a newer app");
        if (!p.contains("media") || !p["media"].is_array() ||
            p["media"].empty())
            throw std::runtime_error("project has no media");
        for (const auto& m : p["media"]) {
            if (m.value("sourcePath", "").empty())
                throw std::runtime_error("media item missing sourcePath");
            int64_t in = m.value("trimInUs", int64_t{0});
            int64_t out = m.value("trimOutUs", int64_t{0});
            if (in < 0 || out <= in)
                throw std::runtime_error("invalid trim range on media " +
                                         std::to_string(m.value("id", int64_t{0})));
        }
        out["ok"] = true;
    } catch (const std::exception& e) {
        out["ok"] = false;
        out["error"] = e.what();
    }
    return out.dump();
}

}  // namespace motionix
