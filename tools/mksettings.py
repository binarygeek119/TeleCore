#!/usr/bin/env python3
"""Build a default TeleCore settings.nvr CMOS image.

256-byte AT-style CMOS image for the S0 Settings NVRAM slot.
Defaults the RTC to 1989-11-07 12:00:00 AM, 24-hour BCD mode.
"""
import argparse

SIZE = 256


def main():
    parser = argparse.ArgumentParser(description="Build default settings.nvr")
    parser.add_argument("-o", "--output", default="games/settings.nvr",
                        help="output .nvr file (default: games/settings.nvr)")
    args = parser.parse_args()

    d = bytearray(SIZE)

    # RTC registers (BCD) - 1989-11-07 12:00:00 AM
    d[0x00] = 0x00    # seconds
    d[0x01] = 0x00    # second alarm
    d[0x02] = 0x00    # minutes
    d[0x03] = 0x00    # minute alarm
    d[0x04] = 0x00    # hours (12 AM = 00h in 24h mode)
    d[0x05] = 0x00    # hour alarm
    d[0x06] = 0x03    # day of week (Tuesday)
    d[0x07] = 0x07    # day of month
    d[0x08] = 0x11    # month (November)
    d[0x09] = 0x89    # year (1989)
    d[0x0A] = 0x26    # reg A: 32.768 kHz, 1024 Hz rate
    d[0x0B] = 0x02    # reg B: 24-hour mode, BCD data
    d[0x0C] = 0x00    # reg C
    d[0x0D] = 0x80    # reg D: RTC power good
    d[0x0E] = 0x00    # diagnostics
    d[0x0F] = 0x00    # shutdown status
    d[0x10] = 0x40    # floppy A: 1.44 MB, B: none
    d[0x14] = 0x21    # equipment: 1 floppy, 80x25 colour
    d[0x15] = 0x80    # base memory low  (640 KB)
    d[0x16] = 0x02    # base memory high
    d[0x17] = 0x00    # extended memory low
    d[0x18] = 0x00    # extended memory high
    d[0x32] = 0x19    # century (19)

    with open(args.output, "wb") as f:
        f.write(d)

    print(f"Wrote {args.output} ({SIZE} bytes, 1989-11-07 12:00:00 AM)")


if __name__ == "__main__":
    main()
