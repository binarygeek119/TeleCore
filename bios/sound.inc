; ===========================================================================
;  Sound Blaster 1.0 detection + game port (phase 2 fills in; stubs for now)
; ===========================================================================

sound_detect:
    push si
    mov si, msg_sound_none
    call puts
    pop si
    ret

; INT 15h AH=84h backend: CF=1 = not supported
joy_read:
    stc
    ret

msg_sound_none: db "  Sound  : (not installed)", 13,10, 0
