#+private

// Copyright (c) 2019-2025 Andreas T Jonsson <mail@andreasjonsson.se>
//
// This software is provided 'as-is', without any express or implied
// warranty. In no event will the authors be held liable for any damages
// arising from the use of this software.
//
// Permission is granted to anyone to use this software for any purpose,
// including commercial applications, and to alter it and redistribute it
// freely, subject to the following restrictions:
//
// 1. The origin of this software must not be misrepresented; you must not
//    claim that you wrote the original software. If you use this software
//    in a product, an acknowledgment in the product documentation would be
//    appreciated but is not required.
//
// 2. Altered source versions must be plainly marked as such, and must not be
//    misrepresented as being the original software.
//
// 3. This notice may not be removed or altered from any source
//    distribution.

package chipset

import "core:c"
import "core:log"

import retro "vxt:frontend/libretro"
import retro_callbacks "vxt:frontend/libretro/callbacks"
import "vxt:machine/peripheral"
import rt "vxt:xruntime"

PPI_TONE_VOLUME :: 8192

PPI :: struct {
	data_port, port_61, xt_switches: byte,
	kb_reset, spk_enabled:           bool,
	spk_sample_index:                i64,
	audio_freq:                      uint,
	pit:                             ^PIT,
}

ppi_install :: proc(ppi: ^PPI) -> bool {
	using peripheral
	register_io_address_range(ppi, 0x60, 0x63)

	p, _, ok := peripheral.get_peripheral_from_class(peripheral.Peripheral_Class.PIT)
	assert(ok)
	ppi.pit = peripheral.cast_peripheral(p, PIT)

	kbcb := retro.keyboard_callback{ppi_keyboard_callback}
	retro_callbacks.environment(retro.ENVIRONMENT_SET_KEYBOARD_CALLBACK, &kbcb)

	acb := retro.audio_callback{ppi_audio_callback, nil}
	retro_callbacks.environment(retro.ENVIRONMENT_SET_AUDIO_CALLBACK, &acb)

	assert(ppi.pit != nil)
	return true
}

ppi_config :: proc(ppi: ^PPI, name, key: string, value: any) -> (ok := true) {
	if name != "chipset" {
		return
	}

	switch key {
	case "set_audio_frequency":
		ppi.audio_freq = value.(uint)
	case "set_switches":
		ppi.xt_switches = value.(byte)
	case "get_switches":
		value.(^byte)^ = ppi.xt_switches
	case:
		ok = false
	}
	return
}

ppi_io_in :: proc(using ppi: ^PPI, port: u16) -> byte {
	switch port {
	case 0x60:
		data := data_port
		if kb_reset {
			kb_reset = false
			data_port = 0
		}
		return data
	case 0x61:
		port_61 ~= 0x10 // Toggle refresh bit.
		return port_61
	case 0x62:
		return bool(port_61 & 8) ? (xt_switches >> 4) : (xt_switches & 0xF)
	case:
		return 0
	}
}

ppi_io_out :: proc(using ppi: ^PPI, port: u16, data_out: byte) {
	if port == 0x61 {
		if enable := (data_out & 3) == 3; enable != spk_enabled {
			spk_enabled = enable
			spk_sample_index = 0
		}

		do_reset := !bool(port_61 & 0xC0) && bool(data_out & 0xC0)
		kb_reset ||= do_reset

		if kb_reset && (data_port != 0xAA) {
			data_port = 0xAA
			peripheral.peripheral_interface.interrupt(1)
			log.info("Keyboard reset!")
		}

		port_61 = data_out
	}
}

ppi_generate_sample :: proc(ppi: ^PPI) -> i16 {
	assert(ppi.pit != nil)

	tone_hz := pit_get_frequency(ppi.pit, 2)
	if !ppi.spk_enabled || (tone_hz <= 0) {
		return 0
	}

	square_wave_period := i64(f64(ppi.audio_freq) / tone_hz)
	half_square_wave_period := square_wave_period / 2

	if half_square_wave_period == 0 {
		return 0
	}

	ppi.spk_sample_index += 1
	return bool((ppi.spk_sample_index / half_square_wave_period) % 2) ? PPI_TONE_VOLUME : -PPI_TONE_VOLUME
}

ppi_push_event :: proc(ppi: ^PPI, scan: byte) {
	assert(ppi.pit != nil)

	if !ppi.kb_reset {
		ppi.data_port = scan
		peripheral.peripheral_interface.interrupt(1)
	}
}

ppi_audio_callback :: proc "c" () {
	context = rt.default_context
	p, _, ok := peripheral.get_peripheral_from_class(peripheral.Peripheral_Class.PPI)
	assert(ok)

	sample := ppi_generate_sample(peripheral.cast_peripheral(p, PPI))
	retro_callbacks.audio(sample, sample)
}

ppi_keyboard_callback :: proc "c" (down: c.bool, keycode: retro.key, character: c.uint32_t, key_modifiers: c.uint16_t) {
	context = rt.default_context
	using retro

	xt_key: byte
	#partial switch keycode {
	case .K_ESCAPE:
		xt_key = 0x01
	case .K_1:
		xt_key = 0x02
	case .K_2:
		xt_key = 0x03
	case .K_3:
		xt_key = 0x04
	case .K_4:
		xt_key = 0x05
	case .K_5:
		xt_key = 0x06
	case .K_6:
		xt_key = 0x07
	case .K_7:
		xt_key = 0x08
	case .K_8:
		xt_key = 0x09
	case .K_9:
		xt_key = 0x0A
	case .K_0:
		xt_key = 0x0B
	case .K_MINUS:
		xt_key = 0x0C
	case .K_EQUALS:
		xt_key = 0xD
	case .K_BACKSPACE:
		xt_key = 0x0E
	case .K_TAB:
		xt_key = 0x0F
	case .K_q:
		xt_key = 0x10
	case .K_w:
		xt_key = 0x11
	case .K_e:
		xt_key = 0x12
	case .K_r:
		xt_key = 0x13
	case .K_t:
		xt_key = 0x14
	case .K_y:
		xt_key = 0x15
	case .K_u:
		xt_key = 0x16
	case .K_i:
		xt_key = 0x17
	case .K_o:
		xt_key = 0x18
	case .K_p:
		xt_key = 0x19
	case .K_LEFTBRACKET:
		xt_key = 0x1A
	case .K_RIGHTBRACKET:
		xt_key = 0x1B
	case .K_RETURN:
		xt_key = 0x1C
	case .K_LCTRL, .K_RCTRL:
		xt_key = 0x1D
	case .K_a:
		xt_key = 0x1E
	case .K_s:
		xt_key = 0x1F
	case .K_d:
		xt_key = 0x20
	case .K_f:
		xt_key = 0x21
	case .K_g:
		xt_key = 0x22
	case .K_h:
		xt_key = 0x23
	case .K_j:
		xt_key = 0x24
	case .K_k:
		xt_key = 0x25
	case .K_l:
		xt_key = 0x26
	case .K_SEMICOLON:
		xt_key = 0x27
	case .K_QUOTE:
		xt_key = 0x28
	case .K_BACKQUOTE:
		xt_key = 0x29
	case .K_LSHIFT:
		xt_key = 0x2A
	case .K_BACKSLASH:
		xt_key = 0x2B // INT2
	case .K_z:
		xt_key = 0x2C
	case .K_x:
		xt_key = 0x2D
	case .K_c:
		xt_key = 0x2E
	case .K_v:
		xt_key = 0x2F
	case .K_b:
		xt_key = 0x30
	case .K_n:
		xt_key = 0x31
	case .K_m:
		xt_key = 0x32
	case .K_COMMA:
		xt_key = 0x33
	case .K_PERIOD:
		xt_key = 0x34
	case .K_SLASH:
		xt_key = 0x35
	case .K_RSHIFT:
		xt_key = 0x36
	case .K_PRINT:
		xt_key = 0x37
	case .K_LALT, .K_RALT:
		xt_key = 0x38
	case .K_SPACE:
		xt_key = 0x39
	case .K_CAPSLOCK:
		xt_key = 0x3A
	case .K_F1:
		xt_key = 0x3B
	case .K_F2:
		xt_key = 0x3C
	case .K_F3:
		xt_key = 0x3D
	case .K_F4:
		xt_key = 0x3E
	case .K_F5:
		xt_key = 0x3F
	case .K_F6:
		xt_key = 0x40
	case .K_F7:
		xt_key = 0x41
	case .K_F8:
		xt_key = 0x42
	case .K_F9:
		xt_key = 0x43
	case .K_F10:
		xt_key = 0x44
	case .K_NUMLOCK:
		xt_key = 0x45
	case .K_SCROLLOCK:
		xt_key = 0x46
	case .K_KP7, .K_HOME:
		xt_key = 0x47
	case .K_KP8, .K_UP:
		xt_key = 0x48
	case .K_KP9, .K_PAGEUP:
		xt_key = 0x49
	case .K_KP_MINUS:
		xt_key = 0x4A
	case .K_KP4, .K_LEFT:
		xt_key = 0x4B
	case .K_KP5:
		xt_key = 0x4C
	case .K_KP6, .K_RIGHT:
		xt_key = 0x4D
	case .K_KP_PLUS:
		xt_key = 0x4E
	case .K_KP1, .K_END:
		xt_key = 0x4F
	case .K_KP2, .K_DOWN:
		xt_key = 0x50
	case .K_KP3, .K_PAGEDOWN:
		xt_key = 0x51
	case .K_KP0, .K_INSERT:
		xt_key = 0x52
	case .K_KP_PERIOD, .K_DELETE:
		xt_key = 0x53
	}

	if xt_key != 0 {
		if !down {
			xt_key |= 0x80
		}

		p, _, ok := peripheral.get_peripheral_from_class(peripheral.Peripheral_Class.PPI)
		assert(ok)
		ppi_push_event(peripheral.cast_peripheral(p, PPI), xt_key)
	}
}
