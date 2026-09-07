cmos_write:
	push ax
	or al, 0x80
	out 0x70, al
	jmp $+2
	mov al, ah
	out 0x71, al
	pop ax
	ret

setup_menu:
	push ax
	push bx
	push cx
	push dx
	push si
	push di
	push ds
	mov ax, cs
	mov ds, ax
.sm_loop:
	call vid_clear_screen

	mov dx, 0x0000
	call gotoxy
	mov si, msg_setup_title
	call puts

	mov dx, 0x0200
	call gotoxy
	mov si, msg_setup_date
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

	mov dx, 0x0300
	call gotoxy
	mov si, msg_setup_time
	call puts
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

	mov dx, 0x0500
	call gotoxy
	mov si, msg_setup_prompt
	call puts

	mov ah, 0
	int 0x16
	cmp al, 0x1B
	je .sm_done
	cmp al, 'q'
	je .sm_done
	cmp al, 'Q'
	je .sm_done
	cmp al, '1'
	je .sm_date
	cmp al, '2'
	je .sm_time
	jmp .sm_loop

.sm_done:
	pop ds
	pop di
	pop si
	pop dx
	pop cx
	pop bx
	pop ax
	ret

.sm_date:
	call rtc_wait_update

	mov dx, 0x0700
	call gotoxy
	mov si, msg_setup_year
	call puts
	mov si, entry_buf
	mov cx, 4
	call gets
	jc .sm_loop
	call parse_uint16
	jc .sm_loop
	mov [tmp_year], ax

	mov dx, 0x0800
	call gotoxy
	mov si, msg_setup_month
	call puts
	mov si, entry_buf
	mov cx, 2
	call gets
	jc .sm_loop
	call parse_uint16
	jc .sm_loop
	mov [tmp_month], ax

	mov dx, 0x0900
	call gotoxy
	mov si, msg_setup_day
	call puts
	mov si, entry_buf
	mov cx, 2
	call gets
	jc .sm_loop
	call parse_uint16
	jc .sm_loop
	mov [tmp_day], ax

	call rtc_wait_update

	mov ax, [tmp_day]
	call dec_to_bcd
	mov ah, al
	mov al, 0x07
	call cmos_write

	mov ax, [tmp_month]
	call dec_to_bcd
	mov ah, al
	mov al, 0x08
	call cmos_write

	mov ax, [tmp_year]
	mov bx, 100
	xor dx, dx
	div bx
	push dx
	call dec_to_bcd
	mov ah, al
	mov al, 0x32
	call cmos_write
	pop ax
	call dec_to_bcd
	mov ah, al
	mov al, 0x09
	call cmos_write

	jmp .sm_loop

.sm_time:
	call rtc_wait_update

	mov dx, 0x0700
	call gotoxy
	mov si, msg_setup_hour
	call puts
	mov si, entry_buf
	mov cx, 2
	call gets
	jc .sm_loop
	call parse_uint16
	jc .sm_loop
	mov [tmp_hour], ax

	mov dx, 0x0800
	call gotoxy
	mov si, msg_setup_min
	call puts
	mov si, entry_buf
	mov cx, 2
	call gets
	jc .sm_loop
	call parse_uint16
	jc .sm_loop
	mov [tmp_min], ax

	mov dx, 0x0900
	call gotoxy
	mov si, msg_setup_sec
	call puts
	mov si, entry_buf
	mov cx, 2
	call gets
	jc .sm_loop
	call parse_uint16
	jc .sm_loop
	mov [tmp_sec], ax

	call rtc_wait_update

	mov ax, [tmp_sec]
	call dec_to_bcd
	mov ah, al
	mov al, 0x00
	call cmos_write

	mov ax, [tmp_min]
	call dec_to_bcd
	mov ah, al
	mov al, 0x02
	call cmos_write

	mov ax, [tmp_hour]
	call dec_to_bcd
	mov ah, al
	mov al, 0x04
	call cmos_write

	jmp .sm_loop

entry_buf:       times 16 db 0
tmp_year:        dw 0
tmp_month:       dw 0
tmp_day:         dw 0
tmp_hour:        dw 0
tmp_min:         dw 0
tmp_sec:         dw 0
msg_setup_title: db "System Setup - Date and Time (Y2K compatible)",0
msg_setup_date:  db "Date: ",0
msg_setup_time:  db "Time: ",0
msg_setup_prompt: db "1=Set Date  2=Set Time  Q/Esc=Exit",0
msg_setup_year:  db "Year (YYYY): ",0
msg_setup_month: db "Month (MM): ",0
msg_setup_day:   db "Day (DD): ",0
msg_setup_hour:  db "Hour (HH): ",0
msg_setup_min:   db "Minute (MM): ",0
msg_setup_sec:   db "Second (SS): ",0
