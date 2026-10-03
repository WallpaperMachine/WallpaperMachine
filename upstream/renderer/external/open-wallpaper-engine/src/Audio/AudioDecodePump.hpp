#pragma once

#include <string>
#include <utility>

namespace wallpaper::audio::detail
{
enum class DecodeResult { Ok, Again, End, Error };

class AudioDecodeSource {
public:
    virtual ~AudioDecodeSource() = default;
    virtual DecodeResult receive(std::string*) = 0;
    virtual DecodeResult read(std::string*) = 0;
    virtual DecodeResult send(std::string*) = 0;
    virtual DecodeResult drain(std::string*) = 0;
    virtual void releasePacket() = 0;
};

// libavcodec retains output across calls. Keep the input packet until accepted,
// then receive all delayed frames before reporting EOF to the resampler.
class AudioDecodePump {
public:
    explicit AudioDecodePump(AudioDecodeSource& source): m_source(source) {}

    DecodeResult next(std::string* error) {
        if (m_failed) return DecodeResult::Error;
        if (m_ended) return DecodeResult::End;
        unsigned stalled = 0;
        while (true) {
            const auto received = m_source.receive(error);
            if (received == DecodeResult::Ok) return received;
            if (received == DecodeResult::Error) return fail(error);
            if (received == DecodeResult::End) {
                release();
                m_ended = true;
                return received;
            }

            bool progressed = false;
            if (m_held) {
                const auto sent = m_source.send(error);
                if (sent == DecodeResult::Error || sent == DecodeResult::End) return fail(error);
                if (sent == DecodeResult::Ok) {
                    release();
                    progressed = true;
                }
            } else if (m_input_ended) {
                if (! m_drain_sent) {
                    const auto drained = m_source.drain(error);
                    if (drained == DecodeResult::Error) return fail(error);
                    if (drained != DecodeResult::Again) {
                        m_drain_sent = true;
                        progressed = true;
                    }
                }
            } else {
                const auto read = m_source.read(error);
                if (read == DecodeResult::Error) return fail(error);
                if (read == DecodeResult::Ok) {
                    m_held = true;
                    progressed = true;
                } else if (read == DecodeResult::End) {
                    m_input_ended = true;
                    progressed = true;
                }
            }
            if (progressed) stalled = 0;
            else if (++stalled == 256) {
                if (error != nullptr) *error = "audio decoder made no progress";
                return fail(error);
            }
        }
    }

    void reset() {
        release();
        m_input_ended = m_drain_sent = m_ended = m_failed = false;
    }

private:
    void release() {
        if (m_held) m_source.releasePacket();
        m_held = false;
    }
    DecodeResult fail(std::string* error) {
        release();
        m_failed = true;
        if (error != nullptr && error->empty()) *error = "audio decoder rejected input";
        return DecodeResult::Error;
    }

    AudioDecodeSource& m_source;
    bool m_held { false };
    bool m_input_ended { false };
    bool m_drain_sent { false };
    bool m_ended { false };
    bool m_failed { false };
};
} // namespace wallpaper::audio::detail
