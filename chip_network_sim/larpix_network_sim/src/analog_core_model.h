#ifndef LARPIXSIM_ANALOG_CORE_MODEL_H
#define LARPIXSIM_ANALOG_CORE_MODEL_H

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
    static constexpr std::size_t kPixelTrimWords = 10;
    static constexpr std::size_t kDoutWords = 20;
    static constexpr double kVoutDcCsa = 0.5;
    static constexpr double kFeedbackCapacitance = 40e-15;

    struct Inputs {
        bool reset_n = true;
        uint8_t threshold_global = 0;
        uint64_t sample = 0;
        uint64_t csa_reset = 0;
        const uint32_t* pixel_trim_words = nullptr;
        std::size_t pixel_trim_word_count = 0;
        std::array<double, kNumChannels> charge_in_r{};
    };

    struct Outputs {
        std::array<uint16_t, kNumChannels> dout_words{};
        std::bitset<kNumChannels> hit_bits;
        std::bitset<kNumChannels> done_bits;

        uint64_t pack_hit_bits() const;
        uint64_t pack_done_bits() const;
        std::array<uint32_t, kDoutWords> pack_dout_words() const;
    };

    struct ChannelState {
        double csa_vout = kVoutDcCsa;
        bool prev_sample = false;
        uint16_t adc_code = 0;
        bool hit = false;
        bool done = false;
        uint8_t pixel_trim = 0;
    };

    AnalogCoreModel();

    void reset();
    const Outputs& step(const Inputs& in);
    const Outputs& outputs() const;
    const ChannelState& channel_state(std::size_t ch) const;

  private:
    static uint16_t quantize_adc(double volts);
    static double compute_threshold(uint8_t threshold_global, uint8_t pixel_trim);
    static std::array<uint8_t, kNumChannels> unpack_pixel_trim_words(const uint32_t* words,
                                                                     std::size_t word_count);

    std::array<ChannelState, kNumChannels> channels_{};
    Outputs outputs_{};
};

}  // namespace larpix

#endif
