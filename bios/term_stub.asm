; TeleCore terminal ROM placeholder  ->  boot1.rom  (slot 1, C800:0000)
; Prints a message via BIOS INT 10h and returns to the BIOS READY> prompt.

bits 16
org 0

%include "rom_header.inc"

    TC_ROM_HEADER TCROM_TERMINAL, 1, entry, "Terminal placeholder"

entry:
    push ds
    push si
    push ax
    push cs
    pop ds
    mov si, msg
.l: lodsb
    test al, al
    jz .d
    mov ah, 0x0E
    int 0x10
    jmp .l
.d: pop ax
    pop si
    pop ds
    retf

msg: db 13,10,"  [boot1.rom] Terminal program not installed - this is the placeholder ROM.",13,10
     db "  Replace games/TeleCore/boot1.rom with the real terminal.",13,10,0

    times 0x2000 - ($ - $$) db 0xFF     ; 8 KB image (slot holds up to 96 KB)
