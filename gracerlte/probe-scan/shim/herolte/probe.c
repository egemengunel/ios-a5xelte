/* SPDX-License-Identifier: GPL-2.0-only
 * Note FE (gracerlte) scan probe, from ios-a5xelte shim/herolte/probe.c.
 * The S7 probe draws at 0xe2a00000; on the Note FE only the Samsung logo stayed
 * on screen, so the panel scans out from elsewhere (S-Boot's command line names
 * s3cfb.bootloaderfb=0xd8000000). This probe draws the same text at several
 * candidate addresses: 0xd8000000, 0xe2a00000, then whatever the four IDMA
 * (VPP G0..G3, 0x13951000 + n*0x1000) VG_BASE_ADDR_Y(0) registers (+0x74, as
 * Samsung's vpp_reg_set_in_buf_addr; patch 0322) hold. Each register is read
 * one at a time and its value shown before the next, so a bus stall would show
 * how far it got. Then it counts down and returns so probe.S requests TWRP.
 */
#include <stdint.h>
#include "../fdt.h"
#include "fbtext.h"

#define RECOVERY_DELAY_S 60U
#define MAX_BASES 6U
#define FB_BYTES (HERO_FB_WIDTH * HERO_FB_HEIGHT * 4UL)
#define BANK1_LO 0x84000000UL      /* above this probe's own image and payload */
#define BANK1_HI 0xfdc00000UL      /* Note FE DTB /memory@80000000 end */

static uint64_t bases[MAX_BASES];
static unsigned nbases;

static uint64_t counter(void)
{
    uint64_t value;
    __asm__ volatile("isb; mrs %0, cntpct_el0" : "=r" (value));
    return value;
}

static void add_base(uint64_t b)
{
    if (b < BANK1_LO || b + FB_BYTES > BANK1_HI || (b & 0xfffUL)) return;
    for (unsigned i = 0; i < nbases; ++i)
        if (bases[i] == b) return;
    if (nbases < MAX_BASES) bases[nbases++] = b;
}

static void say(unsigned row, const char *s)
{
    for (unsigned i = 0; i < nbases; ++i) {
        hero_fb_set_base(bases[i]);
        hero_fb_text(row, s);
    }
}

static void say_hex(unsigned row, const char *label, uint64_t v)
{
    for (unsigned i = 0; i < nbases; ++i) {
        hero_fb_set_base(bases[i]);
        hero_fb_hex(row, label, v);
    }
}

void hero_probe_main(uintptr_t fdt, uint64_t el, uint64_t sctlr, uint64_t image)
{
    uint64_t midr, freq;
    uint32_t trig_before = hero_fb_enable();
    (void)fdt; (void)sctlr;

    __asm__ volatile("mrs %0, midr_el1" : "=r" (midr));
    __asm__ volatile("mrs %0, cntfrq_el0" : "=r" (freq));

    nbases = 0;
    add_base(0xd8000000UL);
    add_base(0xe2a00000UL);

    unsigned row = 0;
    say(row++, "NOTE FE SCAN PROBE 2");
    say_hex(row++, "EL", el >> 2);
    say_hex(row++, "IMAGE", image);
    say_hex(row++, "MIDR", midr);
    say_hex(row++, "TRIG", trig_before);

    /* VPP G0..G3: read one, show it on every candidate, then use it as one. */
    static const char *const labels_unused = 0; (void)labels_unused;
    for (unsigned n = 0; n < 4; ++n) {
        char label[] = "VPP0 ADDR";
        label[3] = (char)('0' + n);
        say(row, "READING VPP");
        uint64_t reg = 0x13951000UL + n * 0x1000UL + 0x74UL;
        uint32_t v = *(volatile uint32_t *)(uintptr_t)reg;
        say_hex(row++, label, v);
        add_base(v);
    }
    /* Redraw everything on any base that was added from a register. */
    row = 0;
    say(row++, "NOTE FE SCAN PROBE 2");
    say_hex(row++, "EL", el >> 2);
    say_hex(row++, "IMAGE", image);
    say_hex(row++, "MIDR", midr);
    say_hex(row++, "TRIG", trig_before);
    for (unsigned n = 0; n < 4; ++n) {
        char label[] = "VPP0 ADDR";
        label[3] = (char)('0' + n);
        say_hex(row++, label, *(volatile uint32_t *)(uintptr_t)(0x13951000UL + n * 0x1000UL + 0x74UL));
    }
    /* Which base is this copy of the text in: each base prints its own address. */
    for (unsigned i = 0; i < nbases; ++i) {
        hero_fb_set_base(bases[i]);
        hero_fb_hex(row, "THIS IS FB", bases[i]);
    }
    row++;

    if (!freq)
        freq = 26000000U;
    uint64_t t0 = counter();
    unsigned shown = ~0U;
    for (;;) {
        uint64_t elapsed = (counter() - t0) / freq;
        if (elapsed >= RECOVERY_DELAY_S)
            return;
        unsigned left = RECOVERY_DELAY_S - (unsigned)elapsed;
        if (left != shown) {
            char line[] = "TWRP EN 00 S";
            line[8] = (char)('0' + left / 10);
            line[9] = (char)('0' + left % 10);
            say(row + 1, line);
            shown = left;
        }
    }
}
