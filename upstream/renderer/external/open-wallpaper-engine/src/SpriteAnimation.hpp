#pragma once
#include <cstdint>
#include <vector>
#include <iostream>
#include <cstdint>
#include <array>
#include <algorithm>
#include <cmath>

#include "Core/Literals.hpp"

namespace wallpaper
{
struct SpriteFrame {
    i32   imageId { 0 };
    float frametime { 0 };
    float x { 0 };
    float y { 0 };
    float width { 1 };
    float height { 1 };
    float rate { 1 }; // real h / w

    std::array<float, 2> xAxis { 1, 0 };
    std::array<float, 2> yAxis { 0, 1 };
};

class SpriteAnimation {
public:
    const auto& GetAnimateFrame(double newtime) {
        if (std::isfinite(newtime) && newtime > 0.0) {
            m_remainTime -= newtime;
            if (m_remainTime < 0.0) {
                double cycle = 0.0;
                for (const auto& frame : m_frames) cycle += FrameDuration(frame);
                if (cycle > 0.0) {
                    // Whole cycles leave the frame unchanged. Bound work even
                    // after a long suspend, then retain every fractional second.
                    if (m_remainTime < -cycle) m_remainTime = std::fmod(m_remainTime, cycle);
                    for (usize step = 0; m_remainTime < 0.0 && step < m_frames.size(); ++step) {
                        SwitchToNext();
                        m_remainTime += FrameDuration(m_frames.at((usize)m_curFrame));
                    }
                } else {
                    // Sheets without timed frames still make bounded progress.
                    SwitchToNext();
                    m_remainTime = 0.0;
                }
            }
        }
        const auto& frame = m_frames.at((usize)m_curFrame);
        return frame;
    }
    const auto& SetFrame(double frame) {
        const auto last = static_cast<double>(m_frames.size() - 1);
        m_curFrame = static_cast<idx>(std::clamp(std::floor(frame), 0.0, last));
        m_remainTime = FrameDuration(m_frames.at((usize)m_curFrame));
        return m_frames.at((usize)m_curFrame);
    }
    const auto& GetCurFrame() const { return m_frames.at((usize)m_curFrame); }
    /// One frame by index, for callers that must know every image a sheet can
    /// reach before the animation reaches it -- a renderer that uploads the
    /// sheets up front cannot wait to be surprised mid-playback.
    const SpriteFrame& FrameAt(usize index) const { return m_frames.at(index); }
    /// Index of the frame `GetCurFrame` returns.
    idx CurFrameIndex() const { return m_curFrame; }
    /// A single-frame sprite never advances, so it does not make its pass
    /// time-varying.
    usize FrameCount() const { return m_frames.size(); }
    void        AppendFrame(const SpriteFrame& frame) { m_frames.push_back(frame); }

    usize numFrames() const { return m_frames.size(); }

private:
    static double FrameDuration(const SpriteFrame& frame) {
        return std::isfinite(frame.frametime) && frame.frametime > 0.0f ? frame.frametime : 0.0;
    }
    void SwitchToNext() {
        if (m_curFrame >= std::ssize(m_frames) - 1)
            m_curFrame = 0;
        else
            m_curFrame++;
    }
    idx    m_curFrame { 0 };
    double m_remainTime { 0 };

    std::vector<SpriteFrame> m_frames;
};
} // namespace wallpaper
