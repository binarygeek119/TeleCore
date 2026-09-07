; ===========================================================================
;  Keyboard: 8042 init, INT 09h (IRQ1), INT 16h, INT 74h (IRQ12 mouse)
;  Scancode set 1 (8042 translation on). Buffer in BDA 0040:001E.
; ===========================================================================

; ---- wait for 8042 input buffer empty -----------------------------------
kbc_wait_in:
    push cx
    push ax
    mov cx, 0xFFFF
.w: in al, 0x64
    test al, 2
    jz .d
    loop .w
.d: pop ax
    pop cx
    ret

; ---- wait for output buffer full; returns AL = data, CF=1 on timeout -----
kbc_wait_out:
    push cx
    mov cx, 0xFFFF
.w: in al, 0x64
    test al, 1
    jnz .ok
    loop .w
    stc
    pop cx
    ret
.ok:
    in al, 0x60
    clc
    pop cx
    ret

kbc_cmd:                            ; AL -> port 64h
    call kbc_wait_in
    out 0x64, al
    ret

kbc_data:                           ; AL -> port 60h
    call kbc_wait_in
    out 0x60, al
    ret

kbd_init:
    mov al, 0xAD                    ; disable keyboard
    call kbc_cmd
    mov al, 0xA7                    ; disable aux
    call kbc_cmd
    in al, 0x60                     ; flush
    mov al, 0xAA                    ; self test
    call kbc_cmd
    call kbc_wait_out
    mov al, 0x60                    ; write command byte
    call kbc_cmd
    mov al, 0x47                    ; xlat, sys flag, aux int, kbd int
    call kbc_data
    mov al, 0xAE                    ; enable keyboard
    call kbc_cmd
    mov al, 0xA8                    ; enable aux
    call kbc_cmd
    ; keyboard: reset + enable
    mov al, 0xFF
    call kbc_data
    call kbc_wait_out               ; ACK
    call kbc_wait_out               ; BAT AA
    mov al, 0xF4
    call kbc_data
    call kbc_wait_out
    ; mouse: defaults + enable streaming (data consumed by INT 74h)
    mov al, 0xD4
    call kbc_cmd
    mov al, 0xF6
    call kbc_data
    call kbc_wait_out
    mov al, 0xD4
    call kbc_cmd
    mov al, 0xF4
    call kbc_data
    call kbc_wait_out
    ret

; ---- INT 09h ---------------------------------------------------------------
%define KF_RSHIFT   0x01
%define KF_LSHIFT   0x02
%define KF_CTRL     0x04
%define KF_ALT      0x08
%define KF_SCROLL   0x10
%define KF_NUM      0x20
%define KF_CAPS     0x40

int09_handler:
    push ax
    push bx
    push cx
    push ds
    mov ax, 0x0040
    mov ds, ax
    in al, 0x60
    cmp al, 0xE0
    je .e0
    cmp al, 0xE1
    je .eoi
    mov cl, [BDA_KBFLAG1]           ; bit1 = previous byte was E0
    and byte [BDA_KBFLAG1], ~0x02
    mov ah, al
    and al, 0x7F
    test ah, 0x80
    jnz .break
    ; ---- make codes
    cmp al, 0x2A
    je .lshift_dn
    cmp al, 0x36
    je .rshift_dn
    cmp al, 0x1D
    je .ctrl_dn
    cmp al, 0x38
    je .alt_dn
    cmp al, 0x3A
    je .caps
    cmp al, 0x45
    je .num
    cmp al, 0x46
    je .scroll
    ; translate
    xor bh, bh
    mov bl, al
    test byte [BDA_KBFLAG0], KF_ALT
    jnz .alt_tab
    test byte [BDA_KBFLAG0], KF_CTRL
    jnz .ctrl_tab
    test byte [BDA_KBFLAG0], KF_LSHIFT | KF_RSHIFT
    jnz .shift_tab
    mov ah, [cs:kbd_tab_normal + bx]
    jmp .have
.shift_tab:
    mov ah, [cs:kbd_tab_shift + bx]
    jmp .have
.ctrl_tab:
    mov ah, [cs:kbd_tab_ctrl + bx]
    jmp .have
.alt_tab:
    mov ah, 0
.have:
    ; caps lock toggles letters when shift not held
    test byte [BDA_KBFLAG0], KF_CAPS
    jz .nocaps
    cmp ah, 'a'
    jb .capsup
    cmp ah, 'z'
    ja .nocaps
    sub ah, 0x20
    jmp .nocaps
.capsup:
    cmp ah, 'A'
    jb .nocaps
    cmp ah, 'Z'
    ja .nocaps
    add ah, 0x20
.nocaps:
    ; AX -> buffer as (scancode<<8 | ascii): scancode in AL, ascii in AH -> swap
    xchg al, ah
    test cl, 0x02                   ; E0-prefixed grey key: no ASCII (extended code)
    jz .put
    cmp ah, 0x1C                    ; keypad Enter / grey '/' keep their ASCII
    je .put
    cmp ah, 0x35
    je .put
    xor al, al
.put:
    call kbd_buffer_put
    jmp .eoi

.e0:
    or byte [BDA_KBFLAG1], 0x02
    jmp .eoi
.break:
    cmp al, 0x2A
    je .lshift_up
    cmp al, 0x36
    je .rshift_up
    cmp al, 0x1D
    je .ctrl_up
    cmp al, 0x38
    je .alt_up
    jmp .eoi
.lshift_dn: or  byte [BDA_KBFLAG0], KF_LSHIFT
            jmp .eoi
.rshift_dn: or  byte [BDA_KBFLAG0], KF_RSHIFT
            jmp .eoi
.ctrl_dn:   or  byte [BDA_KBFLAG0], KF_CTRL
            jmp .eoi
.alt_dn:    or  byte [BDA_KBFLAG0], KF_ALT
            jmp .eoi
.lshift_up: and byte [BDA_KBFLAG0], ~KF_LSHIFT
            jmp .eoi
.rshift_up: and byte [BDA_KBFLAG0], ~KF_RSHIFT
            jmp .eoi
.ctrl_up:   and byte [BDA_KBFLAG0], ~KF_CTRL
            jmp .eoi
.alt_up:    and byte [BDA_KBFLAG0], ~KF_ALT
            jmp .eoi
.caps:      xor byte [BDA_KBFLAG0], KF_CAPS
            jmp .eoi
.num:       xor byte [BDA_KBFLAG0], KF_NUM
            jmp .eoi
.scroll:    xor byte [BDA_KBFLAG0], KF_SCROLL
.eoi:
    mov al, 0x20
    out 0x20, al
    pop ds
    pop cx
    pop bx
    pop ax
    iret

; put AX into the keyboard ring buffer (DS = 0040h)
kbd_buffer_put:
    push bx
    push si
    mov bx, [BDA_KBTAIL]
    mov si, bx
    add si, 2
    cmp si, [BDA_KBBUFEND]
    jb .nowrap
    mov si, [BDA_KBBUFSTART]
.nowrap:
    cmp si, [BDA_KBHEAD]
    je .full
    mov [bx], ax
    mov [BDA_KBTAIL], si
.full:
    pop si
    pop bx
    ret

; ---- INT 16h --------------------------------------------------------------
int16_handler:
    push ds
    push bx
    mov bx, 0x0040
    mov ds, bx
    cmp ah, 0x00
    je .read
    cmp ah, 0x10
    je .read
    cmp ah, 0x01
    je .check
    cmp ah, 0x11
    je .check
    cmp ah, 0x02
    je .shift
    cmp ah, 0x12
    je .shift
    cmp ah, 0x05
    je .store
    cmp ah, 0x03
    je .done                        ; typematic: ignore
    jmp .done
.read:
    sti
.rwait:
    mov bx, [BDA_KBHEAD]
    cmp bx, [BDA_KBTAIL]
    jne .rgot
    hlt
    jmp .rwait
.rgot:
    cli
    mov ax, [bx]
    add bx, 2
    cmp bx, [BDA_KBBUFEND]
    jb .rok
    mov bx, [BDA_KBBUFSTART]
.rok:
    mov [BDA_KBHEAD], bx
    sti
    jmp .done
.check:
    mov bx, [BDA_KBHEAD]
    cmp bx, [BDA_KBTAIL]
    je .empty
    mov ax, [bx]
    pop bx
    pop ds
    ; return with ZF=0
    push bp
    mov bp, sp
    and word [bp+6], ~0x40
    pop bp
    iret
.empty:
    pop bx
    pop ds
    push bp
    mov bp, sp
    or word [bp+6], 0x40
    pop bp
    iret
.shift:
    mov al, [BDA_KBFLAG0]
    mov ah, [BDA_KBFLAG1]
    jmp .done
.store:                             ; CX = key to store
    mov ax, cx
    call kbd_buffer_put
    xor al, al
.done:
    pop bx
    pop ds
    iret

; ---- INT 74h: PS/2 mouse IRQ12 - consume byte, EOI ------------------------
int74_handler:
    push ax
    in al, 0x60
    mov al, 0x20
    out 0xA0, al
    out 0x20, al
    pop ax
    iret

; ---- scancode set 1 -> ASCII tables (index = scancode 0..7Fh) -------------
; 0 = no ASCII (extended key, returned as scancode<<8)
kbd_tab_normal:
    db 0,  27, '1','2','3','4','5','6','7','8','9','0','-','=', 8,  9
    db 'q','w','e','r','t','y','u','i','o','p','[',']', 13, 0, 'a','s'
    db 'd','f','g','h','j','k','l',';', 39, '`', 0, '\','z','x','c','v'
    db 'b','n','m',',','.','/', 0, '*', 0, ' ', 0,  0,  0,  0,  0,  0
    db 0,  0,  0,  0,  0,  0,  0, '7','8','9','-','4','5','6','+','1'
    db '2','3','0','.', 0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
    times 128-($-kbd_tab_normal) db 0
kbd_tab_shift:
    db 0,  27, '!','@','#','$','%','^','&','*','(',')','_','+', 8,  0
    db 'Q','W','E','R','T','Y','U','I','O','P','{','}', 13, 0, 'A','S'
    db 'D','F','G','H','J','K','L',':', 34, '~', 0, '|','Z','X','C','V'
    db 'B','N','M','<','>','?', 0, '*', 0, ' ', 0,  0,  0,  0,  0,  0
    db 0,  0,  0,  0,  0,  0,  0, '7','8','9','-','4','5','6','+','1'
    db '2','3','0','.', 0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
    times 128-($-kbd_tab_shift) db 0
kbd_tab_ctrl:
    db 0,  27,  0,  0,  0,  0,  0, 30,  0,  0,  0,  0, 31,  0, 127, 0
    db 17, 23,  5, 18, 20, 25, 21,  9, 15, 16, 27, 29, 10,  0,  1, 19
    db 4,   6,  7,  8, 10, 11, 12,  0,  0,  0,  0, 28, 26, 24,  3, 22
    db 2,  14, 13,  0,  0,  0,  0,  0,  0, ' ', 0,  0,  0,  0,  0,  0
    times 128-($-kbd_tab_ctrl) db 0
