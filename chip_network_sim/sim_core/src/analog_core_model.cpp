#include "analog_core_model.h"

#include <algorithm>
#include <cmath>
#include <stdexcept>

namespace larpix {

AnalogCoreModel::AnalogCoreModel() {
    reset();
}

void AnalogCoreModel::reset() {
    for (std::size_t ch = 0; ch < kNumChannels; ++ch) {
        channels_[ch] = ChannelState{};
        outputs_.dout_words[ch] = 0;
        outputs_.hit_bits[ch] = false;
        outputs_.done_bits[ch] = false;
    }
}

const AnalogCoreModel::Outputs& AnalogCoreModel::outputs() const {
    return outputs_;
}

const AnalogCoreModel::ChannelState& AnalogCoreModel::channel_state(std::size_t ch) const {
    if (ch >= kNumChannels) {
        throw std::out_of_range("analog channel index out of range");
    }
    return channels_[ch];
}

uint64_t AnalogCoreModel::Outputs::pack_hit_bits() const {
    return hit_bits.to_ullong();
}

uint64_t AnalogCoreModel::Outputs::pack_done_bits() const {
    return done_bits.to_ullong();
}

std::array<uint32_t, AnalogCoreModel::kDoutWords> AnalogCoreModel::Outputs::pack_dout_words() const {
    std::array<uint32_t, kDoutWords> words{};
    std::size_t bit_index = 0;

    for (std::size_t ch = 0; ch < kNumChannels; ++ch) {
        uint16_t sample = dout_words[ch] & ((1u << kAdcBits) - 1u);
        for (std::size_t b = 0; b < kAdcBits; ++b, ++bit_index) {
            if ((sample >> b) & 1u) {
                words[bit_index / 32] |= (1u << (bit_index % 32));
            }
        }
    }
    return words;
}

std::array<uint8_t, AnalogCoreModel::kNumChannels> AnalogCoreModel::unpack_pixel_trim_words(
    const uint32_t* words, std::size_t word_count) {
    if (words == nullptr) {
        throw std::invalid_argument("pixel trim word pointer must not be null");
    }
    if (word_count < kPixelTrimWords) {
        throw std::invalid_argument("pixel trim word count is too small");
    }

    std::array<uint8_t, kNumChannels> trims{};
    std::size_t bit_index = 0;
    for (std::size_t ch = 0; ch < kNumChannels; ++ch) {
        uint8_t trim = 0;
        for (std::size_t b = 0; b < kPixelTrimBits; ++b, ++bit_index) {
            uint32_t word = words[bit_index / 32];
            uint32_t bit = (word >> (bit_index % 32)) & 1u;
            trim |= static_cast<uint8_t>(bit << b);
        }
        trims[ch] = trim;
    }
    return trims;
}

double AnalogCoreModel::compute_threshold(uint8_t threshold_global, uint8_t pixel_trim) {
    return 0.47 + static_cast<double>(threshold_global) * (1.8 / 256.0)
           + static_cast<double>(pixel_trim) * (0.05 / 32.0);
}

uint16_t AnalogCoreModel::quantize_adc(double volts) {
    double clamped = std::clamp(volts, 0.0, 1.8);
    double scaled = (clamped / 1.8) * ((1u << kAdcBits) - 1u);
    return static_cast<uint16_t>(std::lround(scaled));
}

const AnalogCoreModel::Outputs& AnalogCoreModel::step(const Inputs& in) {
    const auto trims = unpack_pixel_trim_words(in.pixel_trim_words, in.pixel_trim_word_count);

    for (std::size_t ch = 0; ch < kNumChannels; ++ch) {
        ChannelState& channel = channels_[ch];
        const bool sample = ((in.sample >> ch) & 1ULL) != 0;
        const bool csa_reset = ((in.csa_reset >> ch) & 1ULL) != 0;

        channel.pixel_trim = trims[ch];

        if (!in.reset_n || csa_reset) {
            channel.csa_vout = kVoutDcCsa;
            channel.adc_code = 0;
        }

        channel.csa_vout += -(in.charge_in_r[ch] / kFeedbackCapacitance);
        channel.hit = channel.csa_vout > compute_threshold(in.threshold_global, channel.pixel_trim);

        if (channel.prev_sample && !sample) {
            channel.adc_code = quantize_adc(channel.csa_vout);
        }

        channel.done = !sample;
        channel.prev_sample = sample;

        outputs_.dout_words[ch] = channel.adc_code;
        outputs_.hit_bits[ch] = channel.hit;
        outputs_.done_bits[ch] = channel.done;
    }

    return outputs_;
}

}  // namespace larpix
