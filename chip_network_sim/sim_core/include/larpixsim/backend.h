#ifndef LARPIXSIM_BACKEND_H
#define LARPIXSIM_BACKEND_H

#include <stddef.h>
#include <stdint.h>

#define LARPIXSIM_EDGE_COUNT 4
#define LARPIXSIM_CHANNEL_COUNT 64

typedef struct {
    uint64_t seq;
    uint8_t  reset_n;
    uint8_t  rx_bit_valid[LARPIXSIM_EDGE_COUNT];
    uint8_t  rx_bit_value[LARPIXSIM_EDGE_COUNT];
    double   charge_in[LARPIXSIM_CHANNEL_COUNT];
} larpixsim_backend_tick_inputs_t;

typedef struct {
    uint8_t  tx_bit_valid[LARPIXSIM_EDGE_COUNT];
    uint8_t  tx_bit_value[LARPIXSIM_EDGE_COUNT];
    uint64_t tx_packet_count;
    uint64_t rx_packet_count;
    uint64_t local_event_count;
    uint64_t drop_count;
    uint32_t chip_fifo_occupancy;
    uint8_t  chip_up_mask;
    uint8_t  chip_down_mask;
    uint32_t channel_fifo_occupancy[5];
    uint32_t channel_fifo_occupancy_all[LARPIXSIM_CHANNEL_COUNT];
    uint8_t  channel_packet_generated[LARPIXSIM_CHANNEL_COUNT];
    uint8_t  hydra_state;
    uint8_t  hydra_next_state;
    uint8_t  hydra_uart_has_data;
    uint8_t  hydra_sel_onehot;
    uint8_t  hydra_uld_rx_data_uart;
    uint8_t  hydra_rx_data_flag;
    uint8_t  hydra_comms_busy;
    uint8_t  hydra_pkt_valid;
    uint8_t  hydra_fifo_write_n;
    uint64_t hydra_rx_data_word;
    uint64_t hydra_comms_rcvd_pkt;
    uint64_t hydra_comms_read_pkt;
    uint64_t hydra_fifo_rd_data;
    uint16_t hydra_fifo_read_pointer;
    uint16_t hydra_fifo_write_pointer;
    uint16_t hydra_fifo_counter_debug;
    uint8_t  hydra_fifo_read_n;
    uint8_t  hydra_fifo_write_n_internal;
    uint64_t hydra_fifo_mem0;
    uint64_t hydra_fifo_mem1;
    uint8_t  hydra_ld_tx_data_uart;
    uint8_t  hydra_tx_busy;
    uint8_t  hydra_tx_sel_msg;
    uint64_t hydra_tx_data_uart[LARPIXSIM_EDGE_COUNT];
    uint8_t  msg_valid;
    uint64_t msg_pkt_data;
    uint8_t  ready_for_msg;
    uint8_t  msg_generated_valid;
    uint8_t  msg_fifo_write_n;
    uint8_t  msg_fifo_empty;
    uint8_t  msg_fifo_read_n;
    uint16_t msg_fifo_counter_debug;
    uint64_t msg_fifo_data_in;
    uint64_t msg_fifo_data_out;
    uint64_t msg_fifo_mem0;
    uint64_t msg_fifo_mem1;
    uint8_t  rx_lane_empty[LARPIXSIM_EDGE_COUNT];
    uint8_t  rx_lane_hold_valid[LARPIXSIM_EDGE_COUNT];
    uint64_t rx_lane_data[LARPIXSIM_EDGE_COUNT];
    uint64_t rx_lane_hold[LARPIXSIM_EDGE_COUNT];
} larpixsim_backend_tick_outputs_t;

struct larpixsim_backend_vtbl {
    int  (*tick)(void *ctx, const larpixsim_backend_tick_inputs_t *in,
                 larpixsim_backend_tick_outputs_t *out);
    void (*destroy)(void *ctx);
};

typedef struct {
    const struct larpixsim_backend_vtbl *vtbl;
    void                                *ctx;
} larpixsim_backend_handle_t;

typedef struct {
    uint8_t register_addr;
    uint8_t register_data;
} larpixsim_backend_register_init_t;

#ifdef __cplusplus
extern "C" {
#endif

int larpixsim_backend_create_null(larpixsim_backend_handle_t *backend);
int larpixsim_backend_create_cosim(larpixsim_backend_handle_t *backend);
int larpixsim_backend_set_runtime_id(larpixsim_backend_handle_t *backend, uint8_t runtime_id);
int larpixsim_backend_preload_registers(
    larpixsim_backend_handle_t *backend,
    const larpixsim_backend_register_init_t *registers,
    size_t register_count);
void larpixsim_backend_destroy(larpixsim_backend_handle_t *backend);

#ifdef __cplusplus
}
#endif

#endif
