// Decoded software frames must reach Metal without a second pixel copy.
// No window, audio device or private media is needed for the generated cases.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <gtest/gtest.h>

extern "C" {
#include <libavutil/frame.h>
}

#include <array>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <memory>
#include <vector>

#include "Image.hpp"
#include "Platform/Apple/FfmpegVideoInterop.hpp"
#include "Video/FfmpegVideoTextureSource.hpp"

namespace {
using namespace wallpaper;
using namespace wallpaper::video;

struct OwnedFrame {
    VideoTextureFrame value {};
    ~OwnedFrame() { ReleaseAppleVideoFrame(&value); }
};
using Lease = std::unique_ptr<void, decltype(&ReleaseAppleVideoFrameLease)>;
using Pixel = std::array<uint8_t, 4>;

class SoftwareVideoFrame : public ::testing::TestWithParam<AVPixelFormat> {};

TEST_P(SoftwareVideoFrame, ImportedPixelsOutliveTheDecoderWithoutAnotherConversion) {
    @autoreleasepool {
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        ASSERT_NE(device, nil);
        const auto free_frame = [](AVFrame* frame) { av_frame_free(&frame); };
        std::unique_ptr<AVFrame, decltype(free_frame)> decoded(av_frame_alloc(), free_frame);
        ASSERT_NE(decoded, nullptr);
        // Not a cache-line-sized row: exercise the decoder and IOSurface strides.
        constexpr int width = 18, height = 10;
        decoded->width = width;
        decoded->height = height;
        decoded->format = GetParam();
        decoded->colorspace = AVCOL_SPC_BT709;
        decoded->color_range = GetParam() == AV_PIX_FMT_YUVJ420P ? AVCOL_RANGE_JPEG : AVCOL_RANGE_MPEG;
        ASSERT_GE(av_frame_get_buffer(decoded.get(), 32), 0);

        std::vector<Pixel> expected(width * height);
        YuvColorDescription description;
        description.matrix = YuvMatrix::Bt709;
        description.range = GetParam() == AV_PIX_FMT_YUVJ420P ? YuvRange::Full : YuvRange::Limited;
        const auto params = MakeYuvColorParams(description);
        for (int y = 0; y < height; ++y) {
            auto* row = decoded->data[0] + y * decoded->linesize[0];
            for (int x = 0; x < width; ++x) {
                if (GetParam() == AV_PIX_FMT_BGRA) {
                    const Pixel pixel {uint8_t(10 + x * 7), uint8_t(20 + y * 11), 150, 173};
                    std::memcpy(row + x * 4, pixel.data(), 4);
                    expected[y * width + x] = pixel;
                } else {
                    row[x] = uint8_t(40 + x * 5 + y * 3);
                    const auto rgb = ConvertYuvCodeToRgb8(params, row[x], 90, 180);
                    expected[y * width + x] = {rgb.blue, rgb.green, rgb.red, 255};
                }
            }
        }
        if (GetParam() != AV_PIX_FMT_BGRA) {
            for (int y = 0; y < height / 2; ++y) {
                auto* chroma = decoded->data[1] + y * decoded->linesize[1];
                for (int x = 0; x < width / 2; ++x) {
                    if (GetParam() == AV_PIX_FMT_NV12) {
                        chroma[x * 2] = 90;
                        chroma[x * 2 + 1] = 180;
                    } else {
                        chroma[x] = 90;
                        decoded->data[2][y * decoded->linesize[2] + x] = 180;
                    }
                }
            }
        }

        std::string error;
        OwnedFrame extracted;
        ASSERT_TRUE(ExtractAppleVideoFrame(decoded.get(), &extracted.value, &error)) << error;
        decoded.reset();
        const auto waits = AppleVideoConversionCpuWaits();
        void* destination = nullptr;
        Lease lease(CreateAppleVideoFrameLease(extracted.value, (__bridge void*)device, nullptr,
                                               &error, nullptr, &destination), ReleaseAppleVideoFrameLease);
        ASSERT_NE(lease, nullptr) << error;
        EXPECT_EQ(destination, nullptr) << "software output must import directly, not allocate a conversion target";
        EXPECT_EQ(AppleVideoConversionCpuWaits(), waits);
        ReleaseAppleVideoFrame(&extracted.value);
        id<MTLTexture> texture = (__bridge id<MTLTexture>)AppleVideoFrameLeaseTexture(lease.get());
        ASSERT_NE(texture, nil);
        std::vector<Pixel> actual(width * height);
        [texture getBytes:actual.data() bytesPerRow:width * 4
               fromRegion:MTLRegionMake2D(0, 0, width, height) mipmapLevel:0];
        EXPECT_EQ(actual, expected);
    }
}

INSTANTIATE_TEST_SUITE_P(DecodedFormats, SoftwareVideoFrame,
    ::testing::Values(AV_PIX_FMT_BGRA, AV_PIX_FMT_NV12, AV_PIX_FMT_YUV420P, AV_PIX_FMT_YUVJ420P));

// Opt-in corpus diagnostic; only opens the named file for reading.
TEST(AppleVideoFrame, LocalVideoImportsVisiblePixels) {
    const char* path = std::getenv("WE_TEST_VIDEO");
    if (path == nullptr || *path == '\0') GTEST_SKIP() << "WE_TEST_VIDEO names no local video";
    @autoreleasepool {
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        ASSERT_NE(device, nil);
        const std::filesystem::path media(path);
        std::string error;
        auto image = CreateVideoProjectImage(media.parent_path(), media.filename().string(), &error);
        ASSERT_NE(image, nullptr) << error;
        auto source = CreateVideoTextureSource(*image, &error);
        ASSERT_NE(source, nullptr) << error;
        ASSERT_TRUE(source->prime(&error)) << error;
        const auto frame = source->currentFrame();
        std::cout << DescribeAppleVideoFrame(frame) << '\n';
        Lease lease(CreateAppleVideoFrameLease(frame, (__bridge void*)device, nullptr, &error),
                    ReleaseAppleVideoFrameLease);
        ASSERT_NE(lease, nullptr) << error;
        source.reset();
        id<MTLTexture> texture = (__bridge id<MTLTexture>)AppleVideoFrameLeaseTexture(lease.get());
        ASSERT_NE(texture, nil);
        std::vector<Pixel> pixels(texture.width * texture.height);
        [texture getBytes:pixels.data() bytesPerRow:texture.width * 4
               fromRegion:MTLRegionMake2D(0, 0, texture.width, texture.height) mipmapLevel:0];
        size_t visible = 0;
        for (const auto& pixel : pixels) {
            if (pixel[3] > 0 && (pixel[0] > 8 || pixel[1] > 8 || pixel[2] > 8)) ++visible;
        }
        std::cout << "visible pixels: " << visible << '/' << pixels.size() << '\n';
        EXPECT_GT(visible, pixels.size() / 100);
    }
}
} // namespace
