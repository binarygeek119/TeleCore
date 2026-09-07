; TeleCore add-on ROM header (ROM1..ROM9)
;
;   +00  55 AA        signature
;   +02  'T' 'C'      TeleCore magic
;   +04  byte type    1=terminal 2=font 3=protocol 4=emulation 5=driver FFh=data
;   +05  byte version
;   +06  word entry   far-call offset within the ROM segment (0 = data only)
;   +08  name[24]     zero padded
;   +20  payload
;
; Usage:  TC_ROM_HEADER type, version, entry_label, "Name"

%define TCROM_TERMINAL  1
%define TCROM_FONT      2
%define TCROM_PROTOCOL  3
%define TCROM_EMULATION 4
%define TCROM_DRIVER    5
%define TCROM_DATA      0xFF

%macro TC_ROM_HEADER 4
    db 0x55, 0xAA
    db 'T', 'C'
    db %1
    db %2
    dw %3
%%name: db %4
    times 24 - ($ - %%name) db 0
%endmacro

; Directory entry written by the BIOS at 0050:0000 + slot*32 (slots 1..9)
;   +00 byte present   +01 byte type   +02 byte version   +03 byte slot
;   +04 word entry     +06 word segment (C800h or E000h)
;   +08 name[24]
%define TCDIR_SEG   0x0050
%define TCDIR_SIZE  32
