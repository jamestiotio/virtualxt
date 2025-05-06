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

package rifs2

import "core:strings"
import "core:log"
import "base:runtime"

import retro "vxt:frontend/libretro"
import retro_callbacks "vxt:frontend/libretro/callbacks"

host_rmdir :: proc(path: string) -> Response {
	cpath := strings.clone_to_cstring(path, context.temp_allocator)
	if retro_callbacks.vfs.remove(cpath) == 0 {
		return .OK
	}
	log.warnf("RMDIR: %s (PATH_NOT_FOUND)", path)
	return .PATH_NOT_FOUND
}

host_mkdir :: proc(path: string) -> Response {
	cpath := strings.clone_to_cstring(path, context.temp_allocator)
	if retro_callbacks.vfs.mkdir(cpath) == 0 {
		return .OK
	}
	log.warnf("MKDIR: %s (PATH_NOT_FOUND)", path)
	return .PATH_NOT_FOUND
}

host_exists :: proc(path: string) -> bool {
	cpath := strings.clone_to_cstring(path, context.temp_allocator)
	return (retro_callbacks.vfs.stat(cpath, nil) & retro.VFS_STAT_IS_VALID) != 0
}

host_is_dir :: proc(path: string) -> bool {
	cpath := strings.clone_to_cstring(path, context.temp_allocator)
	return (retro_callbacks.vfs.stat(cpath, nil) & retro.VFS_STAT_IS_DIRECTORY) != 0
}

host_rename :: proc(from, to: string) -> Response {
	cfrom := strings.clone_to_cstring(from, context.temp_allocator)
	cto := strings.clone_to_cstring(to, context.temp_allocator)
	if retro_callbacks.vfs.rename(cfrom, cto) == 0 {
		return .OK
	}
	log.warnf("RENAME: %s -> %s (PATH_NOT_FOUND)", from, to)
	return .PATH_NOT_FOUND
}

host_delete :: proc(path: string) -> Response {
	cpath := strings.clone_to_cstring(path, context.temp_allocator)
	if retro_callbacks.vfs.remove(cpath) == 0 {
		return .OK
	}
	log.warnf("DELETE: %s (PATH_NOT_FOUND)", path)
	return .PATH_NOT_FOUND
}

host_openfile :: proc(process: ^Process, path: string, attrib: u16, payload: []byte) -> Response {
	data := payload_as(payload, struct #packed {
		handle, attrib, time, date: u16,
		size: u32,
	})
	runtime.mem_zero(data, size_of(data^))

	new_handle: u16
	new_fp: ^^retro.vfs_file_handle
	
	for fp, handle in process.files {
		if fp == nil {
			new_handle = u16(handle)
			new_fp = &process.files[handle]
			break
		}
	}

	if new_fp == nil {
		new_handle = u16(append(&process.files, nil) - 1)
		new_fp = &process.files[new_handle]
	}

	cpath := strings.clone_to_cstring(path, context.temp_allocator)
	mode: u32 = retro.VFS_FILE_ACCESS_READ_WRITE | retro.VFS_FILE_ACCESS_UPDATE_EXISTING
	
	if attrib == 0 {
		mode = retro.VFS_FILE_ACCESS_READ
	} else if attrib == 1 {
		mode = retro.VFS_FILE_ACCESS_WRITE
	}
	
	fp := retro_callbacks.vfs.open(cpath, mode, 0)
	if fp == nil {
		log.warnf("OPENFILE: %s (FILE_NOT_FOUND)", path)
		return .FILE_NOT_FOUND
	}

	if file_size := retro_callbacks.vfs.size(fp); (file_size < 0) || (file_size > 0x7FFFFFFF) {
		log.warnf("OPENFILE: %s (VFS size)", path)
		retro_callbacks.vfs.close(fp)
		return .FILE_NOT_FOUND
	} else {
		data.size = u32(file_size)
	}

	// TODO: Fix time and data!
	
	data.attrib = attrib
	data.handle = new_handle
	new_fp^ = fp
	return .OK
}
