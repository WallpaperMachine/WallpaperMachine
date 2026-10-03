#include "Text/TextLayer.hpp"
#include "Text/SystemFontResolver.hpp"

#include <algorithm>
#include <atomic>
#include <array>
#include <cmath>
#include <functional>
#include <fstream>
#include <memory>
#include <mutex>
#include <optional>
#include <span>
#include <string_view>
#include <type_traits>
#include <utility>

#include <ft2build.h>
#include FT_FREETYPE_H

namespace wallpaper
{

namespace
{
constexpr float kWallpaperEnginePointSizeToPx = 4.0f;
#ifdef WESCENE_BUILD_TESTS
std::atomic_uint64_t g_measurement_count { 0 };
#endif
std::mutex g_freetype_mutex;

class FtLibrary {
public:
    static FtLibrary& Get() {
        static FtLibrary instance;
        return instance;
    }

    FT_Library handle() const { return m_library; }

private:
    FtLibrary() {
        if (FT_Init_FreeType(&m_library) != 0) m_library = nullptr;
    }

    ~FtLibrary() {
        if (m_library != nullptr) FT_Done_FreeType(m_library);
    }

    FtLibrary(const FtLibrary&)            = delete;
    FtLibrary& operator=(const FtLibrary&) = delete;

    FT_Library m_library { nullptr };
};

struct FtFaceDeleter {
    void operator()(FT_Face face) const {
        if (face != nullptr) FT_Done_Face(face);
    }
};

FT_UInt FreeTypePixelSize(float point_size) {
    if (! std::isfinite(point_size) || point_size <= 0.0f) point_size = 12.0f;
    return static_cast<FT_UInt>(
        std::clamp(std::lround(point_size * kWallpaperEnginePointSizeToPx), 1l, 1024l));
}

struct GlyphRun {
    uint32_t codepoint { 0 };
    float    advance { 0.0f };
    bool     fallback { false };
    float    left { 0.0f };
    float    right { 0.0f };
    bool     has_ink { false };
};

struct LineRun {
    std::vector<GlyphRun> glyphs;
    float                 advance_width { 0.0f };
    float                 bounds_left { 0.0f };
    float                 bounds_right { 0.0f };
    bool                  has_bounds { false };

    float ExtentLeft() const { return has_bounds ? std::min(0.0f, bounds_left) : 0.0f; }
    float ExtentRight() const {
        return has_bounds ? std::max(advance_width, bounds_right) : advance_width;
    }
    float LayoutWidth() const { return ExtentRight() - ExtentLeft(); }
};

uint8_t ColorByte(float value) {
    if (! std::isfinite(value)) value = 1.0f;
    value = std::clamp(value, 0.0f, 1.0f);
    return static_cast<uint8_t>(std::lround(value * 255.0f));
}

std::array<uint8_t, 4> TextColorBytes(const TextLayerState& state) {
    const float brightness =
        std::isfinite(state.brightness) ? std::max(0.0f, state.brightness) : 1.0f;
    return {
        ColorByte(state.color.x() * brightness),
        ColorByte(state.color.y() * brightness),
        ColorByte(state.color.z() * brightness),
        ColorByte(state.alpha),
    };
}

std::vector<uint8_t> ReadFileBytes(std::string_view path) {
    if (path.empty()) return {};
    std::ifstream file(std::string(path), std::ios::binary | std::ios::ate);
    if (! file) return {};

    const auto size = file.tellg();
    if (size <= 0) return {};
    file.seekg(0, std::ios::beg);

    std::vector<uint8_t> data(static_cast<std::size_t>(size));
    if (! file.read(reinterpret_cast<char*>(data.data()), size)) {
        return {};
    }
    return data;
}

std::unique_ptr<std::remove_pointer_t<FT_Face>, FtFaceDeleter>
CreateFreeTypeFaceFromBytes(const std::vector<uint8_t>& data, float point_size) {
    FT_Library library = FtLibrary::Get().handle();
    if (library == nullptr) return nullptr;
    if (data.empty()) return nullptr;

    FT_Face raw_face = nullptr;
    if (FT_New_Memory_Face(library,
                           reinterpret_cast<const FT_Byte*>(data.data()),
                           static_cast<FT_Long>(data.size()),
                           0,
                           &raw_face) != 0) {
        return nullptr;
    }

    const auto pixel_size = FreeTypePixelSize(point_size);
    if (FT_Set_Pixel_Sizes(raw_face, 0, pixel_size) != 0) {
        FT_Done_Face(raw_face);
        return nullptr;
    }
    return std::unique_ptr<std::remove_pointer_t<FT_Face>, FtFaceDeleter>(raw_face);
}

std::unique_ptr<std::remove_pointer_t<FT_Face>, FtFaceDeleter>
CreateFreeTypeFace(const TextLayerState& state, std::vector<uint8_t>& owned_data) {
    // Keep an authored, usable font first. A package can also contain a broken
    // font, or a previously resolved file can disappear before rasterization.
    // Recover at the decoder boundary so measurement and rasterization choose
    // the same real face in all of these cases, not placeholder rectangles.
    if (! state.resolved_font_data.empty()) {
        if (auto face = CreateFreeTypeFaceFromBytes(state.resolved_font_data.bytes(), state.point_size)) {
            return face;
        }
    } else if (! state.resolved_font_path.empty()) {
        owned_data = ReadFileBytes(state.resolved_font_path);
        if (auto face = CreateFreeTypeFaceFromBytes(owned_data, state.point_size)) return face;
    }
#ifdef __APPLE__
    for (const auto& key : {state.font_key, std::string("systemfont_sansserif")}) {
        const auto path = ResolveSystemFontPath(key);
        if (path.empty()) continue;
        owned_data = ReadFileBytes(path);
        if (auto face = CreateFreeTypeFaceFromBytes(owned_data, state.point_size)) return face;
    }
#endif
    return nullptr;
}

struct FallbackFace {
    std::vector<uint8_t>                                           data;
    std::unique_ptr<std::remove_pointer_t<FT_Face>, FtFaceDeleter> face;
};

std::optional<FallbackFace> CreateFallbackFace(const TextLayerState& state) {
#ifdef __APPLE__
    for (std::string_view key :
         { "systemfont_PingFang SC", "systemfont_Arial Unicode MS", "systemfont_Helvetica" }) {
        const auto path = ResolveSystemFontPath(key);
        if (path.empty() || path == state.resolved_font_path) continue;

        FallbackFace fallback {
            .data = ReadFileBytes(path),
            .face = {},
        };
        fallback.face = CreateFreeTypeFaceFromBytes(fallback.data, state.point_size);
        if (fallback.face != nullptr) return fallback;
    }
#else
    (void)state;
#endif
    return std::nullopt;
}

std::vector<uint32_t> DecodeUtf8(std::string_view text) {
    std::vector<uint32_t> codepoints;
    codepoints.reserve(text.size());

    std::size_t index = 0;
    while (index < text.size()) {
        const auto  first     = static_cast<uint8_t>(text[index]);
        uint32_t    codepoint = 0;
        std::size_t extra     = 0;

        if (first < 0x80u) {
            codepoint = first;
        } else if ((first & 0xE0u) == 0xC0u) {
            codepoint = first & 0x1Fu;
            extra     = 1;
        } else if ((first & 0xF0u) == 0xE0u) {
            codepoint = first & 0x0Fu;
            extra     = 2;
        } else if ((first & 0xF8u) == 0xF0u) {
            codepoint = first & 0x07u;
            extra     = 3;
        } else {
            codepoints.push_back(0xFFFDu);
            ++index;
            continue;
        }

        if (index + extra >= text.size()) {
            codepoints.push_back(0xFFFDu);
            break;
        }

        bool valid = true;
        for (std::size_t offset = 1; offset <= extra; ++offset) {
            const auto next = static_cast<uint8_t>(text[index + offset]);
            if ((next & 0xC0u) != 0x80u) {
                valid = false;
                break;
            }
            codepoint = (codepoint << 6u) | (next & 0x3Fu);
        }
        if (! valid) {
            codepoints.push_back(0xFFFDu);
            ++index;
            continue;
        }

        codepoints.push_back(codepoint);
        index += extra + 1u;
    }
    return codepoints;
}

bool ContainsSubstring(std::string_view value, std::string_view needle) {
    return value.find(needle) != std::string_view::npos;
}

float HorizontalLineStart(const TextLayerState& state, float line_width, float padding,
                          uint32_t width) {
    const std::string_view align = state.horizontal_align;
    if (ContainsSubstring(align, "right")) {
        return std::max(0.0f, static_cast<float>(width) - padding - line_width);
    }
    if (ContainsSubstring(align, "center") || align.empty()) {
        return std::max(padding, (static_cast<float>(width) - line_width) * 0.5f);
    }
    return padding;
}

void AppendGlyphMetrics(LineRun& line, const GlyphRun& glyph) {
    if (glyph.has_ink) {
        const auto left = line.advance_width + glyph.left;
        const auto right = line.advance_width + glyph.right;
        if (! line.has_bounds) {
            line.bounds_left = left;
            line.bounds_right = right;
            line.has_bounds = true;
        } else {
            line.bounds_left = std::min(line.bounds_left, left);
            line.bounds_right = std::max(line.bounds_right, right);
        }
    }
    line.advance_width += glyph.advance;
}

void AppendMeasuredGlyph(LineRun& line, const GlyphRun& glyph) {
    AppendGlyphMetrics(line, glyph);
    line.glyphs.push_back(glyph);
}

std::optional<GlyphRun> MeasureGlyph(FT_Face primary_face, FT_Face fallback_face, uint32_t codepoint) {
    FT_Face face     = primary_face;
    bool    fallback = false;
    if (FT_Get_Char_Index(face, codepoint) == 0u && fallback_face != nullptr &&
        FT_Get_Char_Index(fallback_face, codepoint) != 0u) {
        face     = fallback_face;
        fallback = true;
    }
    if (FT_Get_Char_Index(face, codepoint) == 0u) return std::nullopt;
    if (FT_Load_Char(face, codepoint, FT_LOAD_RENDER | FT_LOAD_TARGET_NORMAL) != 0) return std::nullopt;

    const FT_GlyphSlot slot        = face->glyph;
    const float        glyph_left  = static_cast<float>(slot->bitmap_left);
    const float        glyph_right = glyph_left + static_cast<float>(slot->bitmap.width);
    const float advance = static_cast<float>(slot->advance.x) / 64.0f;
    return GlyphRun { codepoint, advance, fallback, glyph_left, glyph_right,
                      slot->bitmap.width > 0u && slot->bitmap.rows > 0u };
}

float TextWidthLimit(const TextLayerState& state) {
    if (! state.limit_width || ! std::isfinite(state.max_width) || state.max_width <= 0.0f) return 0.0f;
    return std::max(1.0f, state.max_width - 2.0f * std::max(0.0f, state.padding));
}

LineRun MakeLine(std::span<const GlyphRun> glyphs) {
    LineRun line;
    for (const auto& glyph : glyphs) AppendMeasuredGlyph(line, glyph);
    return line;
}

bool BreakSpace(const GlyphRun& glyph) { return glyph.codepoint == ' ' || glyph.codepoint == '\t'; }

template<typename Measure>
std::vector<LineRun> BuildLineRuns(const TextLayerState& state, Measure measure) {
    std::vector<LineRun> lines;
    lines.emplace_back();
    const float width_limit = TextWidthLimit(state);
    const size_t row_limit = state.limit_rows && state.max_rows != 0 ? state.max_rows : SIZE_MAX;
    bool omitted = false;
    for (uint32_t codepoint : DecodeUtf8(state.text)) {
        if (codepoint == '\n') {
            if (lines.size() == row_limit) { omitted = true; break; }
            lines.emplace_back();
            continue;
        }
        if (codepoint == '\r') continue;
        auto glyph = measure(codepoint);
        if (! glyph) continue;
        AppendMeasuredGlyph(lines.back(), *glyph);
        if (width_limit == 0.0f || lines.back().LayoutWidth() <= width_limit || lines.back().glyphs.size() == 1) continue;

        auto& current = lines.back();
        size_t split = current.glyphs.size() - 1;
        if (! BreakSpace(current.glyphs.back())) {
            for (size_t index = split; index > 0; --index) {
                if (BreakSpace(current.glyphs[index - 1])) { split = index; break; }
            }
        }
        std::vector<GlyphRun> carry(current.glyphs.begin() + split, current.glyphs.end());
        current.glyphs.resize(split);
        while (! current.glyphs.empty() && BreakSpace(current.glyphs.back())) current.glyphs.pop_back();
        current = MakeLine(current.glyphs);
        if (lines.size() == row_limit) { omitted = true; break; }
        while (! carry.empty() && BreakSpace(carry.front())) carry.erase(carry.begin());
        lines.push_back(MakeLine(carry));
    }
    if (omitted && state.use_ellipsis) {
        auto& line = lines.back();
        while (! line.glyphs.empty() && BreakSpace(line.glyphs.back())) line.glyphs.pop_back();
        std::vector<GlyphRun> marker;
        if (auto glyph = measure(0x2026)) marker.push_back(*glyph);
        else if (auto dot = measure('.')) marker.assign(3, *dot);
        // Prefix metrics make fitting a suffix linear even for a long row.
        std::vector<LineRun> prefix(1);
        for (const auto& glyph : line.glyphs) {
            auto metrics = prefix.back();
            AppendGlyphMetrics(metrics, glyph);
            prefix.push_back(std::move(metrics));
        }
        size_t count = line.glyphs.size();
        while (true) {
            auto candidate = prefix[count];
            for (const auto& glyph : marker) AppendGlyphMetrics(candidate, glyph);
            if (width_limit == 0.0f || candidate.LayoutWidth() <= width_limit) break;
            if (count == 0) { marker.clear(); break; }
            --count;
        }
        line = MakeLine(std::span<const GlyphRun>(line.glyphs).first(count));
        for (const auto& glyph : marker) AppendMeasuredGlyph(line, glyph);
    }
    return lines;
}

std::vector<LineRun> BuildFreeTypeLines(const TextLayerState& state, FT_Face face, FT_Face fallback) {
    return BuildLineRuns(state, [&](uint32_t codepoint) { return MeasureGlyph(face, fallback, codepoint); });
}

float FirstBaselineY(const TextLayerState& state, FT_Face face, std::size_t line_count,
                     float padding, uint32_t height) {
    const auto  metrics     = face->size->metrics;
    const float ascender    = static_cast<float>(metrics.ascender) / 64.0f;
    const float descender   = static_cast<float>(metrics.descender) / 64.0f;
    const float line_height = std::max(1.0f, static_cast<float>(metrics.height) / 64.0f);
    const float text_height =
        (ascender - descender) +
        static_cast<float>(line_count > 0 ? line_count - 1u : 0u) * line_height;
    const float content_height = std::max(0.0f, static_cast<float>(height) - padding * 2.0f);
    const std::string_view align =
        state.vertical_align.empty() ? state.anchor : state.vertical_align;

    float top = padding;
    if (ContainsSubstring(align, "bottom")) {
        top = padding + std::max(0.0f, content_height - text_height);
    } else if (ContainsSubstring(align, "center") || ContainsSubstring(align, "middle")) {
        top = padding + std::max(0.0f, (content_height - text_height) * 0.5f);
    }

    return top + ascender;
}

std::vector<LineRun> BuildFallbackLines(const TextLayerState& state) {
    const float pixels = static_cast<float>(FreeTypePixelSize(state.point_size));
    return BuildLineRuns(state, [pixels](uint32_t codepoint) -> std::optional<GlyphRun> {
        const float advance = std::max(1.0f, pixels * 0.6f);
        const float ink = std::max(1.0f, pixels * 0.45f);
        return GlyphRun {codepoint, codepoint == '\t' ? advance * 4.0f : advance, false,
                         0.0f, ink, codepoint != ' ' && codepoint != '\t'};
    });
}

Eigen::Vector2f MeasureFallbackText(const TextLayerState& state) {
    const auto lines = BuildFallbackLines(state);
    const float pixels = static_cast<float>(FreeTypePixelSize(state.point_size));
    const float padding = std::max(0.0f, std::isfinite(state.padding) ? state.padding : 0.0f);
    float width = 0.0f;
    for (const auto& line : lines) width = std::max(width, line.LayoutWidth());
    width += padding * 2.0f;
    if (TextWidthLimit(state) > 0.0f) width = std::min(width, state.max_width);
    return {std::max(1.0f, width), std::max(1.0f, float(lines.size()) * pixels * 1.2f + padding * 2.0f)};
}

void RasterizeFallbackText(const TextLayerState& state, uint32_t width, uint32_t height,
                           std::vector<uint8_t>& rgba) {
    const auto color = TextColorBytes(state);
    const auto lines = BuildFallbackLines(state);
    const float pixels = static_cast<float>(FreeTypePixelSize(state.point_size));
    const float glyph_height = std::max(1.0f, pixels * 0.9f);
    const float line_height = std::max(1.0f, pixels * 1.2f);
    const float padding = std::max(0.0f, std::isfinite(state.padding) ? state.padding : 0.0f);
    float top = padding;
    const auto align = state.vertical_align.empty() ? state.anchor : state.vertical_align;
    const float room = std::max(0.0f, float(height) - 2.0f * padding - float(lines.size()) * line_height);
    if (ContainsSubstring(align, "bottom")) top += room;
    else if (ContainsSubstring(align, "center") || ContainsSubstring(align, "middle")) top += room * 0.5f;
    for (const auto& line : lines) {
        const float limit = TextWidthLimit(state);
        const float line_width = limit > 0.0f ? std::min(limit, line.LayoutWidth()) : line.LayoutWidth();
        float pen = HorizontalLineStart(state, line_width, padding, width);
        const float right_edge = limit > 0.0f ? std::min(float(width), pen + limit) : float(width);
        for (const auto& glyph : line.glyphs) {
            if (glyph.has_ink) {
                for (int y = std::max(0, int(std::floor(top))); y < std::min(int(height), int(std::ceil(top + glyph_height))); ++y) {
                    for (int x = std::max(0, int(std::floor(pen))); x < std::min(int(std::ceil(right_edge)), int(std::ceil(pen + glyph.right))); ++x) {
                        const size_t offset = (static_cast<size_t>(y) * width + static_cast<size_t>(x)) * 4;
                        std::copy(color.begin(), color.end(), rgba.begin() + offset);
                    }
                }
            }
            pen += glyph.advance;
        }
        top += line_height;
        if (top >= height) break;
    }
}

bool RasterizeFreeTypeText(const TextLayerState& state, uint32_t width, uint32_t height,
                           std::vector<uint8_t>& rgba) {
    if (state.text.empty()) return true;

    std::vector<uint8_t> font_data;
    auto                 face = CreateFreeTypeFace(state, font_data);
    if (face == nullptr) return false;
    auto fallback_face = CreateFallbackFace(state);

    const auto lines =
        BuildFreeTypeLines(state, face.get(), fallback_face ? fallback_face->face.get() : nullptr);

    const auto  metrics     = face->size->metrics;
    const float line_height = std::max(1.0f, static_cast<float>(metrics.height) / 64.0f);
    const float padding     = std::max(0.0f, std::isfinite(state.padding) ? state.padding : 0.0f);
    const auto  color       = TextColorBytes(state);
    const float alpha_scale = static_cast<float>(color[3]) / 255.0f;

    float baseline_y = FirstBaselineY(state, face.get(), lines.size(), padding, height);
    for (const auto& line : lines) {
        const float limit = TextWidthLimit(state);
        const float line_width = limit > 0.0f ? std::min(limit, line.LayoutWidth()) : line.LayoutWidth();
        const float left_edge = HorizontalLineStart(state, line_width, padding, width);
        const float right_edge = limit > 0.0f ? std::min(float(width), left_edge + limit) : float(width);
        float pen_x = left_edge - line.ExtentLeft();
        for (const auto& glyph : line.glyphs) {
            FT_Face glyph_face =
                glyph.fallback && fallback_face ? fallback_face->face.get() : face.get();
            if (FT_Load_Char(glyph_face, glyph.codepoint, FT_LOAD_RENDER | FT_LOAD_TARGET_NORMAL) !=
                0) {
                pen_x += glyph.advance;
                continue;
            }

            const FT_GlyphSlot slot   = glyph_face->glyph;
            const FT_Bitmap&   bitmap = slot->bitmap;
            const int          left   = static_cast<int>(std::lround(pen_x)) + slot->bitmap_left;
            const int          top   = static_cast<int>(std::lround(baseline_y)) - slot->bitmap_top;
            const auto         pitch = static_cast<std::size_t>(std::abs(bitmap.pitch));

            for (uint32_t row = 0; row < bitmap.rows; ++row) {
                const int dest_y = top + static_cast<int>(row);
                if (dest_y < 0 || dest_y >= static_cast<int>(height)) continue;
                const uint32_t source_row = bitmap.pitch >= 0 ? row : bitmap.rows - 1u - row;

                for (uint32_t column = 0; column < bitmap.width; ++column) {
                    const int dest_x = left + static_cast<int>(column);
                    if (dest_x < 0 || dest_x >= static_cast<int>(width) || dest_x >= right_edge) continue;

                    const auto coverage =
                        bitmap.buffer[static_cast<std::size_t>(source_row) * pitch + column];
                    if (coverage == 0u) continue;

                    const auto alpha = static_cast<uint8_t>(
                        std::lround(static_cast<float>(coverage) * alpha_scale));
                    const std::size_t offset = (static_cast<std::size_t>(dest_y) * width +
                                                static_cast<std::size_t>(dest_x)) *
                                               4u;
                    rgba[offset + 0u] = color[0];
                    rgba[offset + 1u] = color[1];
                    rgba[offset + 2u] = color[2];
                    rgba[offset + 3u] = std::max(rgba[offset + 3u], alpha);
                }
            }

            pen_x += glyph.advance;
            if (pen_x >= static_cast<float>(width)) break;
        }
        baseline_y += line_height;
        if (baseline_y >= static_cast<float>(height) + line_height) break;
    }

    return true;
}

std::optional<Eigen::Vector2f> MeasureFreeTypeText(const TextLayerState& state) {
    std::vector<uint8_t> font_data;
    auto                 face = CreateFreeTypeFace(state, font_data);
    if (face == nullptr) return std::nullopt;
    auto fallback_face = CreateFallbackFace(state);

    const auto lines =
        BuildFreeTypeLines(state, face.get(), fallback_face ? fallback_face->face.get() : nullptr);
    float max_line_width = 0.0f;
    bool  saw_glyph      = false;
    for (const auto& line : lines) {
        max_line_width = std::max(max_line_width, line.LayoutWidth());
        saw_glyph      = saw_glyph || ! line.glyphs.empty();
    }

    const auto  metrics      = face->size->metrics;
    const float ascender     = static_cast<float>(metrics.ascender) / 64.0f;
    const float descender    = static_cast<float>(metrics.descender) / 64.0f;
    const float line_height  = std::max(1.0f, static_cast<float>(metrics.height) / 64.0f);
    const float glyph_height = std::max(1.0f, ascender - descender);
    const float padding      = std::max(0.0f, std::isfinite(state.padding) ? state.padding : 0.0f);

    if (! saw_glyph) {
        return Eigen::Vector2f(std::max(1.0f, padding * 2.0f + line_height * 0.5f),
                               std::max(1.0f, padding * 2.0f + glyph_height));
    }

    const float width = TextWidthLimit(state) > 0.0f
        ? std::min(state.max_width, max_line_width + padding * 2.0f)
        : max_line_width + padding * 2.0f;
    return Eigen::Vector2f(std::max(1.0f, width),
                           std::max(1.0f,
                                    glyph_height +
                                        static_cast<float>(lines.size() - 1u) * line_height +
                                        padding * 2.0f));
}

std::size_t LineCount(std::string_view text) {
    if (text.empty()) return 1;
    return static_cast<std::size_t>(std::count(text.begin(), text.end(), '\n')) + 1u;
}

std::size_t LongestLineCodepoints(std::string_view text) {
    std::size_t longest = 0;
    std::size_t current = 0;
    for (unsigned char ch : text) {
        if (ch == '\n') {
            longest = std::max(longest, current);
            current = 0;
            continue;
        }
        if ((ch & 0xC0u) != 0x80u) ++current;
    }
    return std::max(longest, current);
}

bool HasExplicitTextLayerSize(const TextLayerState& state) {
    return state.explicit_size.x() > 0.0f && state.explicit_size.y() > 0.0f;
}
} // namespace

Eigen::Vector2f EstimateTextLayerSize(std::string_view text, float point_size, float padding) {
    if (! std::isfinite(point_size) || point_size <= 0.0f) point_size = 12.0f;
    if (! std::isfinite(padding) || padding < 0.0f) padding = 0.0f;

    const float pixel_size  = point_size * kWallpaperEnginePointSizeToPx;
    const float glyph_width = std::max(1.0f, pixel_size * 0.6f);
    const float line_height = std::max(1.0f, pixel_size * 1.2f);
    const auto  columns     = std::max<std::size_t>(1u, LongestLineCodepoints(text));
    const auto  lines       = std::max<std::size_t>(1u, LineCount(text));

    return Eigen::Vector2f(static_cast<float>(columns) * glyph_width + padding * 2.0f,
                           static_cast<float>(lines) * line_height + padding * 2.0f);
}

Eigen::Vector2f MeasureTextLayerSize(const TextLayerState& state) {
#ifdef WESCENE_BUILD_TESTS
    ++g_measurement_count;
#endif
    std::optional<Eigen::Vector2f> measured;
    {
        const std::lock_guard lock { g_freetype_mutex };
        measured = MeasureFreeTypeText(state);
    }
    if (measured.has_value()) {
        return *measured;
    }
    return MeasureFallbackText(state);
}

Eigen::Vector2f TextLayerLayoutSize(const TextLayerState& state) {
    if (HasExplicitTextLayerSize(state)) {
        return state.explicit_size;
    }
    return MeasureTextLayerSize(state);
}

Eigen::Vector2f TextLayerRasterSize(const TextLayerState& state) {
    if (HasExplicitTextLayerSize(state)) {
        return state.explicit_size.cwiseMax(MeasureTextLayerSize(state));
    }
    return MeasureTextLayerSize(state);
}

TextLayerRenderBounds TextLayerRenderBoundsForRasterSize(const TextLayerState& state,
                                                         Eigen::Vector2f raster_size) {
    const Eigen::Vector2f layout_size =
        HasExplicitTextLayerSize(state) ? state.explicit_size : raster_size;

    TextLayerRenderBounds bounds {
        .left   = raster_size.x() * -0.5f,
        .right  = raster_size.x() * 0.5f,
        .bottom = raster_size.y() * -0.5f,
        .top    = raster_size.y() * 0.5f,
    };

    if (ContainsSubstring(state.horizontal_align, "left")) {
        bounds.left  = layout_size.x() * -0.5f;
        bounds.right = bounds.left + raster_size.x();
    } else if (ContainsSubstring(state.horizontal_align, "right")) {
        bounds.right = layout_size.x() * 0.5f;
        bounds.left  = bounds.right - raster_size.x();
    }

    const std::string_view vertical_align =
        state.vertical_align.empty() ? state.anchor : state.vertical_align;
    if (ContainsSubstring(vertical_align, "bottom")) {
        bounds.bottom = layout_size.y() * -0.5f;
        bounds.top    = bounds.bottom + raster_size.y();
    } else if (ContainsSubstring(vertical_align, "top")) {
        bounds.top    = layout_size.y() * 0.5f;
        bounds.bottom = bounds.top - raster_size.y();
    }

    return bounds;
}

TextLayerRenderFrame TextLayerRenderFrameForRasterSize(const TextLayerState& state,
                                                       Eigen::Vector2f raster_size) {
    const auto bounds = TextLayerRenderBoundsForRasterSize(state, raster_size);
    return {
        .bounds = bounds,
        .size   = Eigen::Vector2f(bounds.right - bounds.left, bounds.top - bounds.bottom),
        .center = Eigen::Vector2f((bounds.left + bounds.right) * 0.5f,
                                  (bounds.bottom + bounds.top) * 0.5f),
    };
}

TextLayerRenderFrame TextLayerRenderFrameForCapacity(const TextLayerState& state,
                                                     Eigen::Vector2f raster_size,
                                                     Eigen::Vector2f capacity_size) {
    const auto frame = TextLayerRenderFrameForRasterSize(state, raster_size);
    return TextLayerRenderFrameForTargetExtent(frame, capacity_size);
}

TextLayerRenderFrame TextLayerRenderFrameForTargetExtent(const TextLayerRenderFrame& frame,
                                                         Eigen::Vector2f target_extent) {
    return {
        .bounds = {
            .left = frame.center.x() - (target_extent.x() * 0.5f),
            .right = frame.center.x() + (target_extent.x() * 0.5f),
            .bottom = frame.center.y() - (target_extent.y() * 0.5f),
            .top = frame.center.y() + (target_extent.y() * 0.5f),
        },
        .size = target_extent,
        .center = frame.center,
    };
}

TextLayerRenderFrame TextLayerRenderFrameClampedToTarget(const TextLayerRenderFrame& frame,
                                                         const TextLayerRenderFrame& target) {
    const TextLayerRenderBounds bounds {
        .left   = std::clamp(frame.bounds.left, target.bounds.left, target.bounds.right),
        .right  = std::clamp(frame.bounds.right, target.bounds.left, target.bounds.right),
        .bottom = std::clamp(frame.bounds.bottom, target.bounds.bottom, target.bounds.top),
        .top    = std::clamp(frame.bounds.top, target.bounds.bottom, target.bounds.top),
    };
    return {
        .bounds = bounds,
        .size   = Eigen::Vector2f(bounds.right - bounds.left, bounds.top - bounds.bottom),
        .center = Eigen::Vector2f((bounds.left + bounds.right) * 0.5f,
                                  (bounds.bottom + bounds.top) * 0.5f),
    };
}

TextLayerTextureBounds TextLayerTextureBoundsForRenderTarget(const TextLayerRenderFrame& frame,
                                                             Eigen::Vector2f target_size,
                                                             Eigen::Vector2f target_center) {
    if (target_size.x() <= 0.0f || target_size.y() <= 0.0f) return {};

    const auto target_left   = target_center.x() - (target_size.x() * 0.5f);
    const auto target_bottom = target_center.y() - (target_size.y() * 0.5f);
    return {
        .left = (frame.bounds.left - target_left) / target_size.x(),
        .right = (frame.bounds.right - target_left) / target_size.x(),
        .bottom = 1.0f - ((frame.bounds.bottom - target_bottom) / target_size.y()),
        .top = 1.0f - ((frame.bounds.top - target_bottom) / target_size.y()),
    };
}

std::string TextTextureName(std::string_view layer_key) {
    return "runtime/text/" + std::string(layer_key);
}

void RasterizeTextLayer(const TextLayerState& state, uint32_t width, uint32_t height,
                        std::vector<uint8_t>& rgba) {
    bool rasterized = false;
    {
        const std::lock_guard lock { g_freetype_mutex };
        rasterized = RasterizeFreeTypeText(state, width, height, rgba);
    }
    if (! rasterized) {
        RasterizeFallbackText(state, width, height, rgba);
    }
}

#ifdef WESCENE_BUILD_TESTS
uint64_t TextLayerMeasurementCountForTests() {
    return g_measurement_count.load();
}

void ResetTextLayerMeasurementCountForTests() {
    g_measurement_count.store(0);
}
#endif

TextLayer::TextLayer(TextLayerState state): m_state(std::move(state)) {
    if (m_state.resolved_font_identity.empty()) m_state.resolved_font_identity = m_state.font_key;
    if (m_state.resolved_font_kind.empty()) m_state.resolved_font_kind = "family";
    EnsureCacheIdentity();
    Relayout();
    MarkCacheDirty();
    m_state.dirty = false;
}

void TextLayer::SetText(std::string text) {
    if (m_state.text == text) return;
    m_state.text           = std::move(text);
    m_state.dirty          = true;
    m_state.layout_pending = true;
    MarkCacheDirty();
}

bool TextLayer::ApplyPreparedLayout(uint64_t revision, Eigen::Vector2f layout_size,
                                    Eigen::Vector2f raster_size) {
    if (revision <= m_prepared_revision || revision > m_state.cache_revision) return false;
    m_prepared_revision   = revision;
    m_state.layout_size   = layout_size;
    m_state.raster_size   = raster_size;
    m_state.layout_pending = revision != m_state.cache_revision;
    return true;
}

void TextLayer::ClearDirty() {
    m_state.dirty       = false;
    m_state.cache_dirty = false;
    m_state.full_dirty  = false;
}

Eigen::Vector2f TextLayer::rasterSize() const { return m_state.raster_size; }

TextLayerRenderBounds TextLayer::renderBounds() const {
    return TextLayerRenderBoundsForRasterSize(m_state, rasterSize());
}

void TextLayer::Relayout() {
    const auto measured_size = MeasureTextLayerSize(m_state);
    if (HasExplicitTextLayerSize(m_state)) {
        m_state.layout_size = m_state.explicit_size;
        m_state.raster_size = m_state.explicit_size.cwiseMax(measured_size);
        m_state.layout_pending = false;
        return;
    }
    m_state.layout_size = measured_size;
    m_state.raster_size = measured_size;
    m_state.layout_pending = false;
}

void TextLayer::EnsureCacheIdentity() {
    if (! m_state.texture_cache_key.empty()) return;
    const std::string material = m_state.layer_key + "|" + m_state.text + "|" +
                                 m_state.resolved_font_kind + "|" + m_state.resolved_font_identity +
                                 "|" + m_state.resolved_font_path + "|" +
                                 std::to_string(m_state.point_size) + "|" +
                                 std::to_string(m_state.max_width) + "|" +
                                 std::to_string(m_state.max_rows) + "|" +
                                 std::to_string(m_state.limit_width) + "|" +
                                 std::to_string(m_state.limit_rows) + "|" +
                                 std::to_string(m_state.use_ellipsis);
    m_state.texture_cache_key = "textcache:" + std::to_string(std::hash<std::string> {}(material));
}

void TextLayer::MarkCacheDirty() {
    ++m_state.cache_revision;
    m_state.cache_dirty = true;
    m_state.full_dirty  = true;
}

} // namespace wallpaper
