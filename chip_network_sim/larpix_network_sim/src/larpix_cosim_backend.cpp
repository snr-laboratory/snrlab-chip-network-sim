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
#include "Vdigital_core_uart__Fb.h"
#include "verilated.h"

namespace {

class NullBackend {
  public:
    int tick(const larpixsim_backend_tick_inputs_t* in, larpixsim_backend_tick_outputs_t* out) {
        (void)in;
        std::memset(out, 0, sizeof(*out));
        return 0;
    }

    int preload_registers(const larpixsim_backend_register_init_t* registers, std::size_t register_count) {
        (void)registers;
        (void)register_count;
        return 0;
    }

    int set_runtime_id(uint8_t runtime_id) {
        (void)runtime_id;
        return 0;
    }

};

class CosimBackend {
  public:
    CosimBackend()
        : context_(), dut_(&context_) {
        context_.debug(0);
        dut_.runtime_id = 0u;
        dut_.preload_done = 0u;
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
        sample_rx_debug(out);
        return 0;
    }

    int preload_registers(const larpixsim_backend_register_init_t* registers, std::size_t register_count) {
        if (registers == nullptr && register_count != 0) {
            return -1;
        }
        if (!wait_for_config_reset_release()) {
            return -1;
        }
        for (std::size_t i = 0; i < register_count; ++i) {
            dut_.rootp->digital_core__DOT__config_bits[registers[i].register_addr] = registers[i].register_data;
        }
        dut_.preload_done = 1u;
        dut_.eval();
        return 0;
    }

    int set_runtime_id(uint8_t runtime_id) {
        dut_.runtime_id = runtime_id;
        reset_model();
        return 0;
    }


  private:
    void reset_model() {
        dut_.clk = 0;
        dut_.reset_n = 0;
        dut_.preload_done = 0u;
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

    bool wait_for_config_reset_release() {
        constexpr int kMaxWarmupTicks = 64;
        dut_.posi = 0xF;
        dut_.external_trigger = 0;
        dut_.hit = 0ULL;
        dut_.done = 0ULL;
        for (std::size_t i = 0; i < dout_words_.size(); ++i) {
            dut_.dout[i] = 0u;
        }
        dut_.eval();
        for (int tick = 0; tick < kMaxWarmupTicks; ++tick) {
            if (!dut_.rootp->digital_core__DOT__reset_sync_inst__DOT__all_0_config) {
                return true;
            }
            clock_tick(true);
        }
        return !dut_.rootp->digital_core__DOT__reset_sync_inst__DOT__all_0_config;
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
        out->chip_up_mask = static_cast<uint8_t>(dut_.rootp->digital_core__DOT__config_bits[124U] & 0x0fU);
        out->chip_down_mask = static_cast<uint8_t>(dut_.rootp->digital_core__DOT__config_bits[125U] & 0x0fU);

        auto channels = channel_ctrls();
        for (int i = 0; i < 5; ++i) {
            out->channel_fifo_occupancy[i] = static_cast<uint32_t>(channels[static_cast<std::size_t>(i)]->__PVT__local_fifo_counter);
        }
        for (std::size_t i = 0; i < channels.size(); ++i) {
            out->channel_fifo_occupancy_all[i] = static_cast<uint32_t>(channels[i]->__PVT__local_fifo_counter);
            out->channel_packet_generated[i] = channels[i]->__PVT__write_local_fifo_n ? 0u : 1u;
        }
    }

    void sample_rx_debug(larpixsim_backend_tick_outputs_t* out) {
        auto* root = dut_.rootp;
        out->hydra_state = static_cast<uint8_t>(root->digital_core__DOT__external_interface_inst__DOT__hydra_ctrl_inst__DOT__State);
        out->hydra_next_state = static_cast<uint8_t>(root->digital_core__DOT__external_interface_inst__DOT__hydra_ctrl_inst__DOT__Next);
        out->hydra_sel_onehot = static_cast<uint8_t>(root->digital_core__DOT__external_interface_inst__DOT__hydra_ctrl_inst__DOT__sel_onehot);
        out->hydra_uld_rx_data_uart = static_cast<uint8_t>(root->digital_core__DOT__external_interface_inst__DOT__uld_rx_data_uart);
        out->hydra_rx_data_flag = static_cast<uint8_t>(root->digital_core__DOT__external_interface_inst__DOT__rx_data_flag);
        out->hydra_comms_busy = static_cast<uint8_t>(root->digital_core__DOT__external_interface_inst__DOT__comms_busy);
        out->hydra_pkt_valid = static_cast<uint8_t>(root->digital_core__DOT__external_interface_inst__DOT__pkt_valid);
        out->hydra_fifo_write_n = static_cast<uint8_t>(root->digital_core__DOT__external_interface_inst__DOT__hydra_ctrl_inst__DOT__fifo_write_n);
        out->hydra_rx_data_word = static_cast<uint64_t>(root->digital_core__DOT__external_interface_inst__DOT__rx_data);
        out->hydra_comms_rcvd_pkt = static_cast<uint64_t>(root->digital_core__DOT__external_interface_inst__DOT__comms_ctrl_inst__DOT__rcvd_pkt);
        out->hydra_comms_read_pkt = static_cast<uint64_t>(root->digital_core__DOT__external_interface_inst__DOT__comms_ctrl_inst__DOT__read_pkt);
        out->hydra_fifo_rd_data = static_cast<uint64_t>(root->digital_core__DOT__external_interface_inst__DOT__hydra_ctrl_inst__DOT__fifo_rd_data);
        out->hydra_fifo_read_pointer = static_cast<uint16_t>(root->digital_core__DOT__external_interface_inst__DOT__hydra_ctrl_inst__DOT__hydra_fifo_inst__DOT__read_pointer);
        out->hydra_fifo_write_pointer = static_cast<uint16_t>(root->digital_core__DOT__external_interface_inst__DOT__hydra_ctrl_inst__DOT__hydra_fifo_inst__DOT__write_pointer);
        out->hydra_fifo_counter_debug = static_cast<uint16_t>(root->digital_core__DOT__external_interface_inst__DOT__hydra_ctrl_inst__DOT__fifo_counter);
        out->hydra_fifo_read_n = static_cast<uint8_t>(root->digital_core__DOT__external_interface_inst__DOT__hydra_ctrl_inst__DOT__fifo_read_n);
        out->hydra_fifo_write_n_internal = static_cast<uint8_t>(root->digital_core__DOT__external_interface_inst__DOT__hydra_ctrl_inst__DOT__fifo_write_n);
        out->hydra_fifo_mem0 = static_cast<uint64_t>(root->digital_core__DOT__external_interface_inst__DOT__hydra_ctrl_inst__DOT__hydra_fifo_inst__DOT__fifo_mem[0]);
        out->hydra_fifo_mem1 = static_cast<uint64_t>(root->digital_core__DOT__external_interface_inst__DOT__hydra_ctrl_inst__DOT__hydra_fifo_inst__DOT__fifo_mem[1]);
        out->hydra_ld_tx_data_uart = static_cast<uint8_t>(root->digital_core__DOT__external_interface_inst__DOT__ld_tx_data_uart);
        out->hydra_tx_busy = static_cast<uint8_t>(root->digital_core__DOT__external_interface_inst__DOT__tx_busy);
        out->hydra_tx_sel_msg = static_cast<uint8_t>(root->digital_core__DOT__external_interface_inst__DOT__hydra_ctrl_inst__DOT__tx_sel_msg);
        for (int i = 0; i < LARPIXSIM_EDGE_COUNT; ++i) {
            out->hydra_tx_data_uart[i] = static_cast<uint64_t>(root->digital_core__DOT__external_interface_inst__DOT__tx_data_uart[i]);
        }
        out->msg_valid = static_cast<uint8_t>(root->digital_core__DOT__external_interface_inst__DOT__msg_valid);
        out->msg_pkt_data = static_cast<uint64_t>(root->digital_core__DOT__external_interface_inst__DOT__msg_pkt_data);
        out->ready_for_msg = 1u;
        out->msg_generated_valid = static_cast<uint8_t>(root->digital_core__DOT__external_interface_inst__DOT__msg_pending);
        out->msg_fifo_write_n = static_cast<uint8_t>(!root->digital_core__DOT__external_interface_inst__DOT__msg_pending);
        out->msg_fifo_empty = static_cast<uint8_t>(!root->digital_core__DOT__external_interface_inst__DOT__msg_pending);
        out->msg_fifo_read_n = static_cast<uint8_t>(root->digital_core__DOT__external_interface_inst__DOT__msg_read_n);
        out->msg_fifo_counter_debug = static_cast<uint16_t>(root->digital_core__DOT__external_interface_inst__DOT__msg_pending ? 1u : 0u);
        out->msg_fifo_data_in = static_cast<uint64_t>(root->digital_core__DOT__external_interface_inst__DOT__msg_data_out);
        out->msg_fifo_data_out = static_cast<uint64_t>(root->digital_core__DOT__external_interface_inst__DOT__msg_data_out);
        out->msg_fifo_mem0 = 0u;
        out->msg_fifo_mem1 = 0u;

        out->rx_lane_empty[0] = 0u;
        out->rx_lane_empty[1] = 0u;
        out->rx_lane_empty[2] = 0u;
        out->rx_lane_empty[3] = 0u;
        out->hydra_uart_has_data = 0u;

        out->rx_lane_hold_valid[0] = 0u;
        out->rx_lane_hold_valid[1] = 0u;
        out->rx_lane_hold_valid[2] = 0u;
        out->rx_lane_hold_valid[3] = 0u;

        for (int i = 0; i < LARPIXSIM_EDGE_COUNT; ++i) {
            out->rx_lane_data[i] = static_cast<uint64_t>(root->digital_core__DOT__external_interface_inst__DOT__rx_data_uart[i]);
        }
        out->rx_lane_hold[0] = 0u;
        out->rx_lane_hold[1] = 0u;
        out->rx_lane_hold[2] = 0u;
        out->rx_lane_hold[3] = 0u;
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

extern "C" int larpixsim_backend_preload_registers(
    larpixsim_backend_handle_t* backend,
    const larpixsim_backend_register_init_t* registers,
    size_t register_count) {
    if (backend == nullptr || backend->ctx == nullptr || backend->vtbl == nullptr) {
        return -1;
    }
    if (backend->vtbl == &kNullBackendVtable) {
        return static_cast<NullBackend*>(backend->ctx)->preload_registers(registers, register_count);
    }
    if (backend->vtbl == &kCosimBackendVtable) {
        return static_cast<CosimBackend*>(backend->ctx)->preload_registers(registers, register_count);
    }
    return -1;
}

extern "C" int larpixsim_backend_set_runtime_id(
    larpixsim_backend_handle_t* backend,
    uint8_t runtime_id) {
    if (backend == nullptr || backend->ctx == nullptr || backend->vtbl == nullptr) {
        return -1;
    }
    if (backend->vtbl == &kNullBackendVtable) {
        return static_cast<NullBackend*>(backend->ctx)->set_runtime_id(runtime_id);
    }
    if (backend->vtbl == &kCosimBackendVtable) {
        return static_cast<CosimBackend*>(backend->ctx)->set_runtime_id(runtime_id);
    }
    return -1;
}

extern "C" void larpixsim_backend_destroy(larpixsim_backend_handle_t* backend) {
    if (backend == nullptr || backend->vtbl == nullptr || backend->vtbl->destroy == nullptr) {
        return;
    }
    backend->vtbl->destroy(backend->ctx);
    backend->ctx = nullptr;
    backend->vtbl = nullptr;
}
