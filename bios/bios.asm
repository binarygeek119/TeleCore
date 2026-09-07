; ===========================================================================
;  TeleCore BIOS  -  boot0.rom  (64 KB at F000:0000)
;
;  Machine: Intel 80486DX, Tseng ET4000AX VGA, Sound Blaster 1.0 + game port,
;           1.44 MB floppy A:, PS/2 keyboard + mouse, COM1 (modem), RTC.
;
;  Real-mode BIOS: installs interrupt vectors, initialises hardware, scans
;  the add-on ROM slots, then either runs the terminal ROM (slot 1) or drops
;  to the built-in READY> prompt.
; ===========================================================================

bits 16
org 0

%include "rom_header.inc"

; ---------------------------------------------------------------- BIOS data area (segment 0040h)
%define BDA_COM1        0x00    ; word  COM1 base
%define BDA_EQUIP       0x10    ; word  equipment list
%define BDA_MEMSIZE     0x13    ; word  KB
%define BDA_KBFLAG0     0x17    ; byte  shift flags
%define BDA_KBFLAG1     0x18    ; byte
%define BDA_KBHEAD      0x1A    ; word
%define BDA_KBTAIL      0x1C    ; word
%define BDA_KBBUF       0x1E    ; 16 words 1Eh..3Dh
%define BDA_FDRECAL     0x3E
%define BDA_FDMOTOR     0x3F
%define BDA_FDCOUNT     0x40
%define BDA_FDSTATUS    0x41
%define BDA_FDCSTAT     0x42    ; 7 bytes
%define BDA_VMODE       0x49
%define BDA_VCOLS       0x4A    ; word
%define BDA_VPAGESZ     0x4C    ; word
%define BDA_VPAGEOFF    0x4E    ; word
%define BDA_VCURSOR     0x50    ; 8 words
%define BDA_VCURTYPE    0x60    ; word
%define BDA_VPAGE       0x62
%define BDA_VCRTC       0x63    ; word
%define BDA_TICKS       0x6C    ; dword
%define BDA_TICKOVF     0x70
%define BDA_KBBUFSTART  0x80    ; word
%define BDA_KBBUFEND    0x82    ; word
%define BDA_VROWS       0x84    ; byte rows-1
%define BDA_VCHARH      0x85    ; word char height
%define BDA_KBFLAG3     0x96
%define BDA_FDCHANGE    0x8B    ; media change flag (TeleCore use)
%define BDA_FDIRQ       0x3E    ; bit 7 = IRQ6 seen
; TeleCore private area inside BDA (0xB0..0xEF unused by DOS-era software)
%define BDA_TC_SBPORT   0xB0    ; word  220h or 0
%define BDA_TC_SBIRQ    0xB2    ; byte
%define BDA_TC_SBDMA    0xB3    ; byte
%define BDA_TC_ROMMASK  0xB4    ; word  present bitmap (bit n = slot n)
%define BDA_TC_JOY      0xB6    ; byte  joystick present flags

; ===========================================================================
;  Entry
; ===========================================================================
bios_entry:
    cli
    cld
    mov ax, cs
    mov ds, ax
    xor ax, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00                  ; stack 0000:7C00 downwards

    ; ---- 8259 PICs: master 08h-0Fh, slave 70h-77h
    mov al, 0x11
    out 0x20, al
    out 0xA0, al
    mov al, 0x08
    out 0x21, al
    mov al, 0x70
    out 0xA1, al
    mov al, 0x04
    out 0x21, al
    mov al, 0x02
    out 0xA1, al
    mov al, 0x01
    out 0x21, al
    out 0xA1, al
    mov al, 0xFF                    ; mask everything until handlers are in place
    out 0x21, al
    out 0xA1, al

    ; ---- interrupt vector table
    call ivt_init

    ; ---- BIOS data area
    mov cx, 0x80                    ; clear 0400h-04FFh
    xor di, di
    mov ax, 0x0040
    mov es, ax
    xor ax, ax
    rep stosw
    mov word [es:BDA_COM1], 0x3F8
    mov word [es:BDA_EQUIP], 0000_0010_0010_0101b ; 1 serial, 1 floppy, colour 80x25, no FPU
    mov word [es:BDA_MEMSIZE], 640
    mov word [es:BDA_KBHEAD], BDA_KBBUF
    mov word [es:BDA_KBTAIL], BDA_KBBUF
    mov word [es:BDA_KBBUFSTART], BDA_KBBUF
    mov word [es:BDA_KBBUFEND], BDA_KBBUF + 32
    mov word [es:BDA_VCRTC], 0x3D4
    mov byte [es:BDA_VMODE], 3
    mov word [es:BDA_VCOLS], 80
    mov word [es:BDA_VPAGESZ], 4096
    mov byte [es:BDA_VROWS], 24
    mov word [es:BDA_VCHARH], 16
    mov word [es:BDA_VCURTYPE], 0x0E0F
    mov byte [es:BDA_FDMOTOR], 0
    mov word [es:BDA_TC_SBPORT], 0

    ; ---- 8254 PIT: channel 0 mode 3, divisor 0 (18.2 Hz)
    mov al, 0x36
    out 0x43, al
    xor al, al
    out 0x40, al
    out 0x40, al

    ; ---- VGA: mode 3, upload font, clear
    call vga_set_mode3
    call vga_load_font
    call vid_clear_screen

    ; ---- keyboard controller
    call kbd_init

    ; ---- COM1 9600 8N1, polled
    call com1_init

    ; ---- unmask IRQ0,1,2(cascade),4 and IRQ8,12
    mov al, 0xE8
    out 0x21, al
    mov al, 0xEE
    out 0xA1, al
    sti

    ; ---- banner
    mov si, msg_boot_logo
    call puts

    ; ---- hardware summary
    mov si, msg_cpu
    call puts
    mov si, msg_video
    call puts
    call sound_detect               ; phase 2 (prints its own line)
    mov si, msg_floppy
    call puts
    mov si, msg_com
    call puts
    call rtc_print_time

    ; ---- ROM inventory
    call rom_scan

    ; ---- boot menu (F2 setup, F3 PhoneBook, timeout -> ROM1)
    call boot_menu

    ; ---- run the terminal ROM if present
    mov ax, TCDIR_SEG
    mov es, ax
    mov bx, 1 * TCDIR_SIZE
    cmp byte [es:bx], 1
    jne .no_term
    mov ax, [es:bx+4]
    test ax, ax
    jz .no_term
    mov si, msg_starting_term
    call puts
    push word [es:bx+6]
    push ax
    mov ax, cs
    mov ds, ax
    mov bp, sp
    call far [ss:bp]                ; far call into ROM1
    add sp, 4
    mov ax, cs
    mov ds, ax
    mov si, msg_term_returned
    call puts
.no_term:
    jmp ready_prompt

; ===========================================================================
;  READY> prompt  -  minimal terminal: keys -> COM1, COM1 -> screen
; ===========================================================================
ready_prompt:
    mov ax, cs
    mov ds, ax
    mov si, msg_ready_help
    call puts
.prompt:
    mov si, msg_prompt
    call puts
.loop:
    ; COM1 -> screen
    mov dx, 0x3FD
    in al, dx
    test al, 1
    jz .kbd
    mov dx, 0x3F8
    in al, dx
    call putc
.kbd:
    mov ah, 0x01
    int 0x16
    jz .loop
    xor ah, ah
    int 0x16
    cmp ax, 0x3C00                  ; F2 = setup (phase 4)
    je .f2
    cmp ax, 0x3D00                  ; F3 = dial (phase 4)
    je .f3
    cmp ax, 0x011B                  ; ESC
    je .esc
    cmp al, 0
    je .loop
    push ax
    call putc
    pop ax
    call com1_send
    cmp al, 13
    jne .loop
    mov al, 10
    call putc
    jmp .loop
.f2:
    call setup_menu
    jmp .prompt
.f3:
    call phonebook_menu
    jmp .prompt
.esc:
    mov si, msg_reboot
    call puts
    mov al, 0xFE                    ; 8042 pulse reset line
    out 0x64, al
    jmp 0xF000:0xFFF0

; ===========================================================================
;  Boot menu
; ===========================================================================
boot_menu:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push ds
    mov ax, cs
    mov ds, ax
    mov si, msg_boot_options
    call puts
    mov ax, 0x0040
    mov es, ax
    mov bx, [es:BDA_TICKS]
    add bx, 91
.bm_loop:
    mov ah, 1
    int 0x16
    jz .bm_nokey
    xor ah, ah
    int 0x16
    cmp ax, 0x3C00
    je .bm_f2
    cmp ax, 0x3D00
    je .bm_f3
    jmp .bm_boot
.bm_nokey:
    mov ax, [es:BDA_TICKS]
    cmp ax, bx
    jb .bm_loop
    jmp .bm_boot
.bm_f2:
    call setup_menu
    jmp .bm_loop
.bm_f3:
    call phonebook_menu
    jmp .bm_loop
.bm_boot:
    pop ds
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ===========================================================================
;  Includes
; ===========================================================================
%include "vga_init.inc"
%include "video.inc"        ; INT 10h + puts/putc
%include "keyboard.inc"     ; 8042 init, INT 09h, INT 16h
%include "serial.inc"       ; COM1 init, INT 14h
%include "system.inc"       ; INT 08h/1Ah/11h/12h/15h/13h stubs, RTC print, IVT init
%include "romslots.inc"     ; ROM scan, INT F0h services
%include "sound.inc"        ; SB1.0 detect (phase 2)
%include "phonebook.inc"    ; PhoneBook cartridge menu
%include "setup.inc"        ; Date/time setup menu

; ===========================================================================
;  Messages
; ===========================================================================
msg_boot_logo:
    db 13,10
    db " _______           _____       _____",13,10
    db " /\\_____\\         /\\____\\     /\\____\\",13,10
    db " |:::|   |       |:::|   |   |:::|   |",13,10
    db " |:::|___|       |:::|___|   |:::|___|",13,10
    db " |:::\\___\\       |:::\\___\\   |:::\\___\\",13,10
    db " |:::\\___\\       |:::\\___\\   |:::\\___\\",13,10
    db 13,10
    db "                 Apex Data Systems",13,10
    db "                      1987",13,10
    db "           Hill Valley, California",13,10
    db "      Connecting Tomorrow, Today.",13,10
    db "    TeleCore 486  -  BBS Terminal Machine",13,10
    db 13,10,0
msg_cpu:    db "  CPU    : Intel 80486DX", 13,10, 0
msg_video:  db "  Video  : Tseng Labs ET4000AX, 1 MB, 80x25 text", 13,10, 0
msg_floppy: db "  Floppy : A: 3.5", '"', " 1.44 MB  (82077 at 3F0h, IRQ6, DMA2)", 13,10, 0
msg_com:    db "  Serial : COM1 at 3F8h IRQ4 - 9600 8N1 (modem)", 13,10, 0
msg_starting_term: db 13,10,"  Starting terminal ROM...", 13,10,13,10, 0
msg_term_returned: db 13,10,"  Terminal ROM returned to BIOS.", 13,10, 0
msg_ready_help:
    db 13,10
    db "  No terminal program installed (boot1.rom).", 13,10
    db "  Typed characters are sent to COM1, received data is shown.", 13,10
    db "  F2 = Setup   F3 = PhoneBook   ESC = reboot", 13,10, 0
msg_prompt: db 13,10,"READY> ", 0
msg_reboot:   db 13,10,"  Rebooting...", 13,10, 0
msg_boot_options:
    db 13,10
    db "  F2=Setup  F3=PhoneBook  any key=boot terminal ROM (auto-boot in 5s)", 13,10, 0

; ===========================================================================
;  Fixed-address tail
; ===========================================================================
    times 0xE6F5 - ($ - $$) db 0xFF
config_table:                       ; INT 15h AH=C0h
    dw 8
    db 0xFC, 0x01, 0x00, 0x70, 0x00, 0x00, 0x00, 0x00

    times 0xEFC7 - ($ - $$) db 0xFF
diskette_param_table:               ; INT 1Eh vector target, 1.44 MB
    db 0xAF, 0x02, 0x25, 0x02, 0x12, 0x1B, 0xFF, 0x6C, 0xF6, 0x0F, 0x08

%include "font8x16.inc"             ; CP437 8x16 glyphs (4 KB), INT 43h

    times 0xFFF0 - ($ - $$) db 0xFF
reset_vector:
    jmp 0xF000:bios_entry
    db "11/07/89"                   ; FFF5h BIOS date
    db 0x00
    db 0xFC                         ; FFFEh model byte: AT
    db 0x00
