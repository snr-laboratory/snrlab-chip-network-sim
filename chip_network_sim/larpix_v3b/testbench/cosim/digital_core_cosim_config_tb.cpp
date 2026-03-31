#include <array>
#include <bitset>
#include <cstdint>
#include <cstdlib>
#include <exception>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

#include "analog_core_model.h"
#include "Vdigital_core.h"
#include "Vdigital_core___024root.h"
#include "verilated.h"

namespace {

using larpix::AnalogCoreModel;

constexpr vluint64_t kHalfPeriodTicks = 5;
constexpr uint8_t kDefaultChipId = 0x01;
constexpr uint32_t kMagicNumber = 0x89504E47u;
constexpr int kNumPacketBits = 64;

enum ConfigAddr : std::size_t {
    GLOBAL_THRESH = 64,
    CHIP_ID = 122,
    ENABLE_PISO_DOWN = 125,
    ENABLE_POSI = 126,
};

enum PacketType : uint8_t {
    DATA_OP = 0x1,
    CONFIG_WRITE_OP = 0x2,
    CONFIG_READ_OP = 0x3,
};

struct HarnessConfig {
    uint64_t max_cycles = 2500;
    uint8_t posi_idle = 0xF;
    bool verbose = false;
};

class DigitalCoreCosimConfigHarness {
public:
    explicit DigitalCoreCosimConfigHarness(const HarnessConfig& cfg)
        : cfg_(cfg) {
        Verilated::traceEverOn(false);
        dut_.clk = 0;
        dut_.reset_n = 0;
        dut_.external_trigger = 0;
        dut_.posi = cfg_.posi_idle & 0xF;
        clear_input_buses();
        analog_.reset();
    }

    int run() {
        try {
            for (uint64_t cycle = 0; cycle < cfg_.max_cycles && phase_ != Phase::Done; ++cycle) {
                step_cycle(cycle);
            }

            expect(phase_ == Phase::Done, "test did not complete before max_cycles");
            expect(defaults_checked_, "default checks never ran");
            expect(write_enable_seen_, "ENABLE_PISO_DOWN write never took effect");
            expect(write_thresh_seen_, "GLOBAL_THRESH write never took effect");
            expect(launched_reply_packets_.size() >= 2, "did not launch both config-read replies toward UART0");
            expect(tx_started_, "UART0 never asserted tx_busy during config-read replies");
            expect(uart_left_idle_, "UART0 never left idle during config-read replies");

            std::cout
                << "PASS: digital_core_cosim_config_tb drove config write/read packets over POSI and observed correct register updates and readback replies on PISO"
                << '\n'
                << "write_enable_reply=0x" << std::hex << launched_reply_packets_[0] << '\n'
                << "write_global_thresh_reply=0x" << launched_reply_packets_[1] << std::dec << '\n';
        } catch (const std::exception& ex) {
            std::cerr << "harness error: " << ex.what() << '\n';
            return 1;
        }
        return 0;
    }

private:
    // PASS requires all of the following:
    // 1. After reset, default configuration must load correctly:
    //    - config_bits[CHIP_ID] == 0x01
    //    - config_bits[ENABLE_POSI][3:0] == 0xF
    //    - tx_enable == 0 because no PISO lanes are enabled by default
    // 2. A CONFIG_WRITE packet sent over posi[0] must update ENABLE_PISO_DOWN
    //    to 0x01, and the mapped top-level tx_enable output must change to 0x1.
    // 3. A second CONFIG_WRITE packet sent over posi[0] must update
    //    GLOBAL_THRESH to 0x22, and the mapped threshold_global output must
    //    change to 0x22.
    // 4. A CONFIG_READ packet for ENABLE_PISO_DOWN must produce a reply that is
    //    loaded into UART0 for transmission, and that reply must decode as
    //    a CONFIG_READ packet with
    //    chip ID 0x01, register address ENABLE_PISO_DOWN, data 0x01,
    //    downstream bit set, original magic number preserved, and valid parity.
    // 5. A CONFIG_READ packet for GLOBAL_THRESH must produce a second reply
    //    loaded into UART0 for transmission, and that reply must decode as
    //    a CONFIG_READ packet with
    //    chip ID 0x01, register address GLOBAL_THRESH, data 0x22,
    //    downstream bit set, original magic number preserved, and valid parity.
    // 6. UART0 must actually launch the readback replies: tx_busy must assert
    //    and piso[0] must leave the idle-high state.

    enum class Phase {
        WaitDefaults,
        SendEnableWrite,
        WaitEnableWrite,
        SendThreshWrite,
        WaitThreshWrite,
        SendEnableRead,
        WaitEnableReadReply,
        SendThreshRead,
        WaitThreshReadReply,
        Done,
    };

    struct SoftUartTx {
        std::vector<uint8_t> bits;
        std::size_t index = 0;

        void load_packet(uint64_t packet) {
            bits.clear();
            bits.reserve(kNumPacketBits + 2);
            bits.push_back(0u);  // start bit
            for (int i = 0; i < kNumPacketBits; ++i) {
                bits.push_back(static_cast<uint8_t>((packet >> i) & 0x1ULL));
            }
            bits.push_back(1u);  // stop bit
            index = 0;
        }

        bool active() const {
            return index < bits.size();
        }

        uint8_t current_bit(uint8_t idle_high) const {
            return active() ? bits[index] : static_cast<uint8_t>(idle_high & 0x1u);
        }

        void advance() {
            if (active()) {
                ++index;
            }
        }
    };

    void step_cycle(uint64_t cycle) {
        if (cycle == 40) {
            dut_.reset_n = 1;
        }

        drive_posi();
        prepare_analog_inputs();
        drive_digital_inputs_from_analog();
        tick();
        post_tick_checks(cycle);

        if (cfg_.verbose && (cycle % 50 == 0)) {
            std::cout << "cycle=" << cycle
                      << " phase=" << phase_name(phase_)
                      << " tx_enable=" << static_cast<unsigned>(dut_.tx_enable & 0xFu)
                      << " threshold_global=0x" << std::hex << static_cast<unsigned>(dut_.threshold_global & 0xFFu) << std::dec
                      << " launched_replies=" << launched_reply_packets_.size()
                      << '\n';
        }
    }

    void drive_posi() {
        const uint8_t lane0 = uart_tx_.current_bit(1u);
        dut_.posi = static_cast<uint8_t>((cfg_.posi_idle & 0xEu) | lane0);
    }

    void clear_input_buses() {
        for (std::size_t i = 0; i < AnalogCoreModel::kDoutWordCount; ++i) {
            dut_.dout[i] = 0;
        }
        dut_.done = 0;
        dut_.hit = 0;
    }

    void prepare_analog_inputs() {
        AnalogCoreModel::Inputs in{};
        in.threshold_global = static_cast<uint8_t>(dut_.threshold_global & 0xFFu);
        in.sample = qdata_to_bitset(dut_.sample);
        in.csa_reset = qdata_to_bitset(dut_.csa_reset);
        in.gated_reset = qdata_to_bitset(dut_.gated_reset);
        in.csa_bypass_enable = qdata_to_bitset(dut_.csa_bypass_enable);
        in.csa_bypass_select = qdata_to_bitset(dut_.csa_bypass_select);
        in.csa_monitor_select = qdata_to_bitset(dut_.csa_monitor_select);
        in.pixel_trim_dac = AnalogCoreModel::unpack_pixel_trim_words(
            &dut_.pixel_trim_dac[0],
            AnalogCoreModel::kPixelTrimWordCount);
        analog_.step(in);
    }

    void drive_digital_inputs_from_analog() {
        const auto& out = analog_.outputs();
        const auto dout_words = out.pack_dout_words();
        for (std::size_t i = 0; i < dout_words.size(); ++i) {
            dut_.dout[i] = dout_words[i];
        }
        dut_.hit = out.pack_hit_bits();
        dut_.done = out.pack_done_bits();
    }

    static std::bitset<AnalogCoreModel::kNumChannels> qdata_to_bitset(uint64_t value) {
        return std::bitset<AnalogCoreModel::kNumChannels>(value);
    }

    Vdigital_core___024root& root() {
        return *dut_.rootp;
    }

    void post_tick_checks(uint64_t cycle) {
        uart_tx_.advance();

        if (!defaults_checked_ && cycle >= 80) {
            check_defaults();
            defaults_checked_ = true;
            phase_ = Phase::SendEnableWrite;
        }

        if (root().digital_core__DOT__external_interface_inst__DOT____Vcellout__g_uart__BRA__0__KET____DOT__uart_inst__tx_busy) {
            tx_started_ = true;
        }
        if (tx_started_ && ((dut_.piso & 0x1u) == 0u || ((root().digital_core__DOT__external_interface_inst__DOT__ld_tx_data_uart & 0x1u) != 0u))) {
            uart_left_idle_ = true;
        }

        if ((root().digital_core__DOT__external_interface_inst__DOT__ld_tx_data_uart & 0x1u) != 0u) {
            const uint64_t launched = root().digital_core__DOT__external_interface_inst__DOT__hydra_ctrl_inst__DOT__fifo_rd_data;
            if (launched_reply_packets_.empty() || launched_reply_packets_.back() != launched) {
                launched_reply_packets_.push_back(launched);
                if (cfg_.verbose) {
                    std::cout << "launched_reply=0x" << std::hex << launched << std::dec << " count=" << launched_reply_packets_.size() << "\n";
                }
            }
        }

        switch (phase_) {
        case Phase::WaitDefaults:
            break;
        case Phase::SendEnableWrite:
            if (!uart_tx_.active()) {
                uart_tx_.load_packet(build_config_write_packet(kDefaultChipId, ENABLE_PISO_DOWN, 0x01));
                phase_ = Phase::WaitEnableWrite;
            }
            break;
        case Phase::WaitEnableWrite:
            if (root().digital_core__DOT__config_bits[ENABLE_PISO_DOWN] == 0x01u) {
                write_enable_seen_ = true;
                expect((dut_.tx_enable & 0xFu) == 0x1u,
                    "ENABLE_PISO_DOWN write did not map to tx_enable lane 0");
                phase_ = Phase::SendThreshWrite;
            }
            break;
        case Phase::SendThreshWrite:
            if (!uart_tx_.active()) {
                uart_tx_.load_packet(build_config_write_packet(kDefaultChipId, GLOBAL_THRESH, 0x22));
                phase_ = Phase::WaitThreshWrite;
            }
            break;
        case Phase::WaitThreshWrite:
            if (root().digital_core__DOT__config_bits[GLOBAL_THRESH] == 0x22u) {
                write_thresh_seen_ = true;
                expect((dut_.threshold_global & 0xFFu) == 0x22u,
                    "GLOBAL_THRESH write did not map to threshold_global output");
                phase_ = Phase::SendEnableRead;
            }
            break;
        case Phase::SendEnableRead:
            if (!uart_tx_.active()) {
                launched_reply_packets_.clear();
                uart_tx_.load_packet(build_config_read_packet(kDefaultChipId, ENABLE_PISO_DOWN));
                phase_ = Phase::WaitEnableReadReply;
            }
            break;
        case Phase::WaitEnableReadReply:
            if (launched_reply_packets_.size() >= 1) {
                validate_config_read_reply(launched_reply_packets_[0], ENABLE_PISO_DOWN, 0x01);
                phase_ = Phase::SendThreshRead;
            }
            break;
        case Phase::SendThreshRead:
            if (!uart_tx_.active()) {
                uart_tx_.load_packet(build_config_read_packet(kDefaultChipId, GLOBAL_THRESH));
                phase_ = Phase::WaitThreshReadReply;
            }
            break;
        case Phase::WaitThreshReadReply:
            if (launched_reply_packets_.size() >= 2) {
                validate_config_read_reply(launched_reply_packets_[1], GLOBAL_THRESH, 0x22);
                phase_ = Phase::Done;
            }
            break;
        case Phase::Done:
            break;
        }
    }

    void check_defaults() {
        expect(root().digital_core__DOT__config_bits[CHIP_ID] == kDefaultChipId,
            "default chip ID should load as 0x01");
        expect((root().digital_core__DOT__config_bits[ENABLE_POSI] & 0x0Fu) == 0x0Fu,
            "default POSI enables should load as 0xF");
        expect((dut_.tx_enable & 0x0Fu) == 0u,
            "TX lanes should be disabled by default");
    }

    void validate_config_read_reply(uint64_t packet, std::size_t addr, uint8_t expected_data) {
        expect((packet & 0x3u) == CONFIG_READ_OP,
            "reply packet type should be CONFIG_READ_OP");
        expect(((packet >> 2U) & 0xffU) == kDefaultChipId,
            std::string("reply chip ID should be 0x01, packet=0x") + hex_u64(packet));
        expect(((packet >> 10U) & 0xffU) == addr,
            "reply register address mismatch");
        expect(((packet >> 18U) & 0xffU) == expected_data,
            "reply register data mismatch");
        expect(((packet >> 26U) & 0xffffffffULL) == kMagicNumber,
            "reply magic number mismatch");
        expect(((packet >> 62U) & 0x1u) == 1u,
            "reply downstream bit should be set");
        expect(check_parity(packet),
            "reply parity bit does not match payload parity");
    }

    static uint64_t build_config_write_packet(uint8_t chip_id, uint8_t addr, uint8_t data) {
        uint64_t payload = 0;
        payload |= static_cast<uint64_t>(CONFIG_WRITE_OP & 0x3u);
        payload |= static_cast<uint64_t>(chip_id) << 2U;
        payload |= static_cast<uint64_t>(addr) << 10U;
        payload |= static_cast<uint64_t>(data) << 18U;
        payload |= static_cast<uint64_t>(kMagicNumber) << 26U;
        payload |= 0ULL << 58U;  // stats nibble
        payload |= 0ULL << 62U;  // upstream request
        return with_parity(payload);
    }

    static uint64_t build_config_read_packet(uint8_t chip_id, uint8_t addr) {
        uint64_t payload = 0;
        payload |= static_cast<uint64_t>(CONFIG_READ_OP & 0x3u);
        payload |= static_cast<uint64_t>(chip_id) << 2U;
        payload |= static_cast<uint64_t>(addr) << 10U;
        payload |= 0ULL << 18U;
        payload |= static_cast<uint64_t>(kMagicNumber) << 26U;
        payload |= 0ULL << 58U;
        payload |= 0ULL << 62U;
        return with_parity(payload);
    }

    static uint64_t with_parity(uint64_t payload63) {
        const uint64_t masked = payload63 & ((1ULL << 63U) - 1ULL);
        const uint64_t parity_bit = has_even_parity(masked) ? 1ULL : 0ULL;
        return masked | (parity_bit << 63U);
    }

    static bool check_parity(uint64_t packet) {
        const uint64_t payload = packet & ((1ULL << 63U) - 1ULL);
        const bool parity_bit = ((packet >> 63U) & 0x1u) != 0;
        return parity_bit == has_even_parity(payload);
    }

    static bool has_even_parity(uint64_t value) {
        bool parity = false;
        while (value != 0) {
            parity = !parity;
            value &= (value - 1ULL);
        }
        return !parity;
    }

    static std::string hex_u64(uint64_t value) {
        std::ostringstream oss;
        oss << std::hex << value;
        return oss.str();
    }

    static void expect(bool condition, const std::string& message) {
        if (!condition) {
            throw std::runtime_error(message);
        }
    }

    static const char* phase_name(Phase phase) {
        switch (phase) {
        case Phase::WaitDefaults: return "WaitDefaults";
        case Phase::SendEnableWrite: return "SendEnableWrite";
        case Phase::WaitEnableWrite: return "WaitEnableWrite";
        case Phase::SendThreshWrite: return "SendThreshWrite";
        case Phase::WaitThreshWrite: return "WaitThreshWrite";
        case Phase::SendEnableRead: return "SendEnableRead";
        case Phase::WaitEnableReadReply: return "WaitEnableReadReply";
        case Phase::SendThreshRead: return "SendThreshRead";
        case Phase::WaitThreshReadReply: return "WaitThreshReadReply";
        case Phase::Done: return "Done";
        }
        return "Unknown";
    }

    void tick() {
        main_time_ += kHalfPeriodTicks;
        dut_.clk = 0;
        dut_.eval();
        main_time_ += kHalfPeriodTicks;
        dut_.clk = 1;
        dut_.eval();
    }

    HarnessConfig cfg_;
    Vdigital_core dut_{};
    AnalogCoreModel analog_{};
    SoftUartTx uart_tx_{};
    vluint64_t main_time_ = 0;
    Phase phase_ = Phase::WaitDefaults;
    bool defaults_checked_ = false;
    bool write_enable_seen_ = false;
    bool write_thresh_seen_ = false;
    bool tx_started_ = false;
    bool uart_left_idle_ = false;
    std::vector<uint64_t> launched_reply_packets_{};
};

HarnessConfig parse_args(int argc, char** argv) {
    HarnessConfig cfg;
    for (int i = 1; i < argc; ++i) {
        const std::string arg = argv[i];
        if (arg == "--cycles" && i + 1 < argc) {
            cfg.max_cycles = std::strtoull(argv[++i], nullptr, 0);
        } else if (arg == "--posi-idle" && i + 1 < argc) {
            cfg.posi_idle = static_cast<uint8_t>(std::strtoul(argv[++i], nullptr, 0));
        } else if (arg == "--verbose") {
            cfg.verbose = true;
        } else {
            throw std::invalid_argument("unknown argument: " + arg);
        }
    }
    return cfg;
}

} // namespace

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    try {
        const HarnessConfig cfg = parse_args(argc, argv);
        DigitalCoreCosimConfigHarness harness(cfg);
        return harness.run();
    } catch (const std::exception& ex) {
        std::cerr << "fatal: " << ex.what() << '\n';
        return 1;
    }
}
