#include "analog_core_model.h"
#include "larpixsim/backend.h"

#include <array>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <memory>

#include "Vdigital_core.h"
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
