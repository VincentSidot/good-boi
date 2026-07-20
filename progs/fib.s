;; Simple fibonacci program to test the cpu.
;;
;; Assembled by src/tools/asm.zig (`zig build asm`). Branch targets come from
;; labels now, so the hand-computed 0x8040 / 0x800B addresses are gone.

.org $8000

storage equ $B000               ; where the results are written
limit   equ 11                  ; stop once the counter reaches this

;; Entry point
        NOP                     ; placeholder
        LD HL, $0002            ; Fib(2)
        PUSH HL
        LD HL, $0001            ; Fib(n)   = 1
        LD DE, $0001            ; Fib(n-1) = 1

LOOP:
        ; Run one Fibonacci step
        CALL FIB
        POP BC                  ; i counter
        PUSH DE                 ; save Fib(n-1)
        PUSH HL                 ; save Fib(n)

        ; Store the result at storage + i
        LD HL, storage
        ADD HL, BC
        POP DE                  ; Fib(n)
        LD A, E
        LD (HL), A

        ; Restore and advance
        POP HL
        INC BC                  ; i++
        LD A, limit
        CP A, C                 ; compare i against the limit
        PUSH BC                 ; save i
        JP NZ, LOOP

;; End of program
        HALT

;; Fibonacci step
;; Input:  Fib(n-2) => HL, Fib(n-1) => DE
;; Output: Fib(n)   => HL, Fib(n-1) => DE (unchanged)
.org $8040
FIB:
        ADD HL, DE
        RET

;; Results are written at `storage` while the program runs.
;; Expected: 2, 3, 5, 8, 13, 21, 34, 55, 89
.org $8050
