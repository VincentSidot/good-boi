; Simple GameBoy Assembly Test File
; This file tests basic CPU instructions

    NOP                    ; 0x00
    LD B, 0x42            ; 0x06 0x42  
    LD C, $FF             ; 0x0E 0xFF
    INC B                 ; 0x04
    DEC C                 ; 0x0D
    
    LD A, B               ; 0x78
    ADD A, C              ; 0x81
    ADD A, 0x10           ; 0xC6 0x10
    
    LD HL, 0x8000         ; 0x21 0x00 0x80
    INC HL                ; 0x23
    LD A, (HL)            ; 0x7E
    
    JP 0x1000             ; 0xC3 0x00 0x10
    JR -5                 ; 0x18 0xFB (relative jump back 5 bytes)
    
    PUSH BC               ; 0xC5
    POP HL                ; 0xE1
    
    CALL 0x2000           ; 0xCD 0x00 0x20
    RET                   ; 0xC9