; VGA 80x25 colour text mode (mode 03h) register programming.
; Shared by the BIOS and the fallback stub. Requires DS = code segment.
; Clobbers AX, BX, CX, DX, SI.

vga_set_mode3:
    mov dx, 0x3C2
    mov al, 0x67
    out dx, al

    ; sequencer: reset, then regs 1..4, then release
    mov dx, 0x3C4
    mov ax, 0x0100
    out dx, ax
    mov si, vga_seq_tab
    mov bl, 1
.seq:
    mov ah, [si]
    mov al, bl
    out dx, ax
    inc si
    inc bl
    cmp bl, 5
    jb .seq
    mov ax, 0x0300
    out dx, ax

    ; unlock CRTC
    mov dx, 0x3D4
    mov ax, 0x0E11
    out dx, ax
    mov si, vga_crtc_tab
    xor bl, bl
.crtc:
    mov ah, [si]
    mov al, bl
    out dx, ax
    inc si
    inc bl
    cmp bl, 25
    jb .crtc

    mov dx, 0x3CE
    mov si, vga_gc_tab
    xor bl, bl
.gc:
    mov ah, [si]
    mov al, bl
    out dx, ax
    inc si
    inc bl
    cmp bl, 9
    jb .gc

    mov dx, 0x3DA
    in al, dx
    mov dx, 0x3C0
    mov si, vga_ac_tab
    xor bl, bl
.ac:
    mov al, bl
    out dx, al
    mov al, [si]
    out dx, al
    inc si
    inc bl
    cmp bl, 21
    jb .ac
    mov al, 0x20
    out dx, al

    ; default 16-colour text palette via DAC (EGA-style colours)
    mov dx, 0x3C8
    xor al, al
    out dx, al
    inc dx
    mov si, vga_dac_tab
    mov cx, 16*3
.dac:
    mov al, [si]
    out dx, al
    inc si
    loop .dac
    ret

vga_seq_tab:  db 0x00, 0x03, 0x00, 0x02
vga_crtc_tab: db 0x5F,0x4F,0x50,0x82,0x55,0x81,0xBF,0x1F,0x00,0x4F,0x0D,0x0E,0x00,0x00,0x00,0x00
              db 0x9C,0x8E,0x8F,0x28,0x1F,0x96,0xB9,0xA3,0xFF
vga_gc_tab:   db 0x00,0x00,0x00,0x00,0x00,0x10,0x0E,0x00,0xFF
vga_ac_tab:   db 0x00,0x01,0x02,0x03,0x04,0x05,0x14,0x07,0x38,0x39,0x3A,0x3B,0x3C,0x3D,0x3E,0x3F
              db 0x0C,0x00,0x0F,0x08,0x00
vga_dac_tab:  db  0, 0, 0,  0, 0,42, 0,42, 0,  0,42,42, 42, 0, 0, 42, 0,42, 42,21, 0, 42,42,42
              db 21,21,21, 21,21,63, 21,63,21, 21,63,63, 63,21,21, 63,21,63, 63,63,21, 63,63,63
