#include "analog_core_model.h"
#include "larpixsim/backend.h"

#include <array>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <memory>

#include "Vdigital_core.h"
#include "Vdigital_core___024root.h"
#include "Vdigital_core_channel_ctrl.h"
#include "verilated.h"

namespace {

class NullBackend {
  public:
    int tick(const larpixsim_backend_tick_inputs_t* in, larpixsim_backend_tick_outputs_t* out) {
        (void)in;
        std::memset(out, 0, sizeof(*out));
        return 0;
    }
};

class CosimBackend {
  public:
    CosimBackend()
        : context_(), dut_(&context_) {
        context_.debug(0);
        reset_model();
    }

    int tick(const larpixsim_backend_tick_inputs_t* in, larpixsim_backend_tick_outputs_t* out) {
        drive_serial_inputs(*in);
        drive_analog_inputs(*in);
        clock_tick(in->reset_n != 0);
        sample_serial_outputs(out);
        out->tx_packet_count = 0;
        out->rx_packet_count = 0;
        out->local_event_count = 0;
        out->drop_count = 0;
        sample_fifo_occupancy(out);
        return 0;
    }

  private:
    void reset_model() {
        dut_.clk = 0;
        dut_.reset_n = 0;
        dut_.external_trigger = 0;
        dut_.posi = 0xF;
        dut_.done = 0ULL;
        dut_.hit = 0ULL;
        for (std::size_t i = 0; i < dout_words_.size(); ++i) {
            dut_.dout[i] = 0u;
        }
        for (int i = 0; i < 4; ++i) {
            dut_.eval();
            dut_.clk = 1;
            dut_.eval();
            dut_.clk = 0;
        }
        dut_.reset_n = 1;
        dut_.eval();
    }

    void drive_serial_inputs(const larpixsim_backend_tick_inputs_t& in) {
        uint8_t posi = 0xF;
        for (int edge = 0; edge < LARPIXSIM_EDGE_COUNT; ++edge) {
            const uint8_t bit = in.rx_bit_valid[edge] ? (in.rx_bit_value[edge] ? 1u : 0u) : 1u;
            if (bit) {
                posi |= static_cast<uint8_t>(1u << edge);
            } else {
                posi &= static_cast<uint8_t>(~(1u << edge));
            }
        }
        dut_.posi = posi;
        dut_.external_trigger = 0;
    }

    void drive_analog_inputs(const larpixsim_backend_tick_inputs_t& in) {
        larpix::AnalogCoreModel::Inputs ain{};
        ain.reset_n = in.reset_n != 0;
        ain.threshold_global = dut_.threshold_global;
        ain.sample = dut_.sample;
        ain.csa_reset = dut_.csa_reset;
        ain.pixel_trim_words = &dut_.pixel_trim_dac[0];
        ain.pixel_trim_word_count = larpix::AnalogCoreModel::kPixelTrimWords;
        for (std::size_t ch = 0; ch < LARPIXSIM_CHANNEL_COUNT; ++ch) {
            ain.charge_in_r[ch] = in.charge_in[ch];
        }

        const auto& aout = analog_.step(ain);
        dut_.hit = aout.pack_hit_bits();
        dut_.done = aout.pack_done_bits();
        dout_words_ = aout.pack_dout_words();
        for (std::size_t i = 0; i < dout_words_.size(); ++i) {
            dut_.dout[i] = dout_words_[i];
        }
    }

    void clock_tick(bool reset_n) {
        dut_.reset_n = reset_n ? 1 : 0;
        dut_.clk = 0;
        dut_.eval();
        dut_.clk = 1;
        dut_.eval();
        dut_.clk = 0;
        dut_.eval();
    }

    void sample_serial_outputs(larpixsim_backend_tick_outputs_t* out) {
        std::memset(out, 0, sizeof(*out));
        const uint8_t piso = dut_.piso;
        const uint8_t tx_enable = dut_.tx_enable;
        for (int edge = 0; edge < LARPIXSIM_EDGE_COUNT; ++edge) {
            out->tx_bit_valid[edge] = (tx_enable >> edge) & 1u;
            out->tx_bit_value[edge] = (piso >> edge) & 1u;
        }
    }

    std::array<Vdigital_core_channel_ctrl*, LARPIXSIM_CHANNEL_COUNT> channel_ctrls() {
        return {
            dut_.__PVT__digital_core__DOT__g_channels__BRA__0__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__1__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__2__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__3__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__4__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__5__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__6__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__7__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__8__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__9__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__10__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__11__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__12__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__13__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__14__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__15__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__16__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__17__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__18__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__19__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__20__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__21__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__22__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__23__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__24__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__25__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__26__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__27__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__28__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__29__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__30__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__31__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__32__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__33__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__34__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__35__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__36__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__37__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__38__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__39__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__40__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__41__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__42__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__43__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__44__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__45__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__46__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__47__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__48__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__49__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__50__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__51__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__52__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__53__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__54__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__55__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__56__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__57__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__58__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__59__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__60__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__61__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__62__KET____DOT__channel_ctrl_inst,
            dut_.__PVT__digital_core__DOT__g_channels__BRA__63__KET____DOT__channel_ctrl_inst
        };
    }

    void sample_fifo_occupancy(larpixsim_backend_tick_outputs_t* out) {
        out->chip_fifo_occupancy = static_cast<uint32_t>(dut_.rootp->digital_core__DOT__external_interface_inst__DOT__hydra_ctrl_inst__DOT__fifo_counter);

        auto channels = channel_ctrls();
        for (int i = 0; i < 5; ++i) {
            out->channel_fifo_occupancy[i] = static_cast<uint32_t>(channels[static_cast<std::size_t>(i)]->__PVT__local_fifo_counter);
        }
        for (std::size_t i = 0; i < channels.size(); ++i) {
            out->channel_fifo_occupancy_all[i] = static_cast<uint32_t>(channels[i]->__PVT__local_fifo_counter);
            out->channel_packet_generated[i] = channels[i]->__PVT__write_local_fifo_n ? 0u : 1u;
        }
    }

    VerilatedContext context_;
    Vdigital_core dut_;
    larpix::AnalogCoreModel analog_;
    std::array<uint32_t, larpix::AnalogCoreModel::kDoutWords> dout_words_{};
};

int null_tick(void* ctx, const larpixsim_backend_tick_inputs_t* in, larpixsim_backend_tick_outputs_t* out) {
    return static_cast<NullBackend*>(ctx)->tick(in, out);
}

void null_destroy(void* ctx) {
    delete static_cast<NullBackend*>(ctx);
}

int cosim_tick(void* ctx, const larpixsim_backend_tick_inputs_t* in, larpixsim_backend_tick_outputs_t* out) {
    return static_cast<CosimBackend*>(ctx)->tick(in, out);
}

void cosim_destroy(void* ctx) {
    delete static_cast<CosimBackend*>(ctx);
}

const larpixsim_backend_vtbl kNullBackendVtable = {
    &null_tick,
    &null_destroy,
};

const larpixsim_backend_vtbl kCosimBackendVtable = {
    &cosim_tick,
    &cosim_destroy,
};

}  // namespace

extern "C" int larpixsim_backend_create_null(larpixsim_backend_handle_t* backend) {
    if (backend == nullptr) {
        return -1;
    }
    backend->ctx = new (std::nothrow) NullBackend();
    if (backend->ctx == nullptr) {
        backend->vtbl = nullptr;
        return -1;
    }
    backend->vtbl = &kNullBackendVtable;
    return 0;
}

extern "C" int larpixsim_backend_create_cosim(larpixsim_backend_handle_t* backend) {
    if (backend == nullptr) {
        return -1;
    }
    backend->ctx = new (std::nothrow) CosimBackend();
    if (backend->ctx == nullptr) {
        backend->vtbl = nullptr;
        return -1;
    }
    backend->vtbl = &kCosimBackendVtable;
    return 0;
}

extern "C" void larpixsim_backend_destroy(larpixsim_backend_handle_t* backend) {
    if (backend == nullptr || backend->vtbl == nullptr || backend->vtbl->destroy == nullptr) {
        return;
    }
    backend->vtbl->destroy(backend->ctx);
    backend->ctx = nullptr;
    backend->vtbl = nullptr;
}
