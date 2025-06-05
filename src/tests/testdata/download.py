#!/usr/bin/env python3

import gzip
import json
import os
import requests
import shutil
from cbor2 import dump

test_8088 = "https://github.com/virtualxt/8088/raw/main/v2/"
test_V20 = "https://github.com/virtualxt/v20/raw/main/v1_native/"
index_filename = "metadata.json"
test_filename = "../opcodes.odin"

test_header = """// This file is generated!
package tests

import "core:testing"
"""

test_case = """
@(test)
opcode_{sym_name} :: proc(t: ^testing.T) {{
	run_opcode_tests(t, "src/tests/testdata/{file_name}.cbor", transmute(Flags)u16({flags_mask}))
}}
"""

skip_opcodes = (
    # POP CS / Extended
    0xF,
    
    # Wait and Halt instruction
    0x9B, 0xF4,

    # Undefined
    (0xFE, 2), (0xFE, 3), (0xFE, 4), (0xFE, 5), (0xFE, 6), (0xFE, 7),

    # BUG: IDIV
    (0xF6, 7), (0xF7, 7)
)

skip_8088_opcodes = (
    0x60, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A, 0x6B, 0x6C, 0x6D, 0x6E, 0x6F,
    0xC0, 0xC1, 0xC8, 0xC9,
    (0xD0, 6), (0xD1, 6), (0xD2, 6), (0xD3, 6), 0xD6,
    0xF1,
    (0xF6, 1), (0xF7, 1),
    (0xFF, 7)
)

skip_v20_opcodes = (
)

# This data is "broken" and should not be tuple encoded.
flatten_tests = ["8F", "C6", "C7"]

def check_and_download(filename, overwrite = False):
    if overwrite or not os.path.exists(filename):
        print("Downloading: " + filename)

        url = test_url + filename
        resp = requests.get(url)
        if resp.status_code != requests.codes.ok:
            print("Could not download: " + filename)
            return False

        with open(filename, "wb") as f:
            f.write(resp.content)

    return True

def skip_opcode(name, table):
    opcode = int(name[:2], 16)

    for op in table + skip_opcodes:
        if isinstance(op, tuple):
            if op[0] == opcode and int(name[3:]) == op[1]:
                return True
        elif op == opcode:
            return True

    return False

def unpack_test(name, status):
    if status in ["prefix", "fpu"]:
        return False

    cbor_name = name + ".cbor"
    gz_name = name + ".json.gz"
    
    if os.path.exists(cbor_name):
        return True
    
    if not check_and_download(gz_name):
        return False

    print("Unpacking: {} -> {}".format(gz_name, cbor_name))
    with gzip.open(gz_name, "rb") as f_in:
        with open(cbor_name, "wb") as f_out:
            dump(json.loads(f_in.read()), f_out)

    return True

def gen_test(name, data):
    if name in test_functions:
        return
    test_functions.add(name)

    mask = 0xFFFF
    if "flags-mask" in data:
        mask = data["flags-mask"]

    with open(test_filename, "a") as f:
        f.write(test_case.format(sym_name = name.replace(".", "_"), file_name = name, flags_mask = mask))

####################### Start #######################

test_functions = set()

# Target 8088 tests
test_url = test_8088

if check_and_download(index_filename, True):
    index_file = json.loads(open(index_filename, "r").read())

    with open(test_filename, "w") as f:
        f.write(test_header)

    for opcode,data in index_file["opcodes"].items():
        if opcode in flatten_tests:
            data = data["reg"]["0"]
        
        if "reg" in data:
            for reg,rd in data["reg"].items():
                name = "{}.{}".format(opcode, reg)
                if skip_opcode(name, skip_8088_opcodes):
                    continue
                if unpack_test(name, rd["status"]):
                    gen_test(name, rd)
        else:
            if skip_opcode(opcode, skip_8088_opcodes):
                continue
            if unpack_test(opcode, data["status"]):
                gen_test(opcode, data)

# Target V20 tests
test_url = test_V20

if check_and_download(index_filename, True):
    index_file = json.loads(open(index_filename, "r").read())

    for opcode,data in index_file["opcodes"].items():      
        if opcode in flatten_tests:
            data = data["reg"]["0"]

        if "reg" in data:
            for reg,rd in data["reg"].items():
                name = "{}.{}".format(opcode, reg)
                if skip_opcode(name, skip_v20_opcodes):
                    continue
                if unpack_test(name, rd["status"]):
                    gen_test(name, rd)
        else:
            if skip_opcode(opcode, skip_v20_opcodes):
                continue
            if unpack_test(opcode, data["status"]):
                gen_test(opcode, data)
