// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 L99 for Mac contributors

#include <stdint.h>
#include <stddef.h>
int32_t l99_build_music(const uint8_t *levels,uint8_t foreground,uint8_t background,uint8_t brightness,uint8_t *out,uint8_t *flags,size_t capacity);
typedef struct {
    uint16_t year;
    uint8_t month, day, hour, minute, second, weekday;
    uint8_t cpu, cpu_temperature, gpu, gpu_temperature, display_temperature;
} L99Realtime;
int32_t l99_build_realtime(const L99Realtime *value, uint8_t *out, uint8_t *flags, size_t capacity);
int32_t l99_encode_screen(const uint8_t *rgba, size_t rgba_len, const uint16_t *delays, size_t frame_count, uint8_t animation, uint8_t *out, size_t capacity);
typedef struct { uint16_t index; uint8_t kind; uint8_t modifiers; uint16_t usage; } L99Binding;
typedef struct { uint16_t index; uint8_t r; uint8_t g; uint8_t b; } L99KeyColor;
typedef struct { uint16_t slot; uint16_t usage; uint16_t delay_ms; uint8_t action; } L99MacroEvent;
int32_t l99_build_custom(const L99KeyColor *colors,size_t count,uint8_t brightness,uint8_t *out,uint8_t *flags,size_t capacity);
int32_t l99_build_macros(const L99MacroEvent *events,size_t count,size_t macro_count,uint8_t *out,uint8_t *flags,size_t capacity);
int32_t l99_build_lighting(uint8_t mode, uint8_t r, uint8_t g, uint8_t b,
    uint8_t brightness, uint8_t speed, uint8_t direction, uint8_t colorful,
    uint8_t *out, uint8_t *flags, size_t capacity);
int32_t l99_build_settings(uint8_t disable_win, uint8_t disable_alt_f4,
    uint8_t disable_alt_tab, uint8_t fn_toggle, uint8_t sleep_index,
    uint8_t response_level, uint8_t *out, uint8_t *flags, size_t capacity);
int32_t l99_build_keymap(const L99Binding *bindings, size_t count, uint8_t fn_layer,
    uint8_t *out, uint8_t *flags, size_t capacity);
