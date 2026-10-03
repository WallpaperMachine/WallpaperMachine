#pragma once

namespace wallpaper::video
{
// Shared by both renderers: geometry and color conversion must agree before
// either backend samples an imported video as an ordinary texture.
inline constexpr const char* kVideoConversionMetalSource = R"(
#include <metal_stdlib>
using namespace metal;
struct YuvColorParams {
    float y_offset; float y_scale; float chroma_offset; float chroma_scale;
    float r_cr; float g_cb; float g_cr; float b_cb;
};
struct VideoTransform {
    float4 matrix;
    float2 offset;
};
float2 video_uv(float2 uv, constant VideoTransform& transform) {
    return float2(dot(uv, transform.matrix.xy), dot(uv, transform.matrix.zw)) + transform.offset;
}
float video_coverage(float2 uv, constant VideoTransform& transform) {
    const bool non_orthogonal = abs(transform.matrix.x * transform.matrix.y) > 1e-6f ||
                                abs(transform.matrix.z * transform.matrix.w) > 1e-6f;
    return non_orthogonal && (any(uv < 0.0f) || any(uv > 1.0f)) ? 0.0f : 1.0f;
}
kernel void nv12_to_bgra(texture2d<float, access::sample> y_texture [[texture(0)]],
                         texture2d<float, access::sample> uv_texture [[texture(1)]],
                         texture2d<half, access::write> output_texture [[texture(2)]],
                         constant YuvColorParams& params [[buffer(0)]],
                         constant VideoTransform& transform [[buffer(1)]],
                         uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= output_texture.get_width() || gid.y >= output_texture.get_height()) return;
    constexpr sampler sample_state(coord::normalized, address::clamp_to_edge, filter::linear);
    const float2 uv = video_uv((float2(gid) + 0.5f) /
        float2(output_texture.get_width(), output_texture.get_height()), transform);
    const float y = y_texture.sample(sample_state, uv).r;
    const float2 cbcr = (uv_texture.sample(sample_state, uv).rg - params.chroma_offset) * params.chroma_scale;
    const float luma = clamp((y - params.y_offset) * params.y_scale, 0.0f, 1.0f);
    const float3 rgb = saturate(float3(luma + params.r_cr * cbcr.y,
        luma + params.g_cb * cbcr.x + params.g_cr * cbcr.y, luma + params.b_cb * cbcr.x));
    const float coverage = video_coverage(uv, transform);
    output_texture.write(half4(half3(rgb * coverage), half(coverage)), gid);
}
kernel void bgra_transform(texture2d<float, access::sample> source [[texture(0)]],
                            texture2d<half, access::write> output_texture [[texture(2)]],
                            constant VideoTransform& transform [[buffer(1)]],
                            uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= output_texture.get_width() || gid.y >= output_texture.get_height()) return;
    constexpr sampler sample_state(coord::normalized, address::clamp_to_edge, filter::linear);
    const float2 uv = video_uv((float2(gid) + 0.5f) /
        float2(output_texture.get_width(), output_texture.get_height()), transform);
    output_texture.write(half4(source.sample(sample_state, uv) * video_coverage(uv, transform)), gid);
}
)";
} // namespace wallpaper::video
