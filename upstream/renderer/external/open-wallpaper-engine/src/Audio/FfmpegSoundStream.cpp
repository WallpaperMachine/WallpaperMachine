#include "Audio/FfmpegSoundStream.hpp"
#include "AudioDecodePump.hpp"

#include "Fs/IBinaryStream.h"
#include "Video/FfmpegAbi.hpp"
#include "Utils/Logging.h"

extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/channel_layout.h>
#include <libavutil/error.h>
#include <libavutil/frame.h>
#include <libswresample/swresample.h>
}

#include <algorithm>
#include <cerrno>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <memory>
#include <string>
#include <utility>
#include <vector>

namespace wallpaper::audio
{
namespace
{

std::string AvErrorString(int error_code)
{
    char buffer[AV_ERROR_MAX_STRING_SIZE] {};
    av_strerror(error_code, buffer, sizeof(buffer));
    return std::string(buffer);
}

bool SetError(std::string* error, std::string message)
{
    if (error != nullptr) *error = std::move(message);
    return false;
}

class FfmpegInputSource {
public:
    virtual ~FfmpegInputSource() = default;

    virtual const std::string& Description() const = 0;
    virtual bool Open(AVFormatContext** format_context, std::string* error) = 0;
    virtual void Close() {}
};

class PathFfmpegInputSource final : public FfmpegInputSource {
public:
    explicit PathFfmpegInputSource(std::filesystem::path media_path)
        : m_media_path(std::move(media_path))
        , m_description(m_media_path.string())
    {
    }

    const std::string& Description() const override { return m_description; }

    bool Open(AVFormatContext** format_context, std::string* error) override
    {
        if (m_media_path.empty()) return SetError(error, "pure-video audio path must not be empty");

        if (const int result = avformat_open_input(
                format_context,
                m_media_path.string().c_str(),
                nullptr,
                nullptr);
            result < 0) {
            return SetError(error, "failed to open FFmpeg audio input: " + AvErrorString(result));
        }

        return true;
    }

private:
    std::filesystem::path m_media_path;
    std::string           m_description;
};

class StreamFfmpegInputSource final : public FfmpegInputSource {
public:
    explicit StreamFfmpegInputSource(std::shared_ptr<fs::IBinaryStream> stream)
        : m_stream(std::move(stream))
    {
    }

    ~StreamFfmpegInputSource() override
    {
        FreeAvio();
    }

    const std::string& Description() const override { return m_description; }

    bool Open(AVFormatContext** format_context, std::string* error) override
    {
        if (!m_stream->Rewind()) {
            return SetError(error, "failed to rewind VFS audio stream");
        }
        FreeAvio();

        auto* context = avformat_alloc_context();
        if (context == nullptr) {
            return SetError(error, "failed to allocate an FFmpeg media context");
        }

        constexpr int avio_buffer_size = 32 * 1024;
        auto* buffer = static_cast<unsigned char*>(av_malloc(avio_buffer_size));
        if (buffer == nullptr) {
            avformat_free_context(context);
            return SetError(error, "failed to allocate an FFmpeg AVIO buffer");
        }

        m_avio_context = avio_alloc_context(
            buffer,
            avio_buffer_size,
            0,
            this,
            &StreamFfmpegInputSource::ReadPacket,
            nullptr,
            &StreamFfmpegInputSource::Seek);
        if (m_avio_context == nullptr) {
            av_free(buffer);
            avformat_free_context(context);
            return SetError(error, "failed to allocate an FFmpeg AVIO context");
        }

        context->pb = m_avio_context;
        context->flags |= AVFMT_FLAG_CUSTOM_IO;

        if (const int result = avformat_open_input(&context, nullptr, nullptr, nullptr); result < 0) {
            if (context != nullptr) {
                context->pb = nullptr;
                avformat_free_context(context);
            }
            FreeAvio();
            return SetError(error, "failed to open FFmpeg audio input: " + AvErrorString(result));
        }

        *format_context = context;
        return true;
    }

    void Close() override
    {
        FreeAvio();
    }

private:
    static int ReadPacket(void* opaque, uint8_t* buffer, int buffer_size)
    {
        auto* source = static_cast<StreamFfmpegInputSource*>(opaque);
        const auto bytes_read = source->m_stream->Read(
            buffer,
            static_cast<usize>(std::max(buffer_size, 0)));
        if (bytes_read == 0) return AVERROR_EOF;
        return static_cast<int>(bytes_read);
    }

    static int64_t Seek(void* opaque, int64_t offset, int whence)
    {
        auto* source = static_cast<StreamFfmpegInputSource*>(opaque);

        if (whence == AVSEEK_SIZE) {
            const auto size = source->m_stream->Size();
            return size >= 0 ? static_cast<int64_t>(size) : AVERROR(EIO);
        }

        bool seek_result { false };
        switch (whence & ~AVSEEK_FORCE) {
        case SEEK_SET: seek_result = source->m_stream->SeekSet(static_cast<idx>(offset)); break;
        case SEEK_CUR: seek_result = source->m_stream->SeekCur(static_cast<idx>(offset)); break;
        case SEEK_END: seek_result = source->m_stream->SeekEnd(static_cast<idx>(offset)); break;
        default: return AVERROR(EINVAL);
        }

        if (!seek_result) return AVERROR(EIO);
        return source->m_stream->Tell();
    }

    void FreeAvio()
    {
        if (m_avio_context == nullptr) return;

        av_freep(&m_avio_context->buffer);
        avio_context_free(&m_avio_context);
    }

    std::shared_ptr<fs::IBinaryStream> m_stream;
    AVIOContext*                       m_avio_context { nullptr };
    std::string                        m_description { "VFS audio stream" };
};

bool ProbeHasAudioStream(FfmpegInputSource& input_source, std::string* error, bool audio_optional = false)
{
    if (auto mismatch = video::FfmpegAbiMismatch(); !mismatch.empty()) {
        return SetError(error, std::move(mismatch));
    }
    AVFormatContext* format_context = nullptr;
    if (!input_source.Open(&format_context, error)) return false;

    if (const int result = avformat_find_stream_info(format_context, nullptr); result < 0) {
        avformat_close_input(&format_context);
        input_source.Close();
        return SetError(error, "failed to read FFmpeg media stream info: " + AvErrorString(result));
    }

    const int audio_stream_index =
        av_find_best_stream(format_context, AVMEDIA_TYPE_AUDIO, -1, -1, nullptr, 0);
    avformat_close_input(&format_context);
    input_source.Close();
    if (audio_optional && audio_stream_index == AVERROR_STREAM_NOT_FOUND) {
        if (error != nullptr) error->clear();
        return false;
    }
    if (audio_stream_index < 0) {
        return SetError(error, "failed to find an FFmpeg audio stream: " + AvErrorString(audio_stream_index));
    }

    return true;
}

class FfmpegSoundStream final : public SoundStream, private detail::AudioDecodeSource {
public:
    explicit FfmpegSoundStream(std::filesystem::path media_path, Options options = {})
        : FfmpegSoundStream(std::make_unique<PathFfmpegInputSource>(std::move(media_path)),
                            options)
    {
    }

    explicit FfmpegSoundStream(std::shared_ptr<fs::IBinaryStream> stream, Options options = {})
        : FfmpegSoundStream(std::make_unique<StreamFfmpegInputSource>(std::move(stream)),
                            options)
    {
    }

    explicit FfmpegSoundStream(std::unique_ptr<FfmpegInputSource> input_source,
                               Options                           options = {})
        : m_input_source(std::move(input_source)),
          m_options(options)
    {
    }

    ~FfmpegSoundStream() override
    {
        closeDecoder();
    }

    uint64_t NextPcmData(void* pData, uint32_t frameCount) override
    {
        if (pData == nullptr || frameCount == 0) return 0;
        if (!ensureOpen()) return 0;

        auto* out = static_cast<float*>(pData);
        const size_t requested_samples = static_cast<size_t>(frameCount) * m_desc.channels;
        std::fill(out, out + requested_samples, 0.0f);

        uint64_t frames_written = 0;
        while (frames_written < frameCount) {
            const size_t pending_frames = pendingFrames();
            if (pending_frames == 0) {
                if (!decodeMoreAudio()) break;
                continue;
            }

            const uint64_t frames_to_copy = std::min<uint64_t>(
                frameCount - frames_written,
                static_cast<uint64_t>(pending_frames));
            const size_t samples_to_copy = static_cast<size_t>(frames_to_copy) * m_desc.channels;
            std::memcpy(
                out + (frames_written * m_desc.channels),
                m_pending_samples.data() + m_pending_offset_samples,
                samples_to_copy * sizeof(float));
            m_pending_offset_samples += samples_to_copy;
            frames_written += frames_to_copy;

            if (m_pending_offset_samples >= m_pending_samples.size()) {
                m_pending_samples.clear();
                m_pending_offset_samples = 0;
            }
        }

        return frames_written;
    }

    void PassDesc(const Desc& desc) override
    {
        m_desc = desc;
        (void)ensureOpen();
    }

private:
    bool ensureOpen()
    {
        if (m_open) return true;
        if (m_desc.channels == 0 || m_desc.sampleRate == 0) return false;

        std::string error;
        if (!openDecoder(&error)) {
            LOG_ERROR("failed to open FFmpeg audio stream for \"%s\": %s",
                      m_input_source->Description().c_str(),
                      error.c_str());
            return false;
        }
        m_open = true;
        return true;
    }

    bool openDecoder(std::string* error)
    {
        closeDecoder();

        const auto fail = [&](std::string message) {
            closeDecoder();
            return SetError(error, std::move(message));
        };

        if (!m_input_source->Open(&m_format_context, error)) return false;

        if (const int result = avformat_find_stream_info(m_format_context, nullptr); result < 0) {
            return fail("failed to read FFmpeg audio stream info: " + AvErrorString(result));
        }

        m_audio_stream_index =
            av_find_best_stream(m_format_context, AVMEDIA_TYPE_AUDIO, -1, -1, nullptr, 0);
        if (m_audio_stream_index < 0) {
            return fail("failed to find an FFmpeg audio stream: " + AvErrorString(m_audio_stream_index));
        }
        // A video wallpaper's audio demuxer otherwise reads every video packet
        // and drops it. Discarding the unused streams keeps the PCM, the
        // generation and the loop seam identical.
        for (unsigned index = 0; index < m_format_context->nb_streams; ++index) {
            if (static_cast<int>(index) == m_audio_stream_index) continue;
            if (m_format_context->streams[index] != nullptr) {
                m_format_context->streams[index]->discard = AVDISCARD_ALL;
            }
        }

        m_audio_stream = m_format_context->streams[m_audio_stream_index];
        if (m_audio_stream == nullptr || m_audio_stream->codecpar == nullptr) {
            return fail("FFmpeg audio stream is missing codec parameters");
        }

        const AVCodec* codec = avcodec_find_decoder(m_audio_stream->codecpar->codec_id);
        if (codec == nullptr) {
            return fail("failed to find an FFmpeg decoder for the audio stream");
        }

        m_codec_context = avcodec_alloc_context3(codec);
        if (m_codec_context == nullptr) {
            return fail("failed to allocate an FFmpeg audio decoder context");
        }

        if (const int result = avcodec_parameters_to_context(
                m_codec_context,
                m_audio_stream->codecpar);
            result < 0) {
            return fail("failed to copy FFmpeg audio codec parameters: " + AvErrorString(result));
        }

        if (const int result = avcodec_open2(m_codec_context, codec, nullptr); result < 0) {
            return fail("failed to open the FFmpeg audio decoder: " + AvErrorString(result));
        }

        av_channel_layout_default(&m_output_layout, static_cast<int>(m_desc.channels));

        if (const int result = swr_alloc_set_opts2(
                &m_swr,
                &m_output_layout,
                AV_SAMPLE_FMT_FLT,
                static_cast<int>(m_desc.sampleRate),
                &m_codec_context->ch_layout,
                m_codec_context->sample_fmt,
                m_codec_context->sample_rate,
                0,
                nullptr);
            result < 0) {
            return fail("failed to allocate the FFmpeg audio resampler: " + AvErrorString(result));
        }
        if (const int result = swr_init(m_swr); result < 0) {
            return fail("failed to initialize the FFmpeg audio resampler: " + AvErrorString(result));
        }

        m_packet = av_packet_alloc();
        m_frame = av_frame_alloc();
        if (m_packet == nullptr || m_frame == nullptr) {
            return fail("failed to allocate FFmpeg audio packet/frame buffers");
        }

        return true;
    }

    void closeDecoder()
    {
        m_pump.reset();
        if (m_packet != nullptr) av_packet_free(&m_packet);
        if (m_frame != nullptr) av_frame_free(&m_frame);
        if (m_swr != nullptr) swr_free(&m_swr);
        if (m_codec_context != nullptr) avcodec_free_context(&m_codec_context);
        if (m_format_context != nullptr) avformat_close_input(&m_format_context);
        if (m_input_source != nullptr) m_input_source->Close();
        av_channel_layout_uninit(&m_output_layout);
        m_output_layout = {};
        m_audio_stream = nullptr;
        m_audio_stream_index = -1;
        m_pending_samples.clear();
        m_pending_offset_samples = 0;
        m_open = false;
        m_loop_produced_samples = false;
        m_finished = false;
    }

    bool seekToStart()
    {
        if (m_format_context == nullptr || m_codec_context == nullptr || m_audio_stream == nullptr) return false;
        if (const int result = av_seek_frame(
                m_format_context,
                m_audio_stream_index,
                0,
                AVSEEK_FLAG_BACKWARD);
            result < 0) {
            LOG_ERROR("failed to loop FFmpeg audio stream for \"%s\": %s",
                      m_input_source->Description().c_str(),
                      AvErrorString(result).c_str());
            return false;
        }

        avcodec_flush_buffers(m_codec_context);
        if (m_swr != nullptr) {
            swr_close(m_swr);
            if (swr_init(m_swr) < 0) return false;
        }
        m_pump.reset();
        av_packet_unref(m_packet);
        av_frame_unref(m_frame);
        m_loop_produced_samples = false;
        return true;
    }

    size_t pendingFrames() const
    {
        if (m_desc.channels == 0) return 0;
        const size_t pending_samples = m_pending_samples.size() - m_pending_offset_samples;
        return pending_samples / m_desc.channels;
    }

    static detail::DecodeResult result(int code, std::string* error)
    {
        if (code >= 0) return detail::DecodeResult::Ok;
        if (code == AVERROR(EAGAIN)) return detail::DecodeResult::Again;
        if (code == AVERROR_EOF) return detail::DecodeResult::End;
        if (error != nullptr) *error = AvErrorString(code);
        return detail::DecodeResult::Error;
    }

    detail::DecodeResult receive(std::string* error) override {
        return result(avcodec_receive_frame(m_codec_context, m_frame), error);
    }
    detail::DecodeResult read(std::string* error) override {
        while (true) {
            const int code = av_read_frame(m_format_context, m_packet);
            if (code < 0) return result(code, error);
            if (m_packet->stream_index == m_audio_stream_index) return detail::DecodeResult::Ok;
            av_packet_unref(m_packet);
        }
    }
    detail::DecodeResult send(std::string* error) override {
        return result(avcodec_send_packet(m_codec_context, m_packet), error);
    }
    detail::DecodeResult drain(std::string* error) override {
        return result(avcodec_send_packet(m_codec_context, nullptr), error);
    }
    void releasePacket() override {
        if (m_packet != nullptr) av_packet_unref(m_packet);
    }

    int convertFrame(bool draining)
    {
        const int input_samples = draining ? 0 : m_frame->nb_samples;
        const int capacity = swr_get_out_samples(m_swr, input_samples);
        if (capacity < 0) return capacity;
        m_converted.resize(static_cast<size_t>(std::max(capacity, 1)) * m_desc.channels);
        uint8_t* output[] = { reinterpret_cast<uint8_t*>(m_converted.data()) };
        const int samples = swr_convert(m_swr, output, std::max(capacity, 1),
            draining ? nullptr : const_cast<const uint8_t**>(m_frame->extended_data), input_samples);
        if (! draining) av_frame_unref(m_frame);
        if (samples <= 0) return samples;
        m_converted.resize(static_cast<size_t>(samples) * m_desc.channels);
        std::swap(m_pending_samples, m_converted);
        m_pending_offset_samples = 0;
        m_loop_produced_samples = true;
        return samples;
    }

    bool decodeMoreAudio()
    {
        if (m_finished) return false;
        while (true) {
            std::string error;
            const auto decoded = m_pump.next(&error);
            if (decoded == detail::DecodeResult::Error) {
                LOG_ERROR("failed to decode FFmpeg audio for \"%s\": %s",
                          m_input_source->Description().c_str(), error.c_str());
                m_finished = true;
                return false;
            }
            const bool draining = decoded == detail::DecodeResult::End;
            const int samples = convertFrame(draining);
            if (samples < 0) {
                LOG_ERROR("failed to resample FFmpeg audio for \"%s\": %s",
                          m_input_source->Description().c_str(), AvErrorString(samples).c_str());
                m_finished = true;
                return false;
            }
            if (samples > 0) return true;
            if (draining) {
                // An empty stream must terminate even when looping is enabled.
                if (! m_options.loop || ! m_loop_produced_samples || ! seekToStart()) {
                    m_finished = true;
                    return false;
                }
            }
        }
    }

private:
    detail::AudioDecodePump m_pump { *this };
    bool m_loop_produced_samples { false };
    bool m_finished { false };
    std::unique_ptr<FfmpegInputSource> m_input_source;
    Options                            m_options {};
    Desc                               m_desc {};
    bool                               m_open { false };
    AVFormatContext*                   m_format_context { nullptr };
    AVCodecContext*                    m_codec_context { nullptr };
    AVStream*                          m_audio_stream { nullptr };
    int                                m_audio_stream_index { -1 };
    SwrContext*                        m_swr { nullptr };
    AVPacket*                          m_packet { nullptr };
    AVFrame*                           m_frame { nullptr };
    AVChannelLayout                    m_output_layout {};
    std::vector<float>                 m_pending_samples;
    std::vector<float>                 m_converted; // swr_convert output scratch
    size_t                             m_pending_offset_samples { 0 };
};

} // namespace

std::unique_ptr<SoundStream> CreateFfmpegSoundStream(const std::filesystem::path& media_path,
                                                     std::string* error,
                                                     SoundStream::Options options, bool audio_optional)
{
    if (media_path.empty()) {
        SetError(error, "pure-video audio path must not be empty");
        return nullptr;
    }
    if (!std::filesystem::is_regular_file(media_path)) {
        SetError(
            error,
            std::string("pure-video audio file does not exist: ") + media_path.string());
        return nullptr;
    }
    PathFfmpegInputSource input_source(media_path);
    if (!ProbeHasAudioStream(input_source, error, audio_optional)) {
        return nullptr;
    }

    return std::make_unique<FfmpegSoundStream>(media_path, options);
}

std::unique_ptr<SoundStream> CreateFfmpegSoundStream(std::shared_ptr<fs::IBinaryStream> stream,
                                                     std::string* error,
                                                     SoundStream::Options options)
{
    if (stream == nullptr) {
        SetError(error, "VFS audio stream must not be null");
        return nullptr;
    }

    auto input_source = std::make_unique<StreamFfmpegInputSource>(std::move(stream));
    if (!ProbeHasAudioStream(*input_source, error)) {
        return nullptr;
    }

    return std::make_unique<FfmpegSoundStream>(std::move(input_source), options);
}

} // namespace wallpaper::audio
