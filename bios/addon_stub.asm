; TeleCore add-on ROM example  ->  addon.rom  (load into any slot 2-9 via OSD)
; Data-only ROM with a valid header; the BIOS inventory should list it.

bits 16
org 0

%include "rom_header.inc"

    TC_ROM_HEADER TCROM_DATA, 1, 0, "Test Add-on"

    db "TeleCore add-on ROM test payload", 0
    times 0x1000 - ($ - $$) db 0xFF     ; 4 KB
