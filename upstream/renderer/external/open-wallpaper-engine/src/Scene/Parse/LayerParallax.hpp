#pragma once

#include <cstdint>
#include <nlohmann/json.hpp>
#include <unordered_map>
#include <vector>

namespace wallpaper {

// Parented layers ride the outermost parent's parallax, even when a child
// retains a stale depth in the file. Resolve once before building any material
// slots or effect cards; their existing uniform/reuse paths then agree.
inline void ResolveLayerParallax(nlohmann::json& objects) {
    if (!objects.is_array()) return;
    const auto none = objects.size();
    std::unordered_map<int32_t, std::size_t> by_id;
    for (std::size_t i = 0; i < objects.size(); ++i) {
        const auto& object = objects[i];
        if (!object.contains("id") || !object["id"].is_number_integer()) continue;
        const auto id = object["id"].get<int32_t>();
        if (id == 0) continue;
        auto [entry, inserted] = by_id.emplace(id, i);
        if (!inserted) entry->second = none; // no unambiguous parent
    }

    std::vector<uint8_t> state(objects.size(), 0);
    std::vector<std::size_t> roots(objects.size(), none), path;
    for (std::size_t i = 0; i < objects.size(); ++i) {
        if (state[i] == 2) continue;
        path.clear();
        auto current = i;
        auto root = none;
        while (state[current] == 0) {
            state[current] = 1;
            path.push_back(current);
            const auto& object = objects[current];
            auto parent = by_id.end();
            if (object.contains("parent") && object["parent"].is_number_integer())
                parent = by_id.find(object["parent"].get<int32_t>());
            if (parent == by_id.end() || parent->second == none) {
                root = current;
                break;
            }
            current = parent->second;
        }
        if (state[current] == 2) root = roots[current];
        // A cycle has no root. Leave its depths alone rather than inventing
        // an order-dependent inheritance or recursing indefinitely.
        for (const auto member : path) {
            roots[member] = root;
            state[member] = 2;
        }
    }
    for (std::size_t i = 0; i < objects.size(); ++i) {
        if (roots[i] == none || roots[i] == i) continue;
        objects[i]["parallaxDepth"] = objects[roots[i]].value(
            "parallaxDepth", nlohmann::json::array({0.0f, 0.0f}));
    }
}

} // namespace wallpaper
