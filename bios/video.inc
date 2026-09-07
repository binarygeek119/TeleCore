; ===========================================================================
;  Video: font upload, screen primitives, INT 10h
;  Text mode 03h only (80x25x16), page 0. Cursor kept in BDA 0040:0050.
; ===========================================================================

; ---- upload 8x16 CP437 font into plane 2 --------------------------------
vga_load_font:
    push es
    mov dx, 0x3C4
    mov ax, 0x0402                  ; map mask: plane 2
    out dx, ax
    mov ax, 0x0604                  ; memory mode: ext, odd/even off, sequential
    out dx, ax
    mov dx, 0x3CE
    mov ax, 0x0005                  ; write mode 0
    out dx, ax
    mov ax, 0x0406                  ; misc: A0000h 64K, graphics
    out dx, ax
    mov ax, 0x0A000
    mov es, ax
    xor di, di
    mov si, font8x16
    mov cx, 256
.ch:
    push cx
    mov cx, 16
.row:
    lodsb
    stosb
    loop .row
    add di, 16                      ; 32 bytes per glyph slot
    pop cx
    loop .ch
    mov dx, 0x3C4
    mov ax, 0x0302                  ; map mask: planes 0,1
    out dx, ax
    mov ax, 0x0204                  ; memory mode: odd/even
    out dx, ax
    mov dx, 0x3CE
    mov ax, 0x1005                  ; odd/even read/write
    out dx, ax
    mov ax, 0x0E06                  ; misc: B8000h 32K, text
    out dx, ax
    pop es
    ret

; ---- clear screen, home cursor ------------------------------------------
vid_clear_screen:
    push es
    push ax
    push cx
    push di
    mov ax, 0xB800
    mov es, ax
    xor di, di
    mov ax, 0x0720
    mov cx, 80*25
    rep stosw
    mov ax, 0x0040
    mov es, ax
    mov word [es:BDA_VCURSOR], 0
    call vid_update_cursor
    pop di
    pop cx
    pop ax
    pop es
    ret

; ---- hardware cursor from BDA (page 0) -----------------------------------
vid_update_cursor:
    push ax
    push bx
    push dx
    push es
    mov ax, 0x0040
    mov es, ax
    mov ax, [es:BDA_VCURSOR]        ; AH=row AL=col
    mov bl, ah
    xor bh, bh
    mov ah, 0
    push ax
    mov ax, bx
    mov bx, 80
    mul bx
    pop bx
    add ax, bx                      ; AX = row*80+col
    mov bx, ax
    mov dx, 0x3D4
    mov al, 0x0E
    mov ah, bh
    out dx, ax
    mov al, 0x0F
    mov ah, bl
    out dx, ax
    pop es
    pop dx
    pop bx
    pop ax
    ret

; ---- scroll page up one line -------------------------------------------
vid_scroll_up:
    push ax
    push cx
    push si
    push di
    push ds
    push es
    mov ax, 0xB800
    mov ds, ax
    mov es, ax
    mov si, 160
    xor di, di
    mov cx, 80*24
    rep movsw
    mov ax, 0x0720
    mov cx, 80
    rep stosw
    pop es
    pop ds
    pop di
    pop si
    pop cx
    pop ax
    ret

; ---- teletype output: AL = char, attribute 07h -------------------------
; Handles CR, LF, BS, BEL, TAB; wraps and scrolls.
vid_teletype:
    push ax
    push bx
    push dx
    push di
    push es
    mov bx, 0x0040
    mov es, bx
    mov dx, [es:BDA_VCURSOR]        ; DH=row DL=col
    cmp al, 13
    je .cr
    cmp al, 10
    je .lf
    cmp al, 8
    je .bs
    cmp al, 7
    je .done
    cmp al, 9
    je .tab
    ; printable
    push ax
    mov al, dh
    mov ah, 160
    mul ah
    mov di, ax
    mov al, dl
    xor ah, ah
    shl ax, 1
    add di, ax
    mov ax, 0xB800
    mov es, ax
    pop ax
    mov ah, 0x07
    mov [es:di], ax
    mov ax, 0x0040
    mov es, ax
    inc dl
    cmp dl, 80
    jb .done
    xor dl, dl
.lf:
    inc dh
    cmp dh, 25
    jb .done
    mov dh, 24
    call vid_scroll_up
    jmp .done
.cr:
    xor dl, dl
    jmp .done
.bs:
    test dl, dl
    jz .done
    dec dl
    jmp .done
.tab:
    add dl, 8
    and dl, 0xF8
    cmp dl, 80
    jb .done
    xor dl, dl
    jmp .lf
.done:
    mov [es:BDA_VCURSOR], dx
    call vid_update_cursor
    pop es
    pop di
    pop dx
    pop bx
    pop ax
    ret

; ---- convenience: putc (AL), puts (DS:SI, 0-terminated) -----------------
putc:
    call vid_teletype
    ret

puts:
    push ax
    push si
.l: lodsb
    test al, al
    jz .d
    call vid_teletype
    jmp .l
.d: pop si
    pop ax
    ret

; print AL as two hex digits
puthex8:
    push ax
    push cx
    mov cl, al
    shr al, 4
    call .nib
    mov al, cl
    and al, 0x0F
    call .nib
    pop cx
    pop ax
    ret
.nib:
    add al, '0'
    cmp al, '9'
    jbe .p
    add al, 7
.p: call vid_teletype
    ret

puthex16:
    push ax
    mov al, ah
    call puthex8
    pop ax
    call puthex8
    ret

; print AX as unsigned decimal
putdec16:
    push ax
    push bx
    push cx
    push dx
    mov bx, 10
    xor cx, cx
.div:
    xor dx, dx
    div bx
    push dx
    inc cx
    test ax, ax
    jnz .div
.out:
    pop ax
    add al, '0'
    call vid_teletype
    loop .out
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ===========================================================================
;  INT 10h  (register frame: [bp+0]=AX 2=BX 4=CX 6=DX 8=SI 10=DI 12=BP 14=DS 16=ES)
; ===========================================================================
%define R_AX  0
%define R_BX  2
%define R_CX  4
%define R_DX  6
%define R_SI  8
%define R_DI  10
%define R_BP  12
%define R_DS  14
%define R_ES  16

int10_handler:
    push es
    push ds
    push bp
    push di
    push si
    push dx
    push cx
    push bx
    push ax
    mov bp, sp
    push cs
    pop ds
    cmp ah, 0x00
    je .set_mode
    cmp ah, 0x01
    je .set_cursor_type
    cmp ah, 0x02
    je .set_cursor
    cmp ah, 0x03
    je .get_cursor
    cmp ah, 0x06
    je .scroll
    cmp ah, 0x07
    je .scroll
    cmp ah, 0x08
    je .read_char
    cmp ah, 0x09
    je .write_char_attr
    cmp ah, 0x0A
    je .write_char
    cmp ah, 0x0E
    je .teletype
    cmp ah, 0x0F
    je .get_mode
    cmp ah, 0x11
    je .font_info
    cmp ah, 0x12
    je .alt_select
    cmp ah, 0x13
    je .write_string
    cmp ah, 0x1A
    je .display_combo
    jmp .done

.set_mode:
    call vga_set_mode3
    call vga_load_font
    call vid_clear_screen
    mov ax, 0x0040
    mov es, ax
    mov byte [es:BDA_VMODE], 3
    jmp .done

.set_cursor_type:                   ; CH=start CL=end
    mov ax, 0x0040
    mov es, ax
    mov [es:BDA_VCURTYPE], cx
    mov dx, 0x3D4
    mov al, 0x0A
    mov ah, ch
    out dx, ax
    mov al, 0x0B
    mov ah, cl
    out dx, ax
    jmp .done

.set_cursor:                        ; DH=row DL=col
    mov ax, 0x0040
    mov es, ax
    mov [es:BDA_VCURSOR], dx
    call vid_update_cursor
    jmp .done

.get_cursor:
    mov ax, 0x0040
    mov es, ax
    mov ax, [es:BDA_VCURSOR]
    mov [bp+R_DX], ax
    mov ax, [es:BDA_VCURTYPE]
    mov [bp+R_CX], ax
    jmp .done

.scroll:                            ; AH=06/07 AL=lines BH=attr CH/CL top-left DH/DL bottom-right
    call vid_scroll_window
    jmp .done

.read_char:                         ; -> AL char, AH attr
    mov ax, 0x0040
    mov es, ax
    mov dx, [es:BDA_VCURSOR]
    call vid_cursor_offset
    mov ax, 0xB800
    mov es, ax
    mov ax, [es:di]
    mov [bp+R_AX], ax
    jmp .done

.write_char_attr:                   ; AL char BL attr CX count
    mov ah, bl
    jmp .wc_common
.write_char:                        ; AL char, keep attribute
    mov ah, 0
.wc_common:
    push ax
    mov ax, 0x0040
    mov es, ax
    mov dx, [es:BDA_VCURSOR]
    call vid_cursor_offset
    mov ax, 0xB800
    mov es, ax
    pop ax
    test cx, cx
    jz .done
    cmp byte [bp+R_AX+1], 0x09
    je .wca
.wc:
    mov [es:di], al
    add di, 2
    loop .wc
    jmp .done
.wca:
    mov [es:di], ax
    add di, 2
    loop .wca
    jmp .done

.teletype:
    call vid_teletype
    jmp .done

.get_mode:                          ; -> AH cols AL mode BH page
    mov ax, 0x0040
    mov es, ax
    mov al, [es:BDA_VMODE]
    mov ah, 80
    mov [bp+R_AX], ax
    mov byte [bp+R_BX+1], 0
    jmp .done

.font_info:
    cmp al, 0x30
    jne .done
    ; ES:BP -> font, CX = bytes/char, DL = rows-1
    mov [bp+R_ES], cs
    mov word [bp+R_BP], font8x16
    mov word [bp+R_CX], 16
    mov byte [bp+R_DX], 24
    jmp .done

.alt_select:
    cmp bl, 0x10
    jne .done
    mov word [bp+R_BX], 0x0003      ; colour, 256K
    mov word [bp+R_CX], 0x0009
    jmp .done

.write_string:                      ; AL mode(bit0 update cursor, bit1 attrs in string) BL attr CX len DH/DL pos ES:BP string
    mov si, [bp+R_BP]
    mov ax, 0x0040
    mov es, ax
    push word [es:BDA_VCURSOR]
    mov [es:BDA_VCURSOR], dx
    mov ds, [bp+R_ES]
    mov bl, [bp+R_AX]               ; mode
    test cx, cx
    jz .ws_end
.ws:
    lodsb
    test bl, 2
    jz .ws_put
    inc si                          ; skip attribute byte (attr not applied in this BIOS)
.ws_put:
    call vid_teletype
    loop .ws
.ws_end:
    pop ax
    test bl, 1
    jnz .done
    mov [es:BDA_VCURSOR], ax        ; restore cursor if mode bit0 clear
    call vid_update_cursor
    jmp .done

.display_combo:
    mov byte [bp+R_AX], 0x1A
    mov word [bp+R_BX], 0x0008      ; VGA colour
    jmp .done

.done:
    pop ax
    pop bx
    pop cx
    pop dx
    pop si
    pop di
    pop bp
    pop ds
    pop es
    iret

; DI = byte offset of DH/DL cursor position
vid_cursor_offset:
    push ax
    mov al, dh
    mov ah, 160
    mul ah
    mov di, ax
    mov al, dl
    xor ah, ah
    shl ax, 1
    add di, ax
    pop ax
    ret

; ---- window scroll --------------------------------------------------------
; AH=06 up / 07 down, AL=lines (0=clear window), BH=attr,
; CH,CL = top,left   DH,DL = bottom,right.   Preserves all registers.
vid_scroll_window:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push ds
    push es
    push bp
    mov bp, sp
    sub sp, 8
    ; locals: [bp-2]=lines [bp-4]=width(chars) [bp-6]=dir(0 up/1 down) [bp-8]=attr
    mov bl, al
    xor bh, bh
    mov [bp-2], bx                  ; lines
    mov [bp-8], ax                  ; ah=06/07 (dir), al
    mov al, dl
    sub al, cl
    inc al
    xor ah, ah
    mov [bp-4], ax                  ; width
    mov al, dh
    sub al, ch
    inc al                          ; rows in window
    xor ah, ah
    mov bx, [bp-2]
    test bx, bx
    jz .clear_all
    cmp bx, ax
    jae .clear_all
    sub ax, bx                      ; rows to move
    mov si, ax
    push word 0xB800
    pop ds
    push word 0xB800
    pop es
    cmp byte [bp-7], 0x07
    je .down
    ; ---- up: dest=top, src=top+lines
    mov al, ch
    call .rowoff
    mov di, ax
    mov al, ch
    add al, bl
    call .rowoff
    mov bx, ax                      ; src
.uploop:
    push si
    push di
    mov si, bx
    mov cx, [bp-4]
    rep movsw
    pop di
    pop si
    add di, 160
    add bx, 160
    dec si
    jnz .uploop
    ; blank rows dh-lines+1 .. dh
    mov al, dh
    sub al, [bp-2]
    inc al
    mov ch, al
    jmp .clear_rows
.down:                              ; dest=bottom, src=bottom-lines
    mov al, dh
    call .rowoff
    mov di, ax
    mov al, dh
    sub al, bl
    call .rowoff
    mov bx, ax
.dnloop:
    push si
    push di
    mov si, bx
    mov cx, [bp-4]
    rep movsw
    pop di
    pop si
    sub di, 160
    sub bx, 160
    dec si
    jnz .dnloop
    ; blank rows ch .. ch+lines-1
    mov al, ch
    add al, [bp-2]
    dec al
    mov dh, al
    jmp .clear_rows
.clear_all:
.clear_rows:                        ; rows ch..dh, cols cl..cl+width-1
    push word 0xB800
    pop es
    mov ah, [bp+15]                 ; attribute = saved BH
    mov al, ' '
.crow:
    push ax
    mov al, ch
    call .rowoff
    mov di, ax
    pop ax
    mov cx, [bp-4]
    rep stosw
    inc ch
    cmp ch, dh
    jbe .crow
    mov sp, bp
    pop bp
    pop es
    pop ds
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret
.rowoff:                            ; AL=row -> AX = row*160 + CL*2
    push bx
    mov ah, 160
    mul ah
    mov bl, cl
    xor bh, bh
    shl bx, 1
    add ax, bx
    pop bx
    ret
