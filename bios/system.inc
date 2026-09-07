; ===========================================================================
;  System: IVT setup, INT 08h timer, INT 1Ah, 11h, 12h, 15h, 13h (stub),
;          hardware IRQ stubs, RTC helpers
; ===========================================================================

ivt_init:
    push es
    xor ax, ax
    mov es, ax
    xor di, di
    mov cx, 256
    mov ax, int_default
    mov dx, cs
.fill:
    stosw
    xchg ax, dx
    stosw
    xchg ax, dx
    loop .fill
    ; hardware IRQs 08h-0Fh -> EOI stub
    mov cx, 8
    mov di, 0x08*4
    mov ax, int_irq_master_stub
.m: stosw
    mov ax, cs
    stosw
    mov ax, int_irq_master_stub
    loop .m
    mov cx, 8
    mov di, 0x70*4
    mov ax, int_irq_slave_stub
.s: stosw
    mov ax, cs
    stosw
    mov ax, int_irq_slave_stub
    loop .s
    ; specific vectors
    mov word [es:0x08*4], int08_handler
    mov word [es:0x09*4], int09_handler
    mov word [es:0x0E*4], int0e_handler
    mov word [es:0x10*4], int10_handler
    mov word [es:0x11*4], int11_handler
    mov word [es:0x12*4], int12_handler
    mov word [es:0x13*4], int13_handler
    mov word [es:0x14*4], int14_handler
    mov word [es:0x15*4], int15_handler
    mov word [es:0x16*4], int16_handler
    mov word [es:0x18*4], int18_handler
    mov word [es:0x19*4], int19_handler
    mov word [es:0x1A*4], int1a_handler
    mov word [es:0x1E*4], diskette_param_table
    mov word [es:0x1E*4+2], cs
    mov word [es:0x1F*4], font8x8_placeholder
    mov word [es:0x1F*4+2], cs
    mov word [es:0x43*4], font8x16
    mov word [es:0x43*4+2], cs
    mov word [es:0x70*4], int70_handler
    mov word [es:0x74*4], int74_handler
    mov word [es:0xF0*4], intf0_handler
    ; INT 1Bh/1Ch/4Ah user hooks stay as int_default (iret)
    pop es
    ret

int_default:
    iret

int_irq_master_stub:
    push ax
    mov al, 0x20
    out 0x20, al
    pop ax
    iret

int_irq_slave_stub:
    push ax
    mov al, 0x20
    out 0xA0, al
    out 0x20, al
    pop ax
    iret

; ---- INT 08h: 18.2 Hz timer -------------------------------------------------
int08_handler:
    push ax
    push ds
    mov ax, 0x0040
    mov ds, ax
    inc word [BDA_TICKS]
    jnz .nocarry
    inc word [BDA_TICKS+2]
.nocarry:
    cmp word [BDA_TICKS+2], 0x18
    jne .noday
    cmp word [BDA_TICKS], 0x00B0
    jne .noday
    mov word [BDA_TICKS], 0
    mov word [BDA_TICKS+2], 0
    mov byte [BDA_TICKOVF], 1
.noday:
    ; floppy motor timeout
    cmp byte [BDA_FDCOUNT], 0
    je .nomotor
    dec byte [BDA_FDCOUNT]
    jnz .nomotor
    and byte [BDA_FDMOTOR], 0xF0
    mov al, 0x0C                    ; motors off, DMA/IRQ on, no reset
    push dx
    mov dx, 0x3F2
    out dx, al
    pop dx
.nomotor:
    int 0x1C
    mov al, 0x20
    out 0x20, al
    pop ds
    pop ax
    iret

; ---- INT 0Eh: floppy IRQ6 - flag completion -------------------------------
int0e_handler:
    push ax
    push ds
    mov ax, 0x0040
    mov ds, ax
    or byte [BDA_FDRECAL], 0x80
    mov al, 0x20
    out 0x20, al
    pop ds
    pop ax
    iret

; ---- INT 70h: RTC IRQ8 ------------------------------------------------------
int70_handler:
    push ax
    mov al, 0x0C
    out 0x70, al
    in al, 0x71                     ; clear flags
    mov al, 0x20
    out 0xA0, al
    out 0x20, al
    pop ax
    iret

; ---- INT 11h / 12h ---------------------------------------------------------
int11_handler:
    push ds
    mov ax, 0x0040
    mov ds, ax
    mov ax, [BDA_EQUIP]
    pop ds
    iret

int12_handler:
    push ds
    mov ax, 0x0040
    mov ds, ax
    mov ax, [BDA_MEMSIZE]
    pop ds
    iret

; ---- INT 18h / 19h: no bootable media - back to BIOS prompt ----------------
int18_handler:
int19_handler:
    mov ax, cs
    mov ds, ax
    mov si, msg_no_boot
    call puts
    jmp ready_prompt
msg_no_boot: db 13,10,"  No boot device - returning to READY prompt.",13,10,0

; ---- INT 13h: diskette services (phase 3 fills this in) --------------------
int13_handler:
    mov ah, 0x01                    ; invalid command
    push bp
    mov bp, sp
    or word [bp+6], 1               ; CF=1
    pop bp
    iret

; ---- INT 15h ---------------------------------------------------------------
int15_handler:
    cmp ah, 0x84
    je .joystick
    cmp ah, 0x86
    je .wait
    cmp ah, 0x88
    je .extmem
    cmp ah, 0xC0
    je .config
    cmp ah, 0x41
    je .unsupported
    cmp ah, 0x4F
    je .kbd_intercept
.unsupported:
    mov ah, 0x86
    jmp .fail
.kbd_intercept:                     ; return CF=1 so INT 09h keeps the key
    push bp
    mov bp, sp
    or word [bp+6], 1
    pop bp
    iret
.joystick:                          ; DX=0 buttons -> AL bits 4-7, DX=1 positions -> AX,BX,CX,DX
    call joy_read                   ; phase 2 provides; returns CF
    jc .fail
    jmp .ok
.wait:                              ; CX:DX microseconds, ~18.2 Hz granularity
    push ax
    push bx
    push cx
    push dx
    push ds
    mov ax, 0x0040
    mov ds, ax
    ; ticks = us / 54925
    mov ax, dx
    mov dx, cx
    mov bx, 54925
    div bx
    inc ax
    mov cx, ax
    mov bx, [BDA_TICKS]
.wl:
    sti
    hlt
    mov ax, [BDA_TICKS]
    cmp ax, bx
    je .wl
    mov bx, ax
    loop .wl
    pop ds
    pop dx
    pop cx
    pop bx
    pop ax
    jmp .ok
.extmem:
    mov ax, 3072                    ; 3 MB above 1 MB
    jmp .ok
.config:
    push cs
    pop es
    mov bx, config_table
    xor ah, ah
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

; ---- INT 1Ah: time -----------------------------------------------------------
int1a_handler:
    cmp ah, 0x00
    je .ticks
    cmp ah, 0x01
    je .setticks
    cmp ah, 0x02
    je .rtc_time
    cmp ah, 0x04
    je .rtc_date
    mov ah, 0x86
    push bp
    mov bp, sp
    or word [bp+6], 1
    pop bp
    iret
.ticks:
    push ds
    mov ax, 0x0040
    mov ds, ax
    mov dx, [BDA_TICKS]
    mov cx, [BDA_TICKS+2]
    mov al, [BDA_TICKOVF]
    mov byte [BDA_TICKOVF], 0
    pop ds
    iret
.setticks:
    push ds
    mov ax, 0x0040
    mov ds, ax
    mov [BDA_TICKS], dx
    mov [BDA_TICKS+2], cx
    pop ds
    iret
.rtc_time:                          ; CH hour CL min DH sec DL dst (BCD)
    call rtc_wait_update
    mov al, 0x04
    call cmos_read
    mov ch, al
    mov al, 0x02
    call cmos_read
    mov cl, al
    mov al, 0x00
    call cmos_read
    mov dh, al
    xor dl, dl
    jmp .clc
.rtc_date:                          ; CH century CL year DH month DL day (BCD)
    call rtc_wait_update
    mov al, 0x32
    call cmos_read
    mov ch, al
    mov al, 0x09
    call cmos_read
    mov cl, al
    mov al, 0x08
    call cmos_read
    mov dh, al
    mov al, 0x07
    call cmos_read
    mov dl, al
.clc:
    push bp
    mov bp, sp
    and word [bp+6], ~1
    pop bp
    iret

cmos_read:                          ; AL = reg -> AL = value
    or al, 0x80
    out 0x70, al
    jmp $+2
    in al, 0x71
    ret

rtc_wait_update:
    push ax
    push cx
    mov cx, 0x8000
.w: mov al, 0x0A
    call cmos_read
    test al, 0x80
    jz .d
    loop .w
.d: pop cx
    pop ax
    ret

; print "  Clock  : YYYY-MM-DD HH:MM:SS"
rtc_print_time:
    push ax
    push cx
    push dx
    push si
    mov si, msg_clock
    call puts
    mov ah, 0x04
    int 0x1A
    mov al, ch
    call puthex8
    mov al, cl
    call puthex8
    mov al, '-'
    call putc
    mov al, dh
    call puthex8
    mov al, '-'
    call putc
    mov al, dl
    call puthex8
    mov al, ' '
    call putc
    mov ah, 0x02
    int 0x1A
    mov al, ch
    call puthex8
    mov al, ':'
    call putc
    mov al, cl
    call puthex8
    mov al, ':'
    call putc
    mov al, dh
    call puthex8
    mov si, msg_crlf
    call puts
    pop si
    pop dx
    pop cx
    pop ax
    ret
msg_clock: db "  Clock  : ", 0
msg_crlf:  db 13,10,0

font8x8_placeholder:                ; INT 1Fh: high 128 chars 8x8 - not provided
    times 8 db 0
