; TeleCore fallback stub - embedded in the FPGA (rtl/fallback.hex).
; Written to FFE00h..FFFFFh by rom_loader when no boot0.rom arrives.
; Puts the VGA into text mode and prints a message.

bits 16
org 0xFE00                      ; offset within segment F000h

start:
    cli
    cld
    mov ax, 0xF000
    mov ds, ax
    call vga_set_mode3

    mov ax, 0xB800
    mov es, ax
    xor di, di
    mov cx, 80*25
    mov ax, 0x0720
    rep stosw

    mov di, (80*10 + 14) * 2
    mov si, msg1
    call puts
    mov di, (80*12 + 14) * 2
    mov si, msg2
    call puts
    mov di, (80*13 + 14) * 2
    mov si, msg3
    call puts
.halt:
    hlt
    jmp .halt

puts:
    mov ah, 0x4F                ; white on red
.l: lodsb
    test al, al
    jz .d
    stosw
    jmp .l
.d: ret

msg1: db "TeleCore: no BIOS ROM found", 0
msg2: db "Copy boot0.rom to /media/fat/games/TeleCore/", 0
msg3: db "then reload the core.", 0

%include "vga_init.inc"

    times 0xFFF0 - ($ - $$ + 0xFE00) db 0xFF
reset_vector:
    jmp 0xF000:start
    times 0x10000 - ($ - $$ + 0xFE00) db 0xFF
