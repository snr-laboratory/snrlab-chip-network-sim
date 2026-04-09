#ifndef LARPIXSIM_BACKEND_H
#define LARPIXSIM_BACKEND_H

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
    uint32_t channel_fifo_occupancy[5];
    uint32_t channel_fifo_occupancy_all[LARPIXSIM_CHANNEL_COUNT];
    uint8_t  channel_packet_generated[LARPIXSIM_CHANNEL_COUNT];
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

#ifdef __cplusplus
extern "C" {
#endif

int larpixsim_backend_create_null(larpixsim_backend_handle_t *backend);
int larpixsim_backend_create_cosim(larpixsim_backend_handle_t *backend);
void larpixsim_backend_destroy(larpixsim_backend_handle_t *backend);

#ifdef __cplusplus
}
#endif

#endif
