#ifndef LARPIXSIM_TRACE_PROTOCOL_H
#define LARPIXSIM_TRACE_PROTOCOL_H

#include <stdint.h>

#define LARPIXSIM_TRACE_MSG_EVENT 201u

#define LARPIXSIM_TRACE_EVENT_CHARGE_INJECTED 1u
#define LARPIXSIM_TRACE_EVENT_RX_PACKET 2u
#define LARPIXSIM_TRACE_EVENT_TX_PACKET 3u
#define LARPIXSIM_TRACE_EVENT_FINISH 255u

typedef struct {
    uint8_t  type;
    uint8_t  event_type;
    uint8_t  edge;
    uint8_t  reserved0;
    uint32_t runtime_id;
    uint64_t seq;
    uint64_t packet_word;
    uint32_t channel;
    uint32_t value_u32;
    double   value_f64;
} larpixsim_trace_event_msg_t;

#endif
