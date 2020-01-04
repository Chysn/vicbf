; Brainf**k Interpreter for Commodore VIC-20
; (c)2020, Jason Justian
;
; Permission is hereby granted, free of charge, to any person obtaining a copy
; of this software and associated documentation files (the "Software"), to deal
; in the Software without restriction, including without limitation the rights
; to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
; copies of the Software, and to permit persons to whom the Software is
; furnished to do so, subject to the following conditions:
;
; The above copyright notice and this permission notice shall be included in all
; copies or substantial portions of the Software.
;
; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
; IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
; FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
; AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
; LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
; OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
; SOFTWARE.
;

; Before executing, two configuration settings need to be done:
; (1) The starting address of the code is placed in $033C/$033D
; (2) The starting address of the data is placed in $033E/$033F
CODE_S = $033C
CODE_E = $033E

; This code is fully-relocatable. You can put it anywhere in memory and it will work.
* = $1800

; Working memory locations 
IP     = $FB
DP     = $FD
DP_HI  = $A3
 
; Copy the starting instruction and data pointers to working memory.
; This is copied so that the BF program can be run multiple times, with
; the state always restored.
INIT    LDX #$04
COPY    LDA $033B,X
        STA $FA,X
        DEX
        BNE COPY
        
; Copy the starting data pointer to the high data pointer location, set the
; first memory cell to 0, then increment the high memory location. The high
; data pointer is used to set each memory cell to 0 the first time it's used.
        LDA #$00
        STA (DP,X)
        LDA $033E
        STA *DP_HI
        LDA $033F
        STA *$A4
        INC *DP_HI
        BNE GETCMD
        INC *$A4
      
; Load the Accumulator with the character at the instruction pointer      
GETCMD  LDY #$00
        LDA (IP),Y

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Handle the data pointer decrement command '<'
;
PTRDEC  CMP #$3C
        BNE PTRINC      ; Nope, check the next possibility
        DEC *DP
        CMP #$FF
        BNE TOADV 
        DEC *$FE
        
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Handle the data pointer increment command '>'
;
PTRINC  CMP #$3E
        BNE MEMDEC      ; Nope, check the next possibility
        INC *DP
        BNE CHKMEM
        INC *$FE
        
; See if the newly-incremented data pointer has gone into new territory
; by advancing to the high data pointer location.        
CHKMEM  LDA *DP
        CMP *DP_HI
        BNE TOADV
        LDA *$FE
        CMP *$A4
        BNE TOADV
; If the data pointer has broken a record, initialize (set to 0) the cell value,
; then advance the high data pointer.
        LDA #$00
        STA (DP_HI),Y
        INC *DP_HI
        BNE TOADV
        INC *$A4
        SEC
        BCS TOADV

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Handle the data decrement command '-'
;
MEMDEC  CMP #$2D
        BNE MEMINC      ; Nope, check the next possibility
        LDA (DP),Y
        TAX
        DEX
        TXA
        STA (DP),Y
        SEC
        BCS TOADV
TOCMD   SEC
        BCS GETCMD

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Handle the data increment command '+'       
;
MEMINC  CMP #$2B
        BNE OUTPUT      ; Nope, check the next possibility
        LDA (DP),Y
        TAX
        INX
        TXA
        STA (DP),Y
        SEC
        BCS TOADV

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Handle the output command '.'  
;      
OUTPUT  CMP #$2E
        BNE INPUT       ; Nope, check the next possibility
        LDA (DP),Y
        JSR $FFD2

; TOADV is a target for relative branches above, that are too far away from ADV
TOADV   SEC
        BCS ADV
; TOGET is a target for relative branches below, that are too far away from GETCMD
TOGET   SEC
        BCS GETCMD

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Handle the input command ','
;
INPUT   CMP #$2C
        BNE SLOOP       ; Nope, check the next possibility
        JSR $FFCF
        LDY #$00
        STA (DP),Y
        SEC
        BCS ADV

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Handle the start loop command '['
;
SLOOP   CMP #$5B
        BEQ STARTL
        CMP #$1B        ; Alias for '[' for programs running in screen memory
        BNE ELOOP       ; Nope, check the next possibility
STARTL  LDA (DP),Y      ; Get the data in the current cell
        BNE NLOOP       ; If it's not zero, enter a new loop

; If the data is 0, the task at hand is to skip the loop by finding
; the matching ']' for this '['. We do this by stepping through the
; code looking for ']'. But not any old ']' will do! Every time a
; '[' is found during the search, the X register is incremented so
; that we know which ']' matches the '[' that we're interested in.
        LDX #$01        ; X is the loop level
NEXTLC  INC *IP         ; Increase the instruction pointer
        BNE CHKCMD
        INC *$FC
CHKCMD  LDA (IP),Y      ; and look at its command
        CMP #$2A    
        BEQ BYE         ; If the program is done, end
CHKLS   CMP #$5B        ; Is it another, inner, '['?
        BEQ FOUNDS      ; Alias for '[' for programs running in screen memory
        CMP #$1B
        BNE CHKLE
FOUNDS  INX             ; If so, increment the loop counter
CHKLE   CMP #$5D        ; Is it a ']'?
        BEQ FOUNDE
        CMP #$1D        ; Alias for ']' for programs running in screen memory
        BNE NEXTLC      ; If not, keep looking
FOUNDE  DEX             ; Is this the ']' that matches the original '['?
        BEQ ADV         ; Yes! Go to the next command
        BNE NEXTLC      ; No, it matches an inner '[', so keep looking
        
; Enter a new loop by pushing the instruction pointer onto the stack. When the
; end-of-loop command ']' is reached, the instruction pointer will be popped
; off the stack to bring the program back to the start of the loop.        
NLOOP   LDA *IP
        PHA
        LDA *$FC
        PHA
        SEC
        BCS ADV

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Handle the end loop command ']'
;
; Pop the start address of this loop off the stack, which takes us back to the
; beginning. After this, jump back to GETCMD without advancing the intruction
; pointer, because we want to make sure the '[' is handled again based on the
; current cell value.
ELOOP   CMP #$5D
        BEQ ENDL
        CMP #$1D        ; Alias for ']' for programs running in screen memory
        BNE EXIT        ; Nope, check the next possibility
ENDL    PLA
        STA *$FC
        PLA
        STA *IP
        SEC
        BCS TOGET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; The BF program ends when a 2A value is reached. This is a sort of "pseudo-command",
; because it's not part of the BF specification. But the program needs to end somehow. 
; (Note that, on the VIC-20, this is an asterisk)  
;                 
EXIT    CMP #$2A
        BNE ADV
BYE     RTS

; Now that the command has been processed, or not processed, advance the instruction
; pointer and go back to GETCMD
ADV     INC *IP
        BNE TOGET
        INC *$FC
        SEC
        BCS TOGET
