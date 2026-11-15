/* SPDX-License-Identifier: GPL-2.0-only */
#pragma once
#include <stdint.h>

/* S-Boot scanout buffer (uniLoader board-herolte.c). */
#define HERO_FB_BASE 0xd8000000UL  /* Note FE: S-Boot scanout (scan probe 2); S7 0xe2a00000 */
#define HERO_FB_WIDTH 1440U
#define HERO_FB_HEIGHT 2560U

/* Let CPU writes reach the panel (DECON_F HW trigger), returns old value. */
uint32_t hero_fb_enable(void);
void hero_fb_text(unsigned row, const char *s);
void hero_fb_hex(unsigned row, const char *label, uint64_t value);
