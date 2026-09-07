; ===========================================================================
;  ROM slots: bank window control, inventory scan, INT F0h TeleCore services
;
;  Port 0C02h  write: bank (2..9, 0 = off)   read: [3:0] bank, [6] ROM1, [7] BIOS
;  Port 0C03h  read : bit n-2 = slot n present (n = 2..9)
; ===========================================================================

%define TC_PORT_BANK   0x0C02
%define TC_PORT_PRES   0x0C03

; select bank AL (0 or 2..9), flush CPU cache
rom_select_bank:
    push dx
    mov dx, TC_PORT_BANK
    out dx, al
    wbinvd
    pop dx
    ret

; presence bitmap -> AX (bit n = slot n, n = 0..9)
rom_presence:
    push dx
    mov dx, TC_PORT_PRES
    in al, dx
    mov ah, al                      ; slots 2..9 in bits 0..7
    xor al, al
    shl ax, 2                       ; -> bits 2..9 (AX bits 2..9)
    mov dx, TC_PORT_BANK
    push ax
    in al, dx
    mov dl, al
    pop ax
    test dl, 0x80
    jz .nb
    or al, 0x01                     ; BIOS
.nb:
    test dl, 0x40
    jz .nt
    or al, 0x02                     ; ROM1
.nt:
    pop dx
    ret

; ---- scan slots 1..9, fill directory at 0050:0000, print inventory ---------
rom_scan:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push es
    push ds
    mov ax, cs
    mov ds, ax
    call rom_presence
    mov bx, 0x0040
    mov es, bx
    mov [es:BDA_TC_ROMMASK], ax
    mov bx, ax                      ; BX = presence bitmap
    mov ax, TCDIR_SEG
    mov es, ax
    xor di, di
    mov cx, 10 * TCDIR_SIZE / 2
    xor ax, ax
    rep stosw                       ; clear directory
    mov si, msg_roms
    call puts
    mov cx, 1                       ; slot counter
.slot:
    bt bx, cx
    jnc .next
    ; map slot: 1 -> C800h, 2..9 -> E000h via bank
    mov dx, 0xC800
    cmp cx, 1
    je .mapped
    mov al, cl
    call rom_select_bank
    mov dx, 0xE000
.mapped:
    push ds
    mov ds, dx
    cmp word [0], 0xAA55
    jne .badhdr
    cmp word [2], 'TC'
    jne .badhdr
    ; fill directory entry
    mov di, cx
    shl di, 5
    mov byte [es:di], 1
    mov al, [4]
    mov [es:di+1], al
    mov al, [5]
    mov [es:di+2], al
    mov [es:di+3], cl
    mov ax, [6]
    mov [es:di+4], ax
    mov [es:di+6], dx
    push si
    push di
    push cx
    mov si, 8
    add di, 8
    mov cx, 24
.cpname:
    lodsb
    mov [es:di], al
    inc di
    loop .cpname
    pop cx
    pop di
    pop si
    pop ds
    ; print "  ROMn   : <name> (type) v<ver>"
    call .print_entry
    jmp .next
.badhdr:
    pop ds
    push si
    mov si, msg_rom_pfx
    call puts
    mov al, cl
    add al, '0'
    call putc
    mov si, msg_rom_raw
    call puts
    pop si
.next:
    inc cx
    cmp cx, 10
    jb .slot
    xor al, al
    call rom_select_bank            ; window off
    pop ds
    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

.print_entry:                       ; ES:DI = dir entry, CX = slot
    push si
    push di
    mov si, msg_rom_pfx
    call puts
    mov al, cl
    add al, '0'
    call putc
    mov si, msg_rom_sep
    call puts
    add di, 8
    push cx
    mov cx, 24
.pn:
    mov al, [es:di]
    test al, al
    jz .pn_done
    call putc
    inc di
    loop .pn
.pn_done:
    pop cx
    mov al, ' '
    call putc
    mov al, '('
    call putc
    pop di
    push di
    mov al, [es:di+1]               ; type
    call .print_type
    mov al, ')'
    call putc
    mov si, msg_rom_ver
    call puts
    mov al, [es:di+2]
    xor ah, ah
    call putdec16
    mov si, msg_crlf
    call puts
    pop di
    pop si
    ret

.print_type:
    push si
    mov si, msg_type_unknown
    cmp al, 1
    jne .t2
    mov si, msg_type_terminal
    jmp .tp
.t2: cmp al, 2
    jne .t3
    mov si, msg_type_font
    jmp .tp
.t3: cmp al, 3
    jne .t4
    mov si, msg_type_protocol
    jmp .tp
.t4: cmp al, 4
    jne .t5
    mov si, msg_type_emulation
    jmp .tp
.t5: cmp al, 5
    jne .t6
    mov si, msg_type_driver
    jmp .tp
.t6: cmp al, 0xFF
    jne .tp
    mov si, msg_type_data
.tp: call puts
    pop si
    ret

msg_roms:     db 13,10,"  ROM slots:", 13,10, 0
msg_rom_pfx:  db "    ROM", 0
msg_rom_sep:  db "  : ", 0
msg_rom_raw:  db "  : (no TeleCore header)", 13,10, 0
msg_rom_ver:  db " v", 0
msg_type_terminal:  db "terminal", 0
msg_type_font:      db "font", 0
msg_type_protocol:  db "protocol", 0
msg_type_emulation: db "emulation", 0
msg_type_driver:    db "driver", 0
msg_type_data:      db "data", 0
msg_type_unknown:   db "unknown", 0

; ---- INT F0h: TeleCore services ---------------------------------------------
;  AH=10h  select ROM bank        AL = 0 or 2..9              -> CF=0
;  AH=11h  get directory entry    AL = slot 1..9, ES:DI dest  -> copies 32 bytes, CF=1 if absent
;  AH=12h  get presence bitmap                                -> AX
;  AH=13h  get BIOS info                                       -> BX = version (0x0001), CX = 'TC'
;  AH=20h  floppy status (phase 3)                            -> AL bit0 present bit1 write-protected
;  AH=21h  floppy flush hint (phase 3)                        -> no-op
intf0_handler:
    cmp ah, 0x10
    je .bank
    cmp ah, 0x11
    je .dirent
    cmp ah, 0x12
    je .pres
    cmp ah, 0x13
    je .info
    cmp ah, 0x20
    je .fdstat
    cmp ah, 0x21
    je .ok
    jmp .fail
.bank:
    cmp al, 0
    je .bk
    cmp al, 2
    jb .fail
    cmp al, 9
    ja .fail
.bk:
    call rom_select_bank
    jmp .ok
.dirent:
    cmp al, 1
    jb .fail
    cmp al, 9
    ja .fail
    push ds
    push si
    push cx
    push di
    mov si, TCDIR_SEG
    mov ds, si
    xor ah, ah
    mov si, ax
    shl si, 5
    cmp byte [si], 1
    jne .de_absent
    mov cx, 16
    rep movsw
    pop di
    pop cx
    pop si
    pop ds
    jmp .ok
.de_absent:
    pop di
    pop cx
    pop si
    pop ds
    jmp .fail
.pres:
    call rom_presence
    jmp .ok
.info:
    mov bx, 0x0001
    mov cx, 'TC'
    jmp .ok
.fdstat:
    xor al, al                      ; phase 3
    jmp .ok
.ok:
    push bp
    mov bp, sp
    and word [bp+6], ~1
    pop bp
    iret
.fail:
    push bp
    mov bp, sp
    or word [bp+6], 1
    pop bp
    iret
