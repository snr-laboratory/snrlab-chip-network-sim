#pragma once

#include <array>
#include <bitset>
#include <cstddef>
#include <cstdint>

namespace larpix {

class AnalogCoreModel {
public:
    static constexpr std::size_t kNumChannels = 64;
    static constexpr std::size_t kAdcBits = 10;
    static constexpr std::size_t kPixelTrimBits = 5;
    static constexpr std::size_t kDoutBusBits = kNumChannels * kAdcBits;
    static constexpr std::size_t kDoutWordCount = (kDoutBusBits + 31) / 32;
    static constexpr std::size_t kPixelTrimBusBits = kNumChannels * kPixelTrimBits;
    static constexpr std::size_t kPixelTrimWordCount = (kPixelTrimBusBits + 31) / 32;

    struct Inputs {
        std::array<double, kNumChannels> charge_in_r{};
        std::array<uint8_t, kNumChannels> pixel_trim_dac{};
        uint8_t threshold_global = 0;
        std::bitset<kNumChannels> gated_reset{};
        std::bitset<kNumChannels> csa_bypass_enable{};
        std::bitset<kNumChannels> csa_monitor_select{};
        std::bitset<kNumChannels> csa_bypass_select{};
        std::bitset<kNumChannels> sample{};
        std::bitset<kNumChannels> csa_reset{};
    };

    struct Outputs {
        std::array<uint16_t, kNumChannels> dout{};
        std::bitset<kNumChannels> hit{};
        std::bitset<kNumChannels> done{};

        std::array<uint32_t, kDoutWordCount> pack_dout_words() const;
        uint64_t pack_hit_bits() const;
        uint64_t pack_done_bits() const;
    };

    struct ChannelState {
        double csa_vout = 0.5;
        bool prev_sample = true;
        uint16_t dout = 0;
        bool hit = false;
        bool done = false;
    };

    AnalogCoreModel();

    void reset();
    const Outputs& step(const Inputs& in);
    const Outputs& outputs() const;
    const ChannelState& channel_state(std::size_t index) const;

    static std::array<uint8_t, kNumChannels> unpack_pixel_trim_words(
        const uint32_t* words,
        std::size_t word_count);

private:
    static constexpr double kVref = 1.6;
    static constexpr double kVcm = 0.8;
    static constexpr double kFeedbackCapacitance = 40e-15;
    static constexpr double kVoutDcCsa = 0.5;
    static constexpr double kVdda = 1.8;
    static constexpr double kVoffset = 0.47;
    static constexpr double kGlobalLsb = kVdda / 256.0;
    static constexpr double kTrimLsb = 0.05 / 32.0;

    static double compute_threshold(uint8_t threshold_global, uint8_t pixel_trim_dac);
    static uint16_t quantize_adc(double vin_r);

    std::array<ChannelState, kNumChannels> channels_{};
    Outputs outputs_{};
};

} // namespace larpix
