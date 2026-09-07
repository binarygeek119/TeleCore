%define PB_DATA    0x0C10
%define PB_ADDR0   0x0C11
%define PB_ADDR1   0x0C12
%define PB_CTRL    0x0C13
%define PB_MAX0    0x0C17
%define PB_MAX1    0x0C18
%define PB_FLAG_PRESENT  1
%define PB_FLAG_READONLY 2
%define PB_FLAG_BUSY     4
%define PB_CMD_SAVE      1
%define PB_CMD_RESET     2
%define PB_HEADER_SIZE   32
%define PB_RECORD_SIZE   128
%define PB_NAME_LEN      32
%define PB_ADDR_LEN      64
%define PB_NAME_OFF      0
%define PB_ADDR_OFF      32
%define PB_PROTOCOL_OFF  96
%define PB_FLAGS_OFF     97
%define PB_BAUD_OFF      98
%define PB_VALID_FLAG    1

pb_seek:
	push dx
	mov dx, PB_ADDR0
	out dx, al
	mov al, ah
	inc dx
	out dx, al
	pop dx
	ret

pb_read_byte:
	push dx
	mov dx, PB_DATA
	in al, dx
	pop dx
	ret

pb_write_byte:
	push dx
	mov dx, PB_DATA
	out dx, al
	pop dx
	ret

pb_read_word:
	push dx
	mov dx, PB_DATA
	in al, dx
	mov ah, al
	in al, dx
	xchg ah, al
	pop dx
	ret

pb_write_word:
	push dx
	push ax
	mov dx, PB_DATA
	out dx, al
	mov al, ah
	out dx, al
	pop ax
	pop dx
	ret

pb_status:
	push dx
	mov dx, PB_CTRL
	in al, dx
	pop dx
	ret

pb_present:
	call pb_status
	and al, PB_FLAG_PRESENT
	ret

pb_readonly:
	call pb_status
	and al, PB_FLAG_READONLY
	ret

pb_busy:
	call pb_status
	and al, PB_FLAG_BUSY
	ret

pb_save:
	push ax
	push dx
	mov dx, PB_CTRL
	mov al, PB_CMD_SAVE
	out dx, al
.pb_wait:
	in al, dx
	test al, PB_FLAG_BUSY
	jnz .pb_wait
	pop dx
	pop ax
	ret

pb_max:
	push dx
	mov dx, PB_MAX0
	in al, dx
	mov ah, al
	inc dx
	in al, dx
	xchg ah, al
	pop dx
	ret

pb_write_count:
	push ax
	push dx
	mov ax, 6
	call pb_seek
	mov ax, [bp-2]
	call pb_write_word
	pop dx
	pop ax
	ret

pb_load_count:
	push bx
	push cx
	push dx
	mov bx, PB_HEADER_SIZE
	xor cx, cx
.pc_loop:
	cmp bx, [bp-12]
	jae .pc_done
	mov ax, bx
	add ax, PB_FLAGS_OFF
	call pb_seek
	call pb_read_byte
	test al, PB_VALID_FLAG
	jz .pc_next
	inc cx
.pc_next:
	add bx, PB_RECORD_SIZE
	jmp .pc_loop
.pc_done:
	mov ax, cx
	pop dx
	pop cx
	pop bx
	ret

find_first_free:
	push bx
	push dx
	mov dx, PB_HEADER_SIZE
.ff_loop:
	cmp dx, [bp-12]
	jae .ff_notfound
	mov ax, dx
	add ax, PB_FLAGS_OFF
	call pb_seek
	call pb_read_byte
	test al, PB_VALID_FLAG
	jz .ff_found
	add dx, PB_RECORD_SIZE
	jmp .ff_loop
.ff_found:
	mov ax, dx
	call pb_seek
	clc
	jmp .ff_ret
.ff_notfound:
	xor ax, ax
	stc
.ff_ret:
	pop dx
	pop bx
	ret

find_record:
	push bx
	push cx
	push dx
	push di
	mov cx, ax
	xor bx, bx
	mov dx, PB_HEADER_SIZE
.fr_loop:
	cmp dx, [bp-12]
	jae .fr_notfound
	mov ax, dx
	add ax, PB_FLAGS_OFF
	call pb_seek
	call pb_read_byte
	test al, PB_VALID_FLAG
	jz .fr_next
	cmp bx, cx
	je .fr_found
	inc bx
.fr_next:
	add dx, PB_RECORD_SIZE
	jmp .fr_loop
.fr_found:
	mov ax, dx
	call pb_seek
	clc
	jmp .fr_ret
.fr_notfound:
	xor ax, ax
	clc
.fr_ret:
	pop di
	pop dx
	pop cx
	pop bx
	ret

pb_format:
	push ax
	push bx
	push cx
	push dx
	xor ax, ax
	call pb_seek
	mov al, 'T'
	call pb_write_byte
	mov al, 'C'
	call pb_write_byte
	mov al, 'P'
	call pb_write_byte
	mov al, 'B'
	call pb_write_byte
	mov al, 1
	call pb_write_byte
	xor al, al
	call pb_write_byte
	xor al, al
	call pb_write_byte
	xor al, al
	call pb_write_byte
	call pb_max
	call pb_write_word
	mov al, PB_RECORD_SIZE & 0xFF
	call pb_write_byte
	mov al, PB_RECORD_SIZE >> 8
	call pb_write_byte
	mov cx, 22
	xor al, al
.fmt_pad:
	call pb_write_byte
	loop .fmt_pad
	mov bx, PB_HEADER_SIZE
.fmt_mark:
	mov ax, bx
	add ax, PB_FLAGS_OFF
	call pb_seek
	xor al, al
	call pb_write_byte
	add bx, PB_RECORD_SIZE
	cmp bx, [bp-12]
	jb .fmt_mark
	pop dx
	pop cx
	pop bx
	pop ax
	ret

read_field:
	push ax
	push cx
	push dx
	push si
	push di
	call pb_seek
	mov dx, PB_DATA
.rf_loop:
	in al, dx
	mov [si], al
	inc si
	test al, al
	jz .rf_done
	loop .rf_loop
.rf_done:
	pop di
	pop si
	pop dx
	pop cx
	pop ax
	ret

write_field:
	push ax
	push cx
	push dx
	push si
	push di
	call pb_seek
	mov dx, PB_DATA
.wf_loop:
	lodsb
	out dx, al
	test al, al
	jz .wf_fill
	loop .wf_loop
	jmp .wf_done
.wf_fill:
	dec cx
	jz .wf_done
	xor al, al
.wf_fill_loop:
	out dx, al
	loop .wf_fill_loop
.wf_done:
	pop di
	pop si
	pop dx
	pop cx
	pop ax
	ret

send_string:
	push ax
	push si
.ss_loop:
	lodsb
	test al, al
	jz .ss_done
	call com1_send
	jmp .ss_loop
.ss_done:
	pop si
	pop ax
	ret

gotoxy:
	push ax
	push bx
	mov ah, 2
	xor bh, bh
	int 0x10
	pop bx
	pop ax
	ret

gets:
	push ax
	push bx
	push cx
	push dx
	push si
	xor dx, dx
.g_loop:
	mov ah, 0
	int 0x16
	cmp al, 0x1B
	je .g_esc
	cmp al, 13
	je .g_done
	cmp al, 8
	je .g_bs
	cmp al, 32
	jb .g_loop
	cmp dx, cx
	jae .g_loop
	mov [si], al
	inc si
	inc dx
	call putc
	jmp .g_loop
.g_bs:
	test dx, dx
	jz .g_loop
	dec si
	dec dx
	mov byte [si], 0
	mov al, 8
	call putc
	mov al, ' '
	call putc
	mov al, 8
	call putc
	jmp .g_loop
.g_done:
	mov byte [si], 0
	clc
	jmp .g_ret
.g_esc:
	stc
.g_ret:
	pop si
	pop dx
	pop cx
	pop bx
	pop ax
	ret

parse_uint16:
	push bx
	push cx
	push si
	xor ax, ax
	xor cx, cx
.pu_loop:
	lodsb
	test al, al
	jz .pu_done
	sub al, '0'
	cmp al, 9
	ja .pu_bad
	mov bl, al
	mov dx, 10
	mul dx
	jc .pu_bad
	add al, bl
	adc ah, 0
	jc .pu_bad
	inc cx
	jmp .pu_loop
.pu_done:
	test cx, cx
	jz .pu_empty
	clc
	jmp .pu_ret
.pu_bad:
.pu_empty:
	xor ax, ax
	stc
.pu_ret:
	pop si
	pop cx
	pop bx
	ret

dec_to_bcd:
	push bx
	xor ah, ah
	mov bl, 10
	div bl
	mov bl, ah
	shl al, 4
	or al, bl
	pop bx
	ret

clear_to_eol:
	push ax
	push cx
	push dx
	push es
	mov ax, 0x0040
	mov es, ax
	mov dx, [es:BDA_VCURSOR]
	mov al, 80
	sub al, dl
	jz .cte_done
	mov cl, al
	xor ch, ch
	mov al, ' '
.cte_loop:
	call putc
	loop .cte_loop
.cte_done:
	pop es
	pop dx
	pop cx
	pop ax
	ret

phonebook_menu:
	push bp
	mov bp, sp
	sub sp, 14
	push ax
	push bx
	push cx
	push dx
	push si
	push di
	push ds
	mov ax, cs
	mov ds, ax

	call vid_clear_screen

	call pb_present
	test al, al
	jz .nocart

	call pb_max
	mov [bp-4], ax
	test ax, ax
	jz .small

	xor ax, ax
	mov [bp-12], ax
	add word [bp-12], PB_HEADER_SIZE
	mov ax, [bp-4]
	mov cx, PB_RECORD_SIZE
	mul cx
	add [bp-12], ax

	xor ax, ax
	call pb_seek
	call pb_read_byte
	cmp al, 'T'
	jne .badhdr
	call pb_read_byte
	cmp al, 'C'
	jne .badhdr
	call pb_read_byte
	cmp al, 'P'
	jne .badhdr
	call pb_read_byte
	cmp al, 'B'
	jne .badhdr
	call pb_read_byte
	cmp al, 1
	jne .badhdr

	call pb_load_count
	mov [bp-2], ax
	mov word [bp-6], 0
	mov word [bp-8], 0

	call pb_readonly
	and al, PB_FLAG_READONLY
	shr al, 1
	mov [bp-10], al

	jmp .main_loop

.badhdr:
	mov dx, 0x1000
	call gotoxy
	mov si, msg_pb_format_confirm
	call puts
	mov ah, 0
	int 0x16
	cmp al, 'y'
	je .doformat
	cmp al, 'Y'
	je .doformat
	jmp .exit

.doformat:
	call pb_format
	mov word [bp-2], 0
	mov word [bp-6], 0
	mov word [bp-8], 0
	mov byte [bp-10], 0
	jmp .main_loop

.small:
	mov dx, 0x0C00
	call gotoxy
	mov si, msg_pb_small
	call puts
	jmp .waitexit

.nocart:
	mov dx, 0x0C00
	call gotoxy
	mov si, msg_pb_nocart
	call puts

.waitexit:
	mov ah, 0
	int 0x16
	jmp .exit

.main_loop:
	call vid_clear_screen

	mov dx, 0x0000
	call gotoxy
	mov si, msg_pb_title
	call puts

	mov dx, 0x0100
	call gotoxy
	mov si, msg_pb_status
	call puts
	mov ax, [bp-2]
	call putdec16
	mov al, '/'
	call putc
	mov ax, [bp-4]
	call putdec16
	cmp byte [bp-10], 0
	je .rw
	mov si, msg_pb_ro
	call puts
	jmp .afterstatus
.rw:
	mov si, msg_pb_rw
	call puts
.afterstatus:

	xor di, di
.draw_loop:
	mov ax, di
	add ax, 2
	mov dh, al
	mov dl, 0
	call gotoxy
	mov ax, [bp-6]
	add ax, di
	cmp ax, [bp-2]
	jb .draw_valid
	mov si, blank_line
	call puts
	jmp .draw_next
.draw_valid:
	call find_record
	test ax, ax
	jz .draw_blank
	mov bx, ax
	cmp di, [bp-8]
	jne .noarrow
	mov al, '>'
	call putc
	jmp .afarrow
.noarrow:
	mov al, ' '
	call putc
.afarrow:
	mov ax, [bp-6]
	add ax, di
	inc ax
	call putdec16
	mov al, '.'
	call putc
	mov al, ' '
	call putc
	mov ax, bx
	add ax, PB_NAME_OFF
	mov si, tmp_name
	mov cx, PB_NAME_LEN
	call read_field
	mov si, tmp_name
	call puts
	call clear_to_eol
.draw_next:
	inc di
	cmp di, 21
	jb .draw_loop
.draw_blank:

	mov dx, 0x1800
	call gotoxy
	mov si, msg_pb_footer
	call puts

	mov ah, 0
	int 0x16

	cmp ax, 0x4800
	je .up
	cmp ax, 0x5000
	je .down
	cmp al, 0x1B
	je .exit
	cmp al, 'q'
	je .exit
	cmp al, 'Q'
	je .exit
	cmp al, 13
	je .dial
	cmp al, 'n'
	je .new
	cmp al, 'N'
	je .new
	cmp al, 'e'
	je .edit
	cmp al, 'E'
	je .edit
	cmp al, 'd'
	je .delete
	cmp al, 'D'
	je .delete
	cmp al, 's'
	je .save
	cmp al, 'S'
	je .save
	jmp .main_loop

.up:
	cmp word [bp-8], 0
	je .main_loop
	dec word [bp-8]
	mov ax, [bp-8]
	cmp ax, [bp-6]
	jae .main_loop
	mov [bp-6], ax
	jmp .main_loop

.down:
	cmp word [bp-2], 0
	je .main_loop
	mov ax, [bp-2]
	dec ax
	cmp ax, [bp-8]
	jbe .main_loop
	inc word [bp-8]
	mov ax, [bp-8]
	sub ax, [bp-6]
	cmp ax, 21
	jb .main_loop
	inc word [bp-6]
	jmp .main_loop

.new:
	cmp byte [bp-10], 0
	jne .readonly
	mov ax, [bp-2]
	cmp ax, [bp-4]
	jae .full
	call find_first_free
	test ax, ax
	jz .full
	push ax
	call vid_clear_screen
	mov dx, 0x0300
	call gotoxy
	mov si, msg_pb_name
	call puts
	mov si, entry_name
	mov cx, PB_NAME_LEN - 1
	call gets
	jc .new_cancel
	mov dx, 0x0500
	call gotoxy
	mov si, msg_pb_addr
	call puts
	mov si, entry_address
	mov cx, PB_ADDR_LEN - 1
	call gets
	jc .new_cancel
	mov dx, 0x0700
	call gotoxy
	mov si, msg_pb_baud
	call puts
	mov si, entry_baud
	mov cx, 6
	call gets
	jc .new_cancel
	mov si, entry_baud
	call parse_uint16
	jnc .baudok
	mov ax, 9600
.baudok:
	mov [tmp_baud], ax
	pop bx
	mov ax, bx
	add ax, PB_NAME_OFF
	mov si, entry_name
	mov cx, PB_NAME_LEN
	call write_field
	mov ax, bx
	add ax, PB_ADDR_OFF
	mov si, entry_address
	mov cx, PB_ADDR_LEN
	call write_field
	mov ax, bx
	add ax, PB_PROTOCOL_OFF
	call pb_seek
	xor al, al
	call pb_write_byte
	mov al, PB_VALID_FLAG
	call pb_write_byte
	mov ax, [tmp_baud]
	call pb_write_word
	inc word [bp-2]
	call pb_write_count
	jmp .main_loop

.new_cancel:
	pop ax
	jmp .main_loop

.full:
	mov dx, 0x1600
	call gotoxy
	mov si, msg_pb_full
	call puts
	mov ah, 0
	int 0x16
	jmp .main_loop

.readonly:
	mov dx, 0x1600
	call gotoxy
	mov si, msg_pb_readonly
	call puts
	mov ah, 0
	int 0x16
	jmp .main_loop

.edit:
	cmp byte [bp-10], 0
	jne .readonly
	cmp word [bp-2], 0
	je .main_loop
	mov ax, [bp-8]
	call find_record
	test ax, ax
	jz .main_loop
	mov bx, ax
	push bx
	mov ax, bx
	add ax, PB_NAME_OFF
	mov si, entry_name
	mov cx, PB_NAME_LEN
	call read_field
	mov ax, bx
	add ax, PB_ADDR_OFF
	mov si, entry_address
	mov cx, PB_ADDR_LEN
	call read_field
	call vid_clear_screen
	mov dx, 0x0300
	call gotoxy
	mov si, msg_pb_name
	call puts
	mov si, entry_name
	mov cx, PB_NAME_LEN - 1
	call gets
	jc .edit_cancel
	mov dx, 0x0500
	call gotoxy
	mov si, msg_pb_addr
	call puts
	mov si, entry_address
	mov cx, PB_ADDR_LEN - 1
	call gets
	jc .edit_cancel
	pop bx
	mov ax, bx
	add ax, PB_NAME_OFF
	mov si, entry_name
	mov cx, PB_NAME_LEN
	call write_field
	mov ax, bx
	add ax, PB_ADDR_OFF
	mov si, entry_address
	mov cx, PB_ADDR_LEN
	call write_field
	jmp .main_loop

.edit_cancel:
	pop bx
	jmp .main_loop

.delete:
	cmp byte [bp-10], 0
	jne .readonly
	cmp word [bp-2], 0
	je .main_loop
	call vid_clear_screen
	mov dx, 0x0C00
	call gotoxy
	mov si, msg_pb_delete_confirm
	call puts
	mov ah, 0
	int 0x16
	cmp al, 'y'
	je .dodel
	cmp al, 'Y'
	je .dodel
	jmp .main_loop

.dodel:
	mov ax, [bp-8]
	call find_record
	test ax, ax
	jz .main_loop
	mov bx, ax
	add ax, PB_FLAGS_OFF
	call pb_seek
	xor al, al
	call pb_write_byte
	dec word [bp-2]
	call pb_write_count
	mov ax, [bp-8]
	cmp ax, [bp-2]
	jb .delok
	dec word [bp-8]
.delok:
	mov ax, [bp-8]
	cmp ax, [bp-6]
	jae .main_loop
	mov [bp-6], ax
	jmp .main_loop

.save:
	cmp byte [bp-10], 0
	jne .readonly
	call pb_save
	jmp .main_loop

.dial:
	cmp word [bp-2], 0
	je .main_loop
	mov ax, [bp-8]
	call find_record
	test ax, ax
	jz .main_loop
	mov bx, ax
	mov ax, bx
	add ax, PB_NAME_OFF
	mov si, tmp_name
	mov cx, PB_NAME_LEN
	call read_field
	mov ax, bx
	add ax, PB_ADDR_OFF
	mov si, tmp_addr
	mov cx, PB_ADDR_LEN
	call read_field
	mov si, msg_atdt
	call send_string
	mov si, tmp_addr
	call send_string
	mov al, 13
	call com1_send
	call vid_clear_screen
	mov dx, 0x0C00
	call gotoxy
	mov si, msg_pb_dialing
	call puts
	mov si, tmp_name
	call puts
	mov si, msg_pb_at
	call puts
	mov si, tmp_addr
	call puts
	mov ah, 0
	int 0x16
	jmp .exit

.exit:
	pop ds
	pop di
	pop si
	pop dx
	pop cx
	pop bx
	pop ax
	mov sp, bp
	pop bp
	ret

msg_pb_title:    db "PhoneBook Cartridge",0
msg_pb_status:   db "Entries: ",0
msg_pb_ro:       db "  [READ-ONLY]",0
msg_pb_rw:       db "  [READ/WRITE]",0
msg_pb_footer:   db "Up/Down=Move  Enter=Dial  N=New  E=Edit  D=Delete  S=Save  Q=Exit",0
msg_pb_nocart:   db "No PhoneBook cartridge mounted. Press any key.",0
msg_pb_small:    db "Cartridge too small. Press any key.",0
msg_pb_name:     db "Name: ",0
msg_pb_addr:     db "Address: ",0
msg_pb_baud:     db "Baud (9600): ",0
msg_pb_format_confirm: db "Invalid header. Format cartridge? (Y/N)",0
msg_pb_delete_confirm: db "Delete selected entry? (Y/N)",0
msg_pb_dialing:  db "Dialing ",0
msg_pb_at:       db " at ",0
msg_pb_full:     db "PhoneBook full. Press any key.",0
msg_pb_readonly: db "Cartridge is read-only. Press any key.",0
msg_atdt:        db "ATDT",0
blank_line:      times 80 db ' ',0
entry_name:      times 32 db 0
entry_address:   times 64 db 0
entry_baud:      times 8 db 0
tmp_name:        times 32 db 0
tmp_addr:        times 64 db 0
tmp_baud:        dw 0
