#!/usr/bin/env python3
"""Build a TeleCore PhoneBook .nvr cartridge image from a JSON list."""
import argparse
import json
import os
import struct
import sys

HEADER_SIZE = 32
RECORD_SIZE = 128
MAX_IMAGE_SIZE = 65536
MAGIC = b"TCPB"


def pack_record(entry):
    name = entry.get("name", "")[:31].encode("ascii", "ignore")
    name = name + b"\0"
    name = name.ljust(32, b"\0")

    address = entry.get("address", "")[:63].encode("ascii", "ignore")
    address = address + b"\0"
    address = address.ljust(64, b"\0")

    protocol = int(entry.get("protocol", 0)) & 0xFF
    valid = 1 if entry.get("valid", True) else 0
    baud = int(entry.get("baud", 2400)) & 0xFFFF

    return name + address + bytes([protocol, valid]) + struct.pack("<H", baud) + b"\0" * 28


def build_phonebook(entries, output_path, size=MAX_IMAGE_SIZE):
    max_records = (size - HEADER_SIZE) // RECORD_SIZE
    if len(entries) > max_records:
        raise ValueError(f"too many entries ({len(entries)}), max is {max_records}")

    data = bytearray(size)
    data[0:4] = MAGIC
    data[4:6] = struct.pack("<H", 1)          # version
    data[6:8] = struct.pack("<H", len(entries))  # active count
    data[8:10] = struct.pack("<H", max_records)  # max records
    data[10:12] = struct.pack("<H", RECORD_SIZE) # record size

    offset = HEADER_SIZE
    for entry in entries:
        data[offset:offset + RECORD_SIZE] = pack_record(entry)
        offset += RECORD_SIZE

    with open(output_path, "wb") as f:
        f.write(data)

    print(f"Wrote {len(entries)} entries to {output_path} ({size} bytes)")


def main():
    parser = argparse.ArgumentParser(description="Build PhoneBook .nvr image")
    parser.add_argument("-i", "--input", default="games/phonebook.json",
                        help="input JSON file (default: games/phonebook.json)")
    parser.add_argument("-o", "--output", default="games/telecore.nvr",
                        help="output .nvr file (default: games/telecore.nvr)")
    parser.add_argument("-s", "--size", type=int, default=MAX_IMAGE_SIZE,
                        help=f"image size in bytes (default: {MAX_IMAGE_SIZE})")
    args = parser.parse_args()

    if not os.path.exists(args.input):
        entries = []
    else:
        with open(args.input, "r") as f:
            entries = json.load(f)

    if not isinstance(entries, list):
        sys.exit("input must be a JSON list of phonebook entries")

    build_phonebook(entries, args.output, args.size)


if __name__ == "__main__":
    main()
