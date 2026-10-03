#include "Audio/AudioDecodePump.hpp"

#include <gtest/gtest.h>

#include <deque>
#include <vector>

namespace wallpaper::audio::detail
{
namespace
{
class BufferedDecoder final : public AudioDecodeSource {
public:
    DecodeResult receive(std::string*) override {
        if (! output.empty()) {
            delivered.push_back(output.front());
            output.pop_front();
            return DecodeResult::Ok;
        }
        return draining ? DecodeResult::End : DecodeResult::Again;
    }
    DecodeResult read(std::string*) override {
        EXPECT_EQ(held, -1);
        if (next_packet == 3) return DecodeResult::End;
        held = next_packet++;
        return DecodeResult::Ok;
    }
    DecodeResult send(std::string*) override {
        EXPECT_GE(held, 0);
        attempts.push_back(held);
        if (held == 1 && ! rejected) {
            rejected = true;
            output.push_back(10); // previously buffered output makes room
            return DecodeResult::Again;
        }
        accepted.push_back(held);
        if (held != 2) output.push_back(held);
        return DecodeResult::Ok;
    }
    DecodeResult drain(std::string*) override {
        ++drains;
        if (reject_drain && drains == 1) {
            output.push_back(11);
            return DecodeResult::Again;
        }
        draining = true;
        output.push_back(2); // codec-delayed final output
        return DecodeResult::Ok;
    }
    void releasePacket() override {
        EXPECT_GE(held, 0);
        released.push_back(held);
        held = -1;
    }
    int held { -1 }, next_packet { 0 }, drains { 0 };
    bool rejected { false }, draining { false }, reject_drain { false };
    std::deque<int> output;
    std::vector<int> attempts, accepted, released, delivered;
};

TEST(AudioDecodePump, RejectedPacketSurvivesUntilAllOutputAndDelayedTailAreRead) {
    BufferedDecoder decoder;
    AudioDecodePump pump(decoder);
    std::string error;
    for (int frame = 0; frame < 4; ++frame) ASSERT_EQ(pump.next(&error), DecodeResult::Ok) << error;
    EXPECT_EQ(pump.next(&error), DecodeResult::End);
    EXPECT_EQ(pump.next(&error), DecodeResult::End);
    EXPECT_EQ(decoder.attempts, (std::vector<int> {0, 1, 1, 2}));
    EXPECT_EQ(decoder.accepted, (std::vector<int> {0, 1, 2}));
    EXPECT_EQ(decoder.released, decoder.accepted);
    EXPECT_EQ(decoder.delivered, (std::vector<int> {0, 10, 1, 2}));
    EXPECT_EQ(decoder.drains, 1);
}

TEST(AudioDecodePump, BackpressuredDrainIsRetriedAfterItsOutput) {
    BufferedDecoder decoder;
    decoder.reject_drain = true;
    AudioDecodePump pump(decoder);
    std::string error;
    for (int frame = 0; frame < 5; ++frame) ASSERT_EQ(pump.next(&error), DecodeResult::Ok) << error;
    EXPECT_EQ(pump.next(&error), DecodeResult::End);
    EXPECT_EQ(decoder.delivered, (std::vector<int> {0, 10, 1, 11, 2}));
    EXPECT_EQ(decoder.drains, 2);
}

TEST(AudioDecodePump, ResetReleasesARejectedPacketAndCanDecodeAgain) {
    BufferedDecoder decoder;
    AudioDecodePump pump(decoder);
    std::string error;
    ASSERT_EQ(pump.next(&error), DecodeResult::Ok);
    ASSERT_EQ(pump.next(&error), DecodeResult::Ok);
    ASSERT_EQ(decoder.held, 1);
    pump.reset();
    EXPECT_EQ(decoder.held, -1);
    EXPECT_EQ(decoder.released, (std::vector<int> {0, 1}));
    ASSERT_EQ(pump.next(&error), DecodeResult::Ok);
    EXPECT_EQ(decoder.delivered.back(), 2);
    EXPECT_EQ(pump.next(&error), DecodeResult::End);
}
} // namespace
} // namespace wallpaper::audio::detail
