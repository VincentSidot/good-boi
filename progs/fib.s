;; Simple fibonacci program to test the cpu.


;; 0x0000 -> Main entry point
NOP                         ; 0x00 No operation (just a placeholder)
LD HL, 0x0002               ; 0x21 Load i = 0 into BC
PUSH HL                     ; 0xE5 Push Fib(0)
LD HL, 0x0001               ; 0x21 Load n = 1 into DE
LD DE, 0x0001               ; 0x11 Load n = 2 into HL

LOOP:
    ; Run Fibonacci calculation
    CALL FIB                ; 0xCD Call Fibonacci function
    POP BC                  ; 0xC1 Pop i counter into BC (Fib(n))
    PUSH DE                 ; 0xD5 Save Fib(n-1)
    PUSH HL                 ; 0xE5 Save Fib(n)

    ; Store result    
    LD HL, 0xB000           ; 0x21 Load base address for Fibonacci storage
    ADD HL, BC              ; 0x09 Offset by ADDR
    POP DE                  ; 0xD1 Pop Fib(n)
    LD A, E                 ; 0x7B Load low byte of address
    LD (HL), A              ; 0x77 Store high byte

    ; Check loop condition
    POP HL                  ; 0xE1 Restore i

    INC BC                  ; 0x03 i++
    LD A, 0x000B            ; 0xFA Load 11 into A
    CP A, C                 ; 0xB9 Compare i with 11
    PUSH BC                 ; 0xC5 Save i
    JP NZ, 0x000B           ; 0xC2 If i < 10, repeat loop

; End of program
HALT                        ; 0x76 Halt execution


;; 0x0040 -> Fibonacci function
;; Input:
;; Fib(n-2) => HL
;; Fib(n-1) => DE
;; Output:
;; Fib(n)   => HL
;; Fib(n-1) => DE (unchanged)
FIB:
    ADD HL, DE              ; 0x19 Fib(n  ) = Fib(n-1) + Fib(n-2)
    RET                     ; 0xC9 Return with Fib(n) in HL

;; 0xB000: Fibonacci numbers should be stored here
2                           ; Fib(2) = 2
3                           ; Fib(3) = 3
5                           ; Fib(4) = 5
8                           ; Fib(5) = 8
13                          ; Fib(6) = 13
21                          ; Fib(7) = 21
34                          ; Fib(8) = 34
55                          ; Fib(9) = 55
89                          ; Fib(10) = 89
