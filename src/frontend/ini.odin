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

package frontend

import "base:runtime"
import "core:strings"
import "core:strconv"

@(private="file")
Iterator :: struct {
	section: string,
	source:  string,
}

@(private="file")
iterate :: proc(it: ^Iterator) -> (key, value: string, ok: bool) {
	for ln in strings.split_lines_iterator(&it.source) {
		line := strings.trim_space(ln)
		if len(line) == 0 {
			continue
		}

		if line[0] == '[' {
			end_idx := strings.index_byte(line, ']')
			if end_idx < 0 {
				end_idx = len(line)
			}
			it.section = line[1:end_idx]
			continue
		}

		if strings.has_prefix(line, ";") {
			continue
		}

		equal := strings.index(line, " =")
		quote := strings.index_byte(line, '"')
		if equal < 0 || quote > 0 && quote < equal {
			equal = strings.index_byte(line, '=')
			if equal < 0 {
				continue
			}
		} else {
			equal += 1
		}

		key = strings.trim_space(line[:equal])
		value = strings.trim_space(line[equal+1:])
		ok = true
		return
	}

	it.section = ""
	return
}

load_ini :: proc(source: string) -> (m: map[string]map[string]string, ok: bool) {
	context.allocator = context.temp_allocator

	unquote :: proc(val: string) -> (string, bool) {
		if (len(val) > 0) && (val[0] == '"' || val[0] == '\'') {
			v, allocated, ok := strconv.unquote_string(val)
			if !ok {
				s, e := strings.clone(val)
				return s, e == nil
			}
			if allocated {
				return v, true
			}
			s, e := strings.clone(v)
			return s, e == nil
		}
		s, e := strings.clone(val)
		return s, e == nil
	}

	it := Iterator{"", source}
	for key, value in iterate(&it) {
		section := it.section
		if section not_in m {
			err: runtime.Allocator_Error
			section, err = strings.clone(section)
			if err != nil {
				return
			}
			m[section] = {}
		}

		pairs := &m[section]
		new_key := unquote(key) or_return
		pairs[new_key] = unquote(value) or_return
	}

	ok = true
	return
}
