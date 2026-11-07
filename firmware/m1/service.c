/* M1 RV32I policy loop; the RTL owns progress, generation and reuse qualification. */
#include "layout.h"

#ifndef M1_AUTORUN
#define M1_AUTORUN 0
#endif
#ifndef M1_BUILD_TASKS
#define M1_BUILD_TASKS 64
#endif
#ifndef M1_PAIR_COUNT
#define M1_PAIR_COUNT 2
#endif
#ifndef M1_SEED20
#define M1_SEED20 3555
#endif
#ifndef M1_SEED21
#define M1_SEED21 8429
#endif

static volatile uint32_t *const regs = (volatile uint32_t *)0x40000000u;
static volatile uint32_t *const mb = (volatile uint32_t *)RKV_MAILBOX_BASE;
static inline uint32_t rd(uint32_t offset) { return regs[offset >> 2]; }
static inline void wr(uint32_t offset, uint32_t value) { regs[offset >> 2] = value; }
static void fence(void) { __asm__ volatile ("fence iorw,iorw" ::: "memory"); }

/* Host writes request payload then DOORBELL, and waits RESPONSE == DOORBELL.
 * RESPONSE is written last. Payload is immutable while pending. CANCEL is a
 * separate increasing serial and is sampled while waiting for completion.
 * After controlled reset the old doorbell is discarded; READY_EPOCH changes.
 */
enum {
    DOORBELL=RKV_MB_DOORBELL, ACTION=RKV_MB_ACTION, OP=RKV_MB_OP,
    SESSION0=RKV_MB_SESSION0, SESSION1=RKV_MB_SESSION1, EPOCH=RKV_MB_EPOCH,
    SEQUENCE0=RKV_MB_SEQUENCE0, SEQUENCE1=RKV_MB_SEQUENCE1, CONTEXT=RKV_MB_CONTEXT,
    GENERATION=RKV_MB_GENERATION, TOKEN0=RKV_MB_TOKEN0, TOKEN1=RKV_MB_TOKEN1,
    CANCEL_SERIAL=RKV_MB_CANCEL_SERIAL, RESPONSE=RKV_MB_RESPONSE, RESULT=RKV_MB_RESULT,
    READY_EPOCH=RKV_MB_READY_EPOCH, STATUS=RKV_MB_STATUS, CQ0=RKV_MB_CQ0,
    BUILT=RKV_MB_BUILT, DECODED=RKV_MB_DECODED, CURRENT_GENERATION=RKV_MB_CURRENT_GENERATION,
    CURRENT_SEQUENCE0=RKV_MB_CURRENT_SEQUENCE0, CURRENT_SEQUENCE1=RKV_MB_CURRENT_SEQUENCE1
};

static void stage(uint32_t session0, uint32_t session1, uint32_t epoch,
                  uint32_t seq0, uint32_t seq1, uint32_t context, uint32_t generation) {
    wr(RKV_REG_SESSION_LO, session0); wr(RKV_REG_SESSION_HI, session1);
    wr(RKV_REG_EPOCH, epoch); wr(RKV_REG_SEQUENCE_LO, seq0); wr(RKV_REG_SEQUENCE_HI, seq1);
    wr(RKV_REG_CONTEXT, context); wr(RKV_REG_GENERATION, generation);
}

static void stage_cq(void) {
    stage(rd(RKV_REG_CQ_SESSION_LO), rd(RKV_REG_CQ_SESSION_HI), rd(RKV_REG_CQ_EPOCH),
          rd(RKV_REG_CQ_SEQUENCE_LO), rd(RKV_REG_CQ_SEQUENCE_HI),
          rd(RKV_REG_CQ_CONTEXT), rd(RKV_REG_CQ_GENERATION));
}

static uint32_t wait_cq(uint32_t *cancel_serial) {
    for (;;) {
        uint32_t status = rd(RKV_REG_STATUS);
        if (status & 4u) return 0x80010000u | rd(RKV_REG_ERROR);
        if (status & 2u) return rd(RKV_REG_CQ_STATUS);
        if (cancel_serial && mb[CANCEL_SERIAL] != *cancel_serial) {
            *cancel_serial = mb[CANCEL_SERIAL];
            wr(RKV_REG_CANCEL, 1u);
        }
    }
}

static uint32_t submit(uint32_t op, uint32_t *cancel_serial) {
    wr(RKV_REG_COMMAND, op);
    uint32_t error = rd(RKV_REG_ERROR);
    return error ? 0x80020000u | error : wait_cq(cancel_serial);
}

static void consume(void) {
    stage_cq();
    wr(RKV_REG_ACK, 1u);
}

#if M1_AUTORUN
/* Fixed identity is intentionally confined to an isolated simulation firmware.
 * Board firmware is mailbox mode and receives a fresh host identity at BOOT. */
static void fail(uint32_t code) {
    *(volatile uint32_t *)0x50000000u = code;
    for (;;) { }
}
static void operation(uint32_t op, uint32_t token0, uint32_t token1) {
    stage(0x61104001u, 0x4d315349u, rd(RKV_REG_CURRENT_EPOCH),
          rd(RKV_REG_NEXT_SEQUENCE_LO), rd(RKV_REG_NEXT_SEQUENCE_HI), 7u,
          rd(RKV_REG_CURRENT_GENERATION));
    wr(RKV_REG_TOKEN0, token0); wr(RKV_REG_TOKEN1, token1);
    uint32_t status = submit(op, (uint32_t *)0);
    if (status) fail(0xbad10000u | status);
}
int main(void) {
    if (rd(RKV_REG_ID) != RKV_ABI_MAGIC || rd(RKV_REG_LAYOUT) != RKV_LAYOUT_VERSION) fail(0xbad00001u);
    operation(RKV_OP_BOOT, 0, 0); consume();
    operation(RKV_OP_REGISTER, 0, 0); consume();
    for (uint32_t i = 0; i < M1_BUILD_TASKS; i++) {
        operation(RKV_OP_BUILD, 0, 0); consume();
        if (rd(RKV_REG_BUILT) != (i+1u)*4u) fail(0xbad00002u);
    }
    if (M1_BUILD_TASKS != 64) {
        *(volatile uint32_t *)0x50000000u = 0x600d0004u;
        for (;;) { }
    }
    operation(RKV_OP_SEAL, 0, 0); consume();
    for (uint32_t pair = 0; pair < M1_PAIR_COUNT; pair++) {
        operation(RKV_OP_BIND, 0, 0); consume();
        uint32_t token0 = pair ? M1_SEED20 : 3555u;
        uint32_t token1 = pair ? M1_SEED21 : 8429u;
        for (uint32_t step = 0; step < 3; step++) {
            operation(RKV_OP_DECODE, token0, token1);
            token0 = rd(RKV_REG_CQ_TOKEN0); token1 = rd(RKV_REG_CQ_TOKEN1);
            *(volatile uint32_t *)0x50000010u = token0;
            *(volatile uint32_t *)0x50000014u = token1;
            consume();
        }
        if (pair+1u != M1_PAIR_COUNT) { operation(RKV_OP_RELEASE, 0, 0); consume(); }
    }
    *(volatile uint32_t *)0x50000000u = 0x600d4102u;
    for (;;) { }
}
#else
int main(void) {
    uint32_t seen = mb[DOORBELL];
    uint32_t cancel = mb[CANCEL_SERIAL];
    mb[READY_EPOCH] = rd(RKV_REG_CURRENT_EPOCH);
    fence();
    for (;;) {
        uint32_t request = mb[DOORBELL];
        if (request == seen) continue;
        fence();
        stage(mb[SESSION0], mb[SESSION1], mb[EPOCH], mb[SEQUENCE0], mb[SEQUENCE1], mb[CONTEXT], mb[GENERATION]);
        wr(RKV_REG_TOKEN0, mb[TOKEN0]); wr(RKV_REG_TOKEN1, mb[TOKEN1]);
        uint32_t result;
        switch (mb[ACTION]) {
        case 1: result = submit(mb[OP], &cancel); break;
        case 2: wr(RKV_REG_ACK, 1u); result = rd(RKV_REG_ERROR); break;
        case 3: wr(RKV_REG_CANCEL, 1u); result = rd(RKV_REG_ERROR); break;
        case 4: wr(RKV_REG_RESET, 1u); result = rd(RKV_REG_ERROR); break;
        default: result = 0x80030000u; break;
        }
        mb[RESULT] = result;
        mb[STATUS] = rd(RKV_REG_STATUS);
        for (uint32_t i = 0; i < 11; i++) mb[CQ0+i] = rd(RKV_REG_CQ_OP + i*4u);
        mb[BUILT] = rd(RKV_REG_BUILT); mb[DECODED] = rd(RKV_REG_DECODED);
        mb[CURRENT_GENERATION] = rd(RKV_REG_CURRENT_GENERATION);
        mb[CURRENT_SEQUENCE0] = rd(RKV_REG_NEXT_SEQUENCE_LO);
        mb[CURRENT_SEQUENCE1] = rd(RKV_REG_NEXT_SEQUENCE_HI);
        fence();
        mb[RESPONSE] = request;
        seen = request;
    }
}
#endif
