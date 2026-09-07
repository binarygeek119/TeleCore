; ===========================================================================
;  COM1 (16550 at 3F8h): init, polled send, INT 14h
; ===========================================================================

com1_init:                          ; 9600 8N1, FIFO on, DTR/RTS high, no IRQs
    push ax
    push dx
    mov dx, 0x3F9
    xor al, al
    out dx, al                      ; IER = 0
    mov dx, 0x3FB
    mov al, 0x80
    out dx, al                      ; DLAB
    mov dx, 0x3F8
    mov al, 12                      ; 115200/12 = 9600
    out dx, al
    inc dx
    xor al, al
    out dx, al
    mov dx, 0x3FB
    mov al, 0x03                    ; 8N1
    out dx, al
    mov dx, 0x3FA
    mov al, 0xC7                    ; FIFO enable + clear, 14-byte trigger
    out dx, al
    mov dx, 0x3FC
    mov al, 0x03                    ; DTR + RTS
    out dx, al
    mov dx, 0x3F8                   ; drain
    in al, dx
    pop dx
    pop ax
    ret

com1_send:                          ; AL = byte; waits for THR empty
    push ax
    push dx
    push cx
    mov ah, al
    mov dx, 0x3FD
    mov cx, 0xFFFF
.w: in al, dx
    test al, 0x20
    jnz .go
    loop .w
.go:
    mov dx, 0x3F8
    mov al, ah
    out dx, al
    pop cx
    pop dx
    pop ax
    ret

; ---- INT 14h ---------------------------------------------------------------
; DX = port (0 = COM1 only). AH=00 init(AL=params) 01 send 02 recv 03 status
int14_handler:
    cmp dx, 0
    jne .bad
    cmp ah, 0x00
    je .init
    cmp ah, 0x01
    je .send
    cmp ah, 0x02
    je .recv
    cmp ah, 0x03
    je .status
.bad:
    mov ax, 0x8000
    iret

.init:                              ; AL = bits 7-5 baud, 4-3 parity, 2 stop, 1-0 data
    push bx
    push cx
    push dx
    mov bl, al
    mov cl, al
    shr cl, 5
    xor ch, ch
    mov bh, cl
    push bx
    mov bx, cx
    shl bx, 1
    mov cx, [cs:com_divisors + bx]
    pop bx
    mov dx, 0x3FB
    mov al, 0x80
    out dx, al
    mov dx, 0x3F8
    mov al, cl
    out dx, al
    inc dx
    mov al, ch
    out dx, al
    mov dx, 0x3FB
    mov al, bl
    and al, 0x1F
    out dx, al
    mov dx, 0x3F9
    xor al, al
    out dx, al
    mov dx, 0x3FC
    mov al, 0x03
    out dx, al
    pop dx
    pop cx
    pop bx
    jmp .status

.send:
    call com1_send
    jmp .status

.recv:
    push cx
    push dx
    mov cx, 0xFFFF
    mov dx, 0x3FD
.rw: in al, dx
    test al, 1
    jnz .rgot
    loop .rw
    pop dx
    pop cx
    mov ah, 0x80                    ; timeout
    iret
.rgot:
    and al, 0x1E
    mov ah, al                      ; line errors
    mov dx, 0x3F8
    in al, dx
    pop dx
    pop cx
    iret

.status:                            ; AH = LSR, AL = MSR
    push dx
    mov dx, 0x3FD
    in al, dx
    mov ah, al
    mov dx, 0x3FE
    in al, dx
    pop dx
    iret

com_divisors: dw 1047, 768, 384, 192, 96, 48, 24, 12   ; 110 150 300 600 1200 2400 4800 9600
