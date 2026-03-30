#include "analog_core_model.h"

#include <stdexcept>

namespace larpix {

std::array<uint32_t, AnalogCoreModel::kDoutWordCount>
AnalogCoreModel::Outputs::pack_dout_words() const {
    std::array<uint32_t, kDoutWordCount> words{};
    for (std::size_t ch = 0; ch < kNumChannels; ++ch) {
        const uint16_t code = static_cast<uint16_t>(dout[ch] & ((1u << kAdcBits) - 1u));
        for (std::size_t bit = 0; bit < kAdcBits; ++bit) {
            if (((code >> bit) & 1u) == 0u) {
                continue;
            }
            const std::size_t packed_bit = ch * kAdcBits + bit;
            words[packed_bit / 32] |= (1u << (packed_bit % 32));
        }
    }
    return words;
}

uint64_t
AnalogCoreModel::Outputs::pack_hit_bits() const {
    return hit.to_ullong();
}

uint64_t
AnalogCoreModel::Outputs::pack_done_bits() const {
    return done.to_ullong();
}

AnalogCoreModel::AnalogCoreModel() {
    reset();
}

void
AnalogCoreModel::reset() {
    for (auto& channel : channels_) {
        channel.csa_vout = kVoutDcCsa;
        channel.prev_sample = true;
        channel.dout = 0;
        channel.hit = false;
        channel.done = false;
    }
    outputs_ = Outputs{};
}

const AnalogCoreModel::Outputs&
AnalogCoreModel::step(const Inputs& in) {
    for (std::size_t ch = 0; ch < kNumChannels; ++ch) {
        ChannelState& channel = channels_[ch];

        if (in.csa_reset.test(ch)) {
            channel.csa_vout = kVoutDcCsa;
        } else {
            channel.csa_vout += -(in.charge_in_r[ch] / kFeedbackCapacitance);
        }

        const double threshold = compute_threshold(in.threshold_global,
            static_cast<uint8_t>(in.pixel_trim_dac[ch] & 0x1Fu));
        channel.hit = (channel.csa_vout > threshold);

        const bool sample_now = in.sample.test(ch);
        if (channel.prev_sample && !sample_now) {
            channel.dout = quantize_adc(channel.csa_vout);
        }
        channel.done = !sample_now;
        channel.prev_sample = sample_now;

        outputs_.dout[ch] = channel.dout;
        outputs_.hit.set(ch, channel.hit);
        outputs_.done.set(ch, channel.done);
    }

    return outputs_;
}

const AnalogCoreModel::Outputs&
AnalogCoreModel::outputs() const {
    return outputs_;
}

const AnalogCoreModel::ChannelState&
AnalogCoreModel::channel_state(std::size_t index) const {
    if (index >= kNumChannels) {
        throw std::out_of_range("analog channel index out of range");
    }
    return channels_[index];
}

std::array<uint8_t, AnalogCoreModel::kNumChannels>
AnalogCoreModel::unpack_pixel_trim_words(const uint32_t* words, std::size_t word_count) {
    if (words == nullptr) {
        throw std::invalid_argument("pixel trim word pointer must not be null");
    }
    if (word_count < kPixelTrimWordCount) {
        throw std::invalid_argument("pixel trim word count is too small");
    }

    std::array<uint8_t, kNumChannels> trims{};
    for (std::size_t ch = 0; ch < kNumChannels; ++ch) {
        uint8_t trim = 0;
        for (std::size_t bit = 0; bit < kPixelTrimBits; ++bit) {
            const std::size_t packed_bit = ch * kPixelTrimBits + bit;
            const uint32_t word = words[packed_bit / 32];
            const uint8_t value = static_cast<uint8_t>((word >> (packed_bit % 32)) & 0x1u);
            trim |= static_cast<uint8_t>(value << bit);
        }
        trims[ch] = trim;
    }
    return trims;
}

double
AnalogCoreModel::compute_threshold(uint8_t threshold_global, uint8_t pixel_trim_dac) {
    return kVoffset
        + static_cast<double>(threshold_global) * kGlobalLsb
        + static_cast<double>(pixel_trim_dac & 0x1Fu) * kTrimLsb;
}

uint16_t
AnalogCoreModel::quantize_adc(double vin_r) {
    double vcommon_r = vin_r;
    double vdac_r = kVref;
    uint16_t dout = 0;

    (void)kVcm;

    for (int bit = static_cast<int>(kAdcBits) - 1; bit >= 0; --bit) {
        vdac_r /= 2.0;
        if (vcommon_r > vdac_r) {
            dout |= static_cast<uint16_t>(1u << bit);
            vcommon_r -= vdac_r;
        }
    }
    return dout;
}

} // namespace larpix
