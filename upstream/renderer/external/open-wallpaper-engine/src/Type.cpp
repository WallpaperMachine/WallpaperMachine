#include "Type.hpp"
#include <cmath>

#include "Utils/Logging.h"

std::string wallpaper::ToString(const ImageType& type) {
#define IMG(str) \
    case ImageType::str: return #str;

    switch (type) {
        IMG(UNKNOWN);
        IMG(BMP);
        IMG(ICO);
        IMG(JPEG);
        IMG(JNG);
        IMG(PNG);
    default: LOG_ERROR("Not valied image type: %d", (int)type); return "";
    }
}

std::string wallpaper::ToString(const TextureFormat& format) {
#define Fmt(str) \
    case TextureFormat::str: return #str;

    switch (format) {
        Fmt(RGBA8);
        Fmt(RGBA16F);
        Fmt(BC1);
        Fmt(BC2);
        Fmt(BC3);
        Fmt(RGB8);
        Fmt(RG8);
        Fmt(R8);
    default: LOG_ERROR("Not valied tex format: %d", (int)format); return "";
    }
}

float wallpaper::HalfFloatToFloat(uint16_t bits) {
    const auto sign = bits & 0x8000 ? -1.0f : 1.0f;
    const auto exponent = (bits >> 10) & 31;
    const auto fraction = bits & 1023;
    if (exponent == 0) return sign * std::ldexp(static_cast<float>(fraction), -24);
    if (exponent == 31) {
        return sign * (fraction == 0 ? INFINITY : NAN);
    }
    return sign * std::ldexp(static_cast<float>(1024 + fraction), exponent - 25);
}
