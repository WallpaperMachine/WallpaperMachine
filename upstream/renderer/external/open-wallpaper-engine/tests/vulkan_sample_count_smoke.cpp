#include "Scene/SceneRenderTarget.h"
#include "Vulkan/GraphicsPipeline.hpp"
#include "Vulkan/SampleCount.hpp"
#include "Vulkan/TextureCache.hpp"
#include "VulkanRender/Resource.hpp"
#include "VulkanRender/FinPass.hpp"
#include "VulkanRender/PassCommon.hpp"

#include <gtest/gtest.h>
#include "TestRequire.hpp"

namespace
{
using wallpaper::SceneRenderTarget;
using wallpaper::TextureFilter;
using wallpaper::TextureFormat;
using wallpaper::TextureSample;
using wallpaper::TextureWrap;
using wallpaper::vulkan::ResolveSampleCount;
using wallpaper::vulkan::SampleCountValue;
using wallpaper::vulkan::ResolveCustomPassRenderTargetSampleCount;
using wallpaper::vulkan::TexUsage;
using wallpaper::vulkan::TextureKey;
using wallpaper::vulkan::ToTexKey;

TextureKey makeKey(VkSampleCountFlagBits sample_count) {
    return TextureKey {
        .width        = 64,
        .height       = 64,
        .usage        = TexUsage::COLOR,
        .format       = TextureFormat::RGBA8,
        .sample       = TextureSample {
                  .wrapS     = TextureWrap::CLAMP_TO_EDGE,
                  .wrapT     = TextureWrap::CLAMP_TO_EDGE,
                  .magFilter = TextureFilter::LINEAR,
                  .minFilter = TextureFilter::LINEAR,
              },
        .mipmap_level = 1,
        .sample_count = sample_count,
    };
}

TextureKey makeDepthKey(VkSampleCountFlagBits sample_count) {
    TextureKey key = makeKey(sample_count);
    key.usage      = TexUsage::DEPTH;
    return key;
}

TEST(VulkanSampleCount, requestedZeroOrOneResolvesToOne) {
    const auto supported = VK_SAMPLE_COUNT_1_BIT | VK_SAMPLE_COUNT_2_BIT |
                           VK_SAMPLE_COUNT_4_BIT | VK_SAMPLE_COUNT_8_BIT;

    REQUIRE(ResolveSampleCount(0, supported) == VK_SAMPLE_COUNT_1_BIT);
    REQUIRE(ResolveSampleCount(1, supported) == VK_SAMPLE_COUNT_1_BIT);
}

TEST(VulkanSampleCount, requestedAboveSupportedFallsBackToHighestSupported) {
    const auto supported =
        VK_SAMPLE_COUNT_1_BIT | VK_SAMPLE_COUNT_2_BIT | VK_SAMPLE_COUNT_4_BIT;

    REQUIRE(ResolveSampleCount(8, supported) == VK_SAMPLE_COUNT_4_BIT);
}

TEST(VulkanSampleCount, unsupportedRequestsFallBackToOne) {
    REQUIRE(ResolveSampleCount(16, VK_SAMPLE_COUNT_1_BIT) == VK_SAMPLE_COUNT_1_BIT);
}

TEST(VulkanSampleCount, sampleCountValueReturnsIntegerSamples) {
    REQUIRE(SampleCountValue(VK_SAMPLE_COUNT_1_BIT) == 1);
    REQUIRE(SampleCountValue(VK_SAMPLE_COUNT_4_BIT) == 4);
}

TEST(VulkanSampleCount, textureKeyHashIncludesSampleCount) {
    const TextureKey single_sample = makeKey(VK_SAMPLE_COUNT_1_BIT);
    const TextureKey four_sample   = makeKey(VK_SAMPLE_COUNT_4_BIT);

    REQUIRE(TextureKey::HashValue(single_sample) != TextureKey::HashValue(four_sample));
}

TEST(VulkanSampleCount, sceneRenderTargetSampleCountConvertsToTextureKey) {
    const SceneRenderTarget render_target {
        .width        = 64,
        .height       = 64,
        .allowReuse   = true,
        .sample_count = 4,
    };

    const TextureKey key = ToTexKey(render_target);

    REQUIRE(key.sample_count == VK_SAMPLE_COUNT_4_BIT);
}

TEST(VulkanSampleCount, customPassRenderTargetSampleCountFallsBackToSupportedColorSamples) {
    const auto supported =
        VK_SAMPLE_COUNT_1_BIT | VK_SAMPLE_COUNT_2_BIT | VK_SAMPLE_COUNT_4_BIT;

    REQUIRE(ResolveCustomPassRenderTargetSampleCount(8, supported) == VK_SAMPLE_COUNT_4_BIT);
}

TEST(VulkanSampleCount, customPassRenderTargetSampleCountFallsBackToSingleSampleWhenUnsupported) {
    REQUIRE(ResolveCustomPassRenderTargetSampleCount(4, VK_SAMPLE_COUNT_1_BIT) ==
           VK_SAMPLE_COUNT_1_BIT);
}

TEST(VulkanSampleCount, customPassRenderTargetSampleCountPreservesGraphFallbackToSingleSample) {
    const auto supported =
        VK_SAMPLE_COUNT_1_BIT | VK_SAMPLE_COUNT_2_BIT | VK_SAMPLE_COUNT_4_BIT;

    REQUIRE(ResolveCustomPassRenderTargetSampleCount(1, supported) == VK_SAMPLE_COUNT_1_BIT);
}

TEST(VulkanSampleCount, gpuAllocationSampleCountPlansRequestedSamplesForInternalColorTargets) {
    const TextureKey key = makeKey(VK_SAMPLE_COUNT_4_BIT);

    REQUIRE(wallpaper::vulkan::PlannedTextureSampleCountForGpuAllocation(key) ==
           VK_SAMPLE_COUNT_1_BIT);
}

TEST(VulkanSampleCount, gpuAllocationSampleCountUsesRequestedSamplesForMsaaSidecars) {
    SceneRenderTarget render_target {
        .width        = 64,
        .height       = 64,
        .allowReuse   = true,
        .sample_count = 4,
    };
    const TextureKey key = wallpaper::vulkan::ToTexKeyMsaa(render_target, VK_SAMPLE_COUNT_4_BIT);

    REQUIRE(wallpaper::vulkan::PlannedTextureSampleCountForGpuAllocation(key) ==
           VK_SAMPLE_COUNT_4_BIT);
}

TEST(VulkanSampleCount, gpuAllocationSampleCountMatchesDepthToMsaaColor) {
    const TextureKey key = makeDepthKey(VK_SAMPLE_COUNT_4_BIT);

    REQUIRE(wallpaper::vulkan::PlannedTextureSampleCountForGpuAllocation(key) ==
           VK_SAMPLE_COUNT_4_BIT);
}

TEST(VulkanSampleCount, graphicsPipelineStoresRequestedSampleCount) {
    wallpaper::vulkan::GraphicsPipeline pipeline;

    REQUIRE(pipeline.sampleCount() == VK_SAMPLE_COUNT_1_BIT);
    pipeline.setSampleCount(VK_SAMPLE_COUNT_4_BIT);
    REQUIRE(pipeline.sampleCount() == VK_SAMPLE_COUNT_4_BIT);
    REQUIRE(pipeline.multisample.rasterizationSamples == VK_SAMPLE_COUNT_4_BIT);
    pipeline.toDefault();
    REQUIRE(pipeline.sampleCount() == VK_SAMPLE_COUNT_1_BIT);
}

TEST(VulkanSampleCount, pipelineParametersResetDropsDescriptorLayouts) {
    wallpaper::vulkan::PipelineParameters parameters;

    parameters.descriptor_layouts.emplace_back();
    REQUIRE(parameters.descriptor_layouts.size() == 1);

    wallpaper::vulkan::ResetPipelineParameters(parameters);

    REQUIRE(parameters.descriptor_layouts.empty());
    REQUIRE(! parameters.handle);
    REQUIRE(! parameters.layout);
    REQUIRE(! parameters.pass);
}

TEST(VulkanSampleCount, finPassDestroyResetsPersistentPipelineState) {
    wallpaper::vulkan::FinPass pass(wallpaper::vulkan::FinPass::Desc {});
    pass.pipelineForTests().descriptor_layouts.emplace_back();
    REQUIRE(pass.pipelineForTests().descriptor_layouts.size() == 1);

    wallpaper::vulkan::RenderingResources resources {};
    pass.destroyForTests(resources);

    REQUIRE(pass.pipelineForTests().descriptor_layouts.empty());
}
} // namespace
