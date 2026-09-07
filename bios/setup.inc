; ===========================================================================
;  TeleCore Setup  -  Date & Time editor (F2)
;
;  Field editor: Left/Right or Tab move between fields, Up/Down or +/-
;  change the value, digits type a number, A/P toggles AM/PM,
;  Enter = next field (saves on the last field), F10 = save & exit,
;  Esc = cancel.  Years are 4 digits so dates past Y2K work.
; ===========================================================================

cmos_write:
	push ax
	or al, 0x80
	out 0x70, al
	jmp $+2
	mov al, ah
	out 0x71, al
	pop ax
	ret

; bcd_to_dec - AL = packed BCD -> AX = binary
bcd_to_dec:
	push bx
	mov bl, al
	shr bl, 4
	and al, 0x0F
	mov bh, al
	mov al, bl
	mov bl, 10
	mul bl
	add al, bh
	adc ah, 0
	pop bx
	ret

; put_dec_n - print AX as decimal, padded with leading zeros to CL digits
put_dec_n:
	push ax
	push bx
	push cx
	push dx
	push si
	push di
	mov di, numbuf+11
	mov byte [di], 0
	mov bx, 10
.pdn_loop:
	xor dx, dx
	div bx
	add dl, '0'
	dec di
	mov [di], dl
	dec cl
	jnz .pdn_loop
	mov si, di
	call puts
	pop di
	pop si
	pop dx
	pop cx
	pop bx
	pop ax
	ret

; ---------------------------------------------------------------------------
;  Field table - 7 entries x 16 bytes:
;    +0  label position (row<<8 | col)
;    +2  value position
;    +4  label string
;    +6  variable address
;    +8  minimum
;    +10 maximum
;    +12 digits
;    +14 flags (bit0 = AM/PM field)
; ---------------------------------------------------------------------------
%define F_LPOS   0
%define F_VPOS   2
%define F_MSG    4
%define F_VAR    6
%define F_MIN    8
%define F_MAX    10
%define F_DIGITS 12
%define F_FLAGS  14
%define F_SIZE   16
%define F_COUNT  7

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

	; ---- load current RTC values into tmp_* (default 1989-11-07 12:00 AM)
	mov word [tmp_year], 1989
	mov word [tmp_month], 11
	mov word [tmp_day], 7
	mov word [tmp_hour], 12
	mov word [tmp_min], 0
	mov word [tmp_sec], 0
	mov word [tmp_ampm], 0

	call rtc_wait_update
	mov ah, 0x04
	int 0x1A				; CH=century CL=year DH=month DL=day
	mov al, ch
	call bcd_to_dec
	mov bx, 100
	mul bx					; AX = century*100
	mov bx, ax
	mov al, cl
	call bcd_to_dec
	add bx, ax				; BX = full year
	cmp bx, 1900
	jb .bad_date
	cmp bx, 2099
	ja .bad_date
	mov [tmp_year], bx
	mov al, dh
	call bcd_to_dec
	mov [tmp_month], ax
	mov al, dl
	call bcd_to_dec
	mov [tmp_day], ax
.bad_date:
	call rtc_wait_update
	mov ah, 0x02
	int 0x1A				; CH=hour CL=min DH=sec (24h)
	mov al, ch
	call bcd_to_dec			; AX = hour 0-23
	mov word [tmp_ampm], 0
	cmp ax, 12
	jb .hour_am
	mov word [tmp_ampm], 1
	sub ax, 12
.hour_am:
	test ax, ax
	jnz .hour_ok
	mov ax, 12
.hour_ok:
	mov [tmp_hour], ax
	mov al, cl
	call bcd_to_dec
	mov [tmp_min], ax
	mov al, dh
	call bcd_to_dec
	mov [tmp_sec], ax

	mov byte [cur_field], 0
	mov byte [edit_len], 0

.sm_loop:
	call vid_clear_screen

	mov dx, 0x0000
	call gotoxy
	mov si, msg_setup_title
	call puts

	; draw all fields
	xor bx, bx
.sm_draw:
	cmp bx, F_COUNT
	jae .sm_keys
	call draw_field
	inc bx
	jmp .sm_draw

.sm_keys:
	mov dx, 0x0B00
	call gotoxy
	mov si, msg_setup_hint
	call puts

	; ---- key handling
	xor ah, ah
	int 0x16

	cmp ax, 0x011B				; Esc - cancel
	je .sm_done
	cmp ax, 0x4400				; F10 - save & exit
	je .sm_save
	cmp ax, 0x4B00				; Left
	je .sm_prev
	cmp ax, 0x4D00				; Right
	je .sm_next
	cmp ax, 0x4800				; Up
	je .sm_inc
	cmp ax, 0x5000				; Down
	je .sm_dec
	cmp ax, 0x0F09				; Tab
	je .sm_next
	cmp ax, 0x0F00				; BackTab
	je .sm_prev
	cmp ax, 0x1C0D				; Enter
	je .sm_enter

	cmp al, '+'
	je .sm_inc
	cmp al, '='
	je .sm_inc
	cmp al, '-'
	je .sm_dec
	cmp al, '_'
	je .sm_dec

	; AM/PM field accepts A/P
	movzx bx, byte [cur_field]
	imul bx, bx, F_SIZE
	test word [field_table+F_FLAGS+bx], 1
	jz .sm_digits
	cmp al, 'a'
	je .sm_setam
	cmp al, 'A'
	je .sm_setam
	cmp al, 'p'
	je .sm_setpm
	cmp al, 'P'
	je .sm_setpm
	jmp .sm_loop

.sm_setam:
	mov word [tmp_ampm], 0
	jmp .sm_loop
.sm_setpm:
	mov word [tmp_ampm], 1
	jmp .sm_loop

.sm_digits:
	cmp al, '0'
	jb .sm_loop
	cmp al, '9'
	ja .sm_loop
	; append digit to edit buffer
	sub al, '0'
	movzx cx, al
	mov ax, [edit_val]
	mov bx, 10
	mul bx
	add ax, cx
	mov [edit_val], ax
	inc byte [edit_len]
	; auto-commit when all digits typed
	movzx bx, byte [cur_field]
	imul bx, bx, F_SIZE
	mov cx, [field_table+F_DIGITS+bx]
	cmp [edit_len], cl
	jb .sm_loop
	call commit_edit
	jmp .sm_next

.sm_prev:
	call commit_edit
	mov al, [cur_field]
	dec al
	jns .sp_ok
	mov al, F_COUNT-1
.sp_ok:
	mov [cur_field], al
	jmp .sm_loop

.sm_next:
	call commit_edit
	mov al, [cur_field]
	inc al
	cmp al, F_COUNT
	jb .sn_ok
	xor al, al
.sn_ok:
	mov [cur_field], al
	jmp .sm_loop

.sm_enter:
	call commit_edit
	mov al, [cur_field]
	inc al
	cmp al, F_COUNT
	jb .se_ok
	jmp .sm_save
.se_ok:
	mov [cur_field], al
	jmp .sm_loop

.sm_cancel:
	jmp .sm_done

.sm_inc:
	call commit_edit
	call field_ptr			; DI -> table entry, SI -> var
	test word [di+F_FLAGS], 1
	jnz .inc_ampm
	mov ax, [si]
	inc ax
	cmp ax, [di+F_MAX]
	jbe .inc_ok
	mov ax, [di+F_MIN]
.inc_ok:
	mov [si], ax
	jmp .sm_loop
.inc_ampm:
	xor word [tmp_ampm], 1
	jmp .sm_loop

.sm_dec:
	call commit_edit
	call field_ptr
	test word [di+F_FLAGS], 1
	jnz .dec_ampm
	mov ax, [si]
	dec ax
	cmp ax, [di+F_MIN]
	jae .dec_ok
	mov ax, [di+F_MAX]
.dec_ok:
	mov [si], ax
	jmp .sm_loop
.dec_ampm:
	xor word [tmp_ampm], 1
	jmp .sm_loop

.sm_save:
	call commit_edit
	call rtc_wait_update

	; seconds / minutes
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

	; hour: convert 12h + AM/PM to 24h
	mov ax, [tmp_hour]
	cmp word [tmp_ampm], 0
	jne .h_pm
	cmp ax, 12
	jne .h_done
	xor ax, ax				; 12 AM = 0
	jmp .h_done
.h_pm:
	cmp ax, 12
	je .h_done
	add ax, 12				; PM -> +12
.h_done:
	call dec_to_bcd
	mov ah, al
	mov al, 0x04
	call cmos_write

	; day / month
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

	; year -> century (0x32) + year (0x09)
	mov ax, [tmp_year]
	xor dx, dx
	mov bx, 100
	div bx					; AX = century, DX = year
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

	; register B: 24-hour mode (bit1=1), BCD data mode (bit2=0)
	mov al, 0x0B
	call cmos_read
	or al, 0x02
	and al, ~0x04
	mov ah, al
	mov al, 0x0B
	call cmos_write

	; confirm the save so the user sees it happened
	mov dx, 0x0C00
	call gotoxy
	mov si, msg_setup_saved
	call puts
	mov ax, 0x0040
	mov es, ax
	mov cx, [es:BDA_TICKS]
	add cx, 18				; ~1 second
.sm_wait:
	mov ax, [es:BDA_TICKS]
	cmp ax, cx
	jb .sm_wait

.sm_done:
	pop ds
	pop di
	pop si
	pop dx
	pop cx
	pop bx
	pop ax
	ret

; ---------------------------------------------------------------------------
;  field_ptr - DI -> field_table entry for cur_field, SI -> variable
; ---------------------------------------------------------------------------
field_ptr:
	movzx di, byte [cur_field]
	imul di, di, F_SIZE
	add di, field_table
	mov si, [di+F_VAR]
	ret

; ---------------------------------------------------------------------------
;  commit_edit - store the typed edit_val into the current field, clamped
; ---------------------------------------------------------------------------
commit_edit:
	push ax
	push di
	push si
	cmp byte [edit_len], 0
	je .ce_done
	call field_ptr
	mov ax, [edit_val]
	cmp ax, [di+F_MIN]
	jae .ce_min
	mov ax, [di+F_MIN]
.ce_min:
	cmp ax, [di+F_MAX]
	jbe .ce_max
	mov ax, [di+F_MAX]
.ce_max:
	mov [si], ax
	mov byte [edit_len], 0
	mov word [edit_val], 0
.ce_done:
	pop si
	pop di
	pop ax
	ret

; ---------------------------------------------------------------------------
;  draw_field - draw field BX:  '>' marker, label, value (or edit buffer)
; ---------------------------------------------------------------------------
draw_field:
	push ax
	push bx
	push cx
	push dx
	push si
	push di
	imul bx, bx, F_SIZE
	add bx, field_table			; BX -> table entry

	; marker + label
	mov dx, [bx+F_LPOS]
	call gotoxy
	mov ax, bx
	sub ax, field_table
	mov cl, 4
	shr ax, cl				; AX = field index
	cmp al, [cur_field]
	jne .df_notcur
	mov al, '>'
	call putc
	jmp .df_label
.df_notcur:
	mov al, ' '
	call putc
.df_label:
	mov si, [bx+F_MSG]
	call puts

	; value
	mov dx, [bx+F_VPOS]
	call gotoxy
	test word [bx+F_FLAGS], 1
	jnz .df_ampm
	; if editing this field show edit_val, else the stored value
	mov ax, bx
	sub ax, field_table
	mov cl, 4
	shr ax, cl
	cmp al, [cur_field]
	jne .df_stored
	cmp byte [edit_len], 0
	je .df_stored
	mov ax, [edit_val]
	jmp .df_print
.df_stored:
	mov si, [bx+F_VAR]
	mov ax, [si]
.df_print:
	mov cx, [bx+F_DIGITS]
	call put_dec_n
	jmp .df_done
.df_ampm:
	cmp word [tmp_ampm], 0
	jne .df_pm
	mov si, msg_am
	jmp .df_ampm_p
.df_pm:
	mov si, msg_pm
.df_ampm_p:
	call puts
.df_done:
	pop di
	pop si
	pop dx
	pop cx
	pop bx
	pop ax
	ret

; ---------------------------------------------------------------------------
;  Data
; ---------------------------------------------------------------------------
field_table:
	;      lpos    vpos    msg            var         min  max  dig flags
	dw 0x0600, 0x0609, msg_f_year,  tmp_year,  1900, 2099, 4, 0
	dw 0x0700, 0x0709, msg_f_month, tmp_month, 1,   12,   2, 0
	dw 0x0800, 0x0809, msg_f_day,   tmp_day,   1,   31,   2, 0
	dw 0x0628, 0x0631, msg_f_hour,  tmp_hour,  1,   12,   2, 0
	dw 0x0728, 0x0731, msg_f_min,   tmp_min,   0,   59,   2, 0
	dw 0x0828, 0x0831, msg_f_sec,   tmp_sec,   0,   59,   2, 0
	dw 0x0928, 0x0931, msg_f_ampm,  tmp_ampm,  0,   1,    2, 1

cur_field: db 0
edit_len:  db 0
edit_val:  dw 0
numbuf:    times 12 db 0

tmp_year:  dw 1989
tmp_month: dw 11
tmp_day:   dw 7
tmp_hour:  dw 12
tmp_min:   dw 0
tmp_sec:   dw 0
tmp_ampm:  dw 0

msg_setup_title: db "System Setup - Date and Time (Y2K compatible)",0
msg_setup_hint:  db "Left/Right=field  +/- or digits=change  A/P=AM/PM",13,10
                 db "Enter=next  F10=save  Esc=cancel",0
msg_f_year:  db " Year : ",0
msg_f_month: db " Month: ",0
msg_f_day:   db " Day  : ",0
msg_f_hour:  db " Hour : ",0
msg_f_min:   db " Min  : ",0
msg_f_sec:   db " Sec  : ",0
msg_f_ampm:  db " AM/PM: ",0
msg_am:      db "AM",0
msg_pm:      db "PM",0
msg_setup_saved: db "Settings saved to CMOS.",0
