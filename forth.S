// HARDWARE CONSTANTS
.equ UART_BASE, 0x09000000
.equ UART_DR, 0x00 // data register: write = send, read = receive
.equ UART_FR, 0x18 // flag register, status bits
.equ FR_RXFE, (1 << 4) // bit 4: receive FIFO empty (nothing to read)
.equ FR_TXFF, (1 << 5) //bit 5: transmit FIFO full (can't send yet)


// HEADER FLAGS 
.equ F_IMMED, 0x80 // Word runs while compiling
.equ F_HIDDEN, 0x20 // Word can't be found by name 
.equ F_LENMASK, 0x1f // name length lives in bits 0-4

// VM REGISTERS 
// Designated callee-saved registers for the Forth VM to be used.
//  x19 = IP or instruction pointer, address of NEXT cell of threaded code
//  x20 = W or working register: address of the codeword of the word running now 
//  x21 = DSP or data stack pointer -- [x21] is the top item, grows downward
//  x22 = RSP or return stack pointer -- [x22] is top item, grows downward

// MACROS
// NEXT: run the word whose execution token (xt) is at IP, and advance IP
// Every primitive ends with NEXT
.macro NEXT
  ldr x20, [x19], #8 // W = the cell at IP; then IP advances 
  ldr x0, [x20]      // x0 = the codeword stored at that xt 
  br x0              // jump to the machine code it names 
.endm 

// Data stack operations
.macro PUSH reg 
  str \reg, [x21, #-8]!
.endm 
.macro POP reg 
  ldr \reg, [x21], #8 
.endm 

// Return stack operations 
.macro PUSHRSP reg
  str \reg, [x22, #-8]!
.endm 
.macro POPRSP reg 
  ldr \reg, [x22], #8
.endm
.section .text.boot

// Dictionary macros 
// Essentially a linked list of headers for words 
// Header layout in memory:
//  +0  link        address of the previous word's header (0 = none)
//  +8  len|flags   one byte
//  +9  name        the name's characters
//      padding     0s up to an 8-byte boundary
//      codeword    address of the machine code that runs this word <- xt 
//      body        (colon words only) list of xts 
.set link, 0 // Set link

.macro header name, label, flags=0 
  .data                    // headers go in the data section 
  .balign 8                // link field must be an aligned 8-byte cell
name_\label :              // e.g. name_EMIT
  .quad link               //link to the previous header 
  .set link, name_\label   // now we are the latest header 
  .byte \flags + (9f - 8f) // length = address after name - address before
8: .ascii "\name"          // the name's bytes (no zero terminator)
9:
  .balign 8                // pad so the codeword is 8-byte aligned 
.endm 

// A primitive: a word written in machine code
.macro defcode name, label, flags=0 
  header "\name", \label, \flags 
\label :                // this label is the xt (address of codeword)
  .quad code_\label     // codeword = address of the code below 
  .text                 // switch to code for the body 
  .balign 4             // instructions must be 4 byte aligned
code_\label:            // everything after defcode goes here 
.endm 

// A colon word written by hand as a list of xts 
.macro defword name, label, flags=0 
  header "\name", \label, \flags 
\label :
  .quad DOCOL   // codeword = DOCOL; .quad cells follow
.endm

// defvar builds a word that pushes the address of a cell
.macro defvar name, label, initial=0, flags=0
  defcode "\name", \label, \flags
  ldr x0, =var_\label
  PUSH x0
  NEXT
  .data
  .balign 8
var_\label:
  .quad \initial
.endm


// BOOT 
.global _start
_start:
  ldr x0, =machine_stack_top
  mov sp, x0

  // Both forth stacks start empty 
  ldr x21, =data_stack_top
  ldr x22, =return_stack_top 

  // point IP at test program (below) and start the machine 
  ldr x19, =test 
  NEXT

// Inner Interpreter
// runs lists of words 
.text
.balign 4

// DOCOL: the codeword of every colon word 
DOCOL:
  PUSHRSP x19       // save where the caller was
  add x19, x20, #8  // body starts one cell after the codeword 
  NEXT              // run the body 

// EXIT 
// The last cell of every colon word; restores IP 
defcode "exit", EXIT
  POPRSP x19 
  NEXT 

// PRIMITIVES 
// ----------LIST----------
// LIT: IP skips over a word and skips an inline data cell 
// EMIT: IP steps over a plain word and gives visible output
// BRANCH: IP jumps backwards by an offset
// INCR: Increments the top of the stack by 1 
//------------------------------------------------------------


// LIT: push the cell that follows it in the threaded code
defcode "lit", LIT 
  ldr x0, [x19], #8   // x0 = the number, IP increments
  PUSH x0 
  NEXT 

// EMIT: pop a character and send it to the UART 
defcode "emit", EMIT 
  POP x0 
  bl _emit 
  NEXT 

// BRANCH: add the following cell (byte offset) to IP 
defcode "branch", BRANCH
  ldr x0, [x19]       // x0 = offset (IP not advanced)
  add x19, x19, x0    // IP += offset
  NEXT

// INCR: ( n -- n + 1 )
defcode "1+", INCR
  ldr x0, [x21]
  add x0, x0, #1 
  str x0, [x21]
  NEXT 

//DECR: ( n -- n - 1 )
defcode "1-", DECR 
  ldr x0, [x21]
  sub x0, x0, #1 
  str x0, [x21]
  NEXT 

// DUP: ( n -- n n )
defcode "dup", DUP 
  ldr x0, [x21]
  PUSH x0 
  NEXT 

// ADD: ( a b -- a + b )
defcode "+", ADD
  POP x0 
  ldr x1, [x21]
  add x1, x1, x0 
  str x1, [x21]
  NEXT 

// SUB: ( a b -- a - b )
defcode "-", SUB 
  POP x0 
  ldr x1, [x21]
  sub x1, x1, x0 
  str x1, [x21]
  NEXT

// MUL: ( a b -- a * b )
defcode "*", MUL 
  POP x0 
  ldr x1, [x21]
  mul x1, x1, x0 
  str x1, [x21]
  NEXT 

// DIVMOD: ( a b -- rem quot )
defcode "/mod", DIVMOD 
  POP x1 
  ldr x0, [x21]
  sdiv x2, x0, x1 
  msub x3, x2, x1, x0 
  str x3, [x21]
  PUSH x2 
  NEXT 

// EQU: ( a b -- flag )
defcode "=", EQU 
  POP x0 
  ldr x1, [x21]
  cmp x1, x0 
  csetm x1, eq 
  str x1, [x21]
  NEXT 

// NEQU: ( a b -- flag )
defcode "<>", NEQU 
  POP x0 
  ldr x1, [x21]
  cmp x1, x0 
  csetm x1, ne
  str x1, [x21]
  NEXT 

// LT: ( a b -- flag )
defcode "<", LT
  POP x0 
  ldr x1, [x21]
  cmp x1, x0
  csetm x1, lt
  str x1, [x21]
  NEXT

// GT: ( a b -- flag )
defcode ">", GT
  POP x0 
  ldr x1, [x21]
  cmp x1, x0
  csetm x1, gt
  str x1, [x21]
  NEXT

// LE: ( a b -- flag )
defcode "<=", LE
  POP x0 
  ldr x1, [x21]
  cmp x1, x0
  csetm x1, le
  str x1, [x21]
  NEXT

// GE: ( a b -- flag )
defcode ">=", GE
  POP x0 
  ldr x1, [x21]
  cmp x1, x0
  csetm x1, ge
  str x1, [x21]
  NEXT

// DROP: ( a -- )
defcode "drop", DROP
  POP x0 
  NEXT 

// SWAP: ( a b -- b a )
defcode "swap", SWAP 
  ldp x0, x1, [x21]
  stp x1, x0, [x21]
  NEXT 

// OVER: ( a b -- a b a )
defcode "over", OVER 
  ldr x0, [x21, #8]
  PUSH x0 
  NEXT 

// ROT: ( a b c -- b c a )
defcode "rot", ROT 
  ldr x2, [x21]
  ldr x1, [x21, #8]
  ldr x0, [x21, #16]
  str x1, [x21, #16]
  str x2, [x21, #8]
  str x0, [x21]
  NEXT 

// NROT: ( a b c -- c a b )
defcode "-rot", NROT 
  ldr x2, [x21]
  ldr x1, [x21, #8]
  ldr x0, [x21, #16]
  str x2, [x21, #16]
  str x0, [x21, #8]
  str x1, [x21]
  NEXT

// TWODROP: ( a b -- )
defcode "2drop", TWODROP
  add x21, x21, #16
  NEXT 

// TWODUP: ( a b -- a b a b )
defcode "2dup", TWODUP 
  ldp x0, x1, [x21]
  PUSH x1 
  PUSH x0 
  NEXT 

// QDUPE: ( x -- x x | 0 )
defcode "?dup", QDUPE
  ldr x0, [x21]
  cbz x0, 1f
  PUSH x0 
1:
  NEXT 

// AND: ( a b -- a & b )
defcode "and", AND
  POP x0
  ldr x1, [x21]
  and x1, x1, x0
  str x1, [x21]
  NEXT

// OR: ( a b -- a | b )
defcode "or", OR
  POP x0
  ldr x1, [x21]
  orr x1, x0, x1
  str x1, [x21]
  NEXT

// XOR: ( a b -- a ^ b )
defcode "xor", XOR
  POP x0
  ldr x1, [x21]
  eor x1, x0, x1
  str x1, [x21]
  NEXT

// INVERT: ( a -- ~ a )
defcode "invert", INVERT
  ldr x0, [x21]
  mvn x0, x0
  str x0, [x21]
  NEXT

// STORE: ( val addr -- )
defcode "!", STORE 
  POP x0 //addr
  POP x1 //val
  str x1, [x0]
  NEXT

// FETCH: ( addr -- val )
defcode "@", FETCH
  ldr x0, [x21]
  ldr x0, [x0]
  str x0, [x21]
  NEXT

// ADDSTORE: ( delta addr -- )
defcode "+!", ADDSTORE
  POP x0
  POP x1
  ldr x2, [x0]
  add x2, x2, x1
  str x2, [x0]
  NEXT

// STOREBYTE: ( char addr -- )
defcode "c!", STOREBYTE
  POP x0
  POP x1
  strb w1, [x0]
  NEXT

// FETCHBYTE: ( addr -- char )
defcode "c@", FETCHBYTE
  ldr x0, [x21]
  ldrb w0, [x0]
  str x0, [x21]
  NEXT

// TOR (to return stack): ( a -- ) R : ( -- a )
defcode ">r", TOR
  POP x0
  PUSHRSP x0
  NEXT

// FROMR: ( -- a ) R: ( a -- )
defcode "r>", FROMR
  POPRSP x0
  PUSH x0
  NEXT

// RSPFETCH: ( -- addr )
defcode "rsp@", RSPFETCH
  PUSH x22
  NEXT

// RSPSTORE ( addr -- )
defcode "rsp!", RSPSTORE
  POP x22
  NEXT

// RDROP: R : ( a -- )
defcode "rdrop", RDROP
  POPRSP x0
  NEXT

// DSPFETCH: ( -- addr )
defcode "dsp@", DSPFETCH
  mov x0, x21
  PUSH x0
  NEXT

// DSPSTORE: ( addr -- )
defcode "dsp!", DSPSTORE
  ldr x21, [x21]
  NEXT

// ZBRANCH: ( flag -- )
defcode "0branch", ZBRANCH
  POP x0
  cbz x0, code_BRANCH
  add x19, x19, #8
  NEXT

// EXECUTE: ( xt -- )
defcode "execute", EXECUTE
  POP x20
  ldr x0, [x20]
  br x0

// KEY ( -- char )
defcode "key", KEY
  bl _key
  PUSH x0
  NEXT

// DOT: ( n -- )
defcode ".", DOT
  POP x0
  bl _print_num
  NEXT

// BYE
defcode "bye", BYE
  ldr x0, =0x84000008
  hvc #0
1:
  wfe
  b 1b

// BASE
defvar "base", BASE, 10

// TYPE: ( addr len -- )
defcode "type", TYPE
  POP x4 //len
  POP x5 //addr
  cbz x4, 2f
1:
  ldrb w0, [x5], #1
  bl _emit
  sub x4, x4, #1
  cbnz x4, 1b
2:
  NEXT

// WORD: ( -- addr len )
defcode "word", WORD
  bl _word
  PUSH x0
  PUSH x1
  NEXT

// NUMBER: ( addr len -- n unparsed )
defcode "number", NUMBER
  POP x1
  POP x0
  bl _number
  PUSH x0
  PUSH x1
  NEXT

// State variables
defvar "state", STATE, 0            // 0 = interpreting, 1 = compiling
defvar "here", HERE, _end            // next free dict byte
defvar "latest", LATEST, last_word  // most recently defined header 
defvar "s0", SZ, data_stack_top     // where an empty data stack points 

// FIND: ( addr len -- header | 0 )
defcode "find", FIND
  POP x1
  POP x0
  bl _find
  PUSH x0
  NEXT

// TCFA: ( header -- xt )
defcode ">cfa", TCFA
  POP x0
  bl _tcfa
  PUSH x0
  NEXT

// CREATE: ( addr len -- )
defcode "create", CREATE
  POP x1
  POP x0
  ldr x2, =var_HERE
  ldr x3, [x2]            // here -> new header address 
  ldr x4, =var_LATEST     // latest -> previous header 
  ldr x5, [x4]
  str x5, [x3]            // link field = previous header 
  strb w1, [x3, #8]       // len byte 
  add x6, x3, #9          // name begins here
 1:
  ldrb w7, [x0], #1         // read a name char, advance the token pointer
  strb w7, [x6], #1         // write it into the header, advance the write pointer
  sub  x1, x1, #1
  cbnz x1, 1b
  add  x6, x6, #7
  and  x6, x6, #~7          // align up — same idiom as _tcfa
  str  x6, [x2]             // here   = aligned end of the name   (value → address in x2)
  str  x3, [x4]             // latest = the new header            (value → address in x4)
  NEXT 
defcode ",", COMMA
  POP  x0
  ldr  x1, =var_HERE
  ldr  x2, [x1]
  str  x0, [x2], #8       // store at here, advance one cell
  str  x2, [x1]            // write the advanced pointer back
  NEXT

defcode "[", LBRAC, F_IMMED
  ldr  x0, =var_STATE
  mov  x1, #0
  str  x1, [x0]
  NEXT

defcode "]", RBRAC
  ldr  x0, =var_STATE
  mov  x1, #1
  str  x1, [x0]
  NEXT

defcode "immediate", IMMEDIATE, F_IMMED
  ldr  x0, =var_LATEST
  ldr  x0, [x0]             // only the value needed here — no write-back of latest itself
  ldrb w1, [x0, #8]
  eor  w1, w1, #F_IMMED
  strb w1, [x0, #8]
  NEXT

defcode "hidden", HIDDEN    // ( header -- )
  POP  x0
  ldrb w1, [x0, #8]
  eor  w1, w1, #F_HIDDEN
  strb w1, [x0, #8]
  NEXT

defword ":", COLON
  .quad WORD, CREATE        // ( -- addr len ) ( addr len -- )
  .quad LIT, DOCOL, COMMA     // compile the codeword that runs colon words
  .quad LATEST, FETCH, HIDDEN
  .quad RBRAC                 // enter compile mode
  .quad EXIT

defword ";", SEMICOLON, F_IMMED
  .quad LIT, EXIT, COMMA     // compile the word every colon word ends with
  .quad LATEST, FETCH, HIDDEN
  .quad LBRAC                 // back to interpreting
  .quad EXIT
// -------- must stay after the LAST word defined in assembly --------
.set last_word, link

// Test 
.data
.balign 8
test:
  .quad WORD, FIND          // ( -- header|0 )
  .quad QDUPE, ZBRANCH, 24  // 0 → loop
  .quad TCFA, EXECUTE       // ( header -- xt ) ( xt -- )
  .quad BRANCH, -64 

// UART Helpers 
.text
.balign 4

// _emit: send the character in w0
_emit:
  ldr x1, =UART_BASE
  cmp w0, #10           // is it LF?
  b.ne 2f               // If not, skip the CR 
  mov w3, #13           // If yes, send the CR first 
1:
  ldr w2, [x1, #UART_FR]
  tst w2, #FR_TXFF      // transmit FIFO full?
  b.ne 1b               // if yes, wait until empty 
  str w3, [x1, #UART_DR]
2:
  ldr w2, [x1, #UART_FR]
  tst w2, #FR_TXFF
  b.ne 2b 
  str w0, [x1, #UART_DR]    // send the character 
  ret 

// _key: wait for a char, echo it, return it in w0
_key:
    stp  x29, x30, [sp, #-16]!
    ldr  x1, =UART_BASE
1:  ldr  w2, [x1, #UART_FR]
    tst  w2, #FR_RXFE           // receive FIFO empty?
    b.ne 1b                     // yes: wait
    ldr  w0, [x1, #UART_DR]
    and  w0, w0, #0xff          // DR bits 8-11 are error flags; keep the char
    cmp  w0, #13                // Enter sends CR...
    b.ne 2f
    mov  w0, #10                // ...turn it into LF
2:  bl   _emit                  // echo (doesn't change w0)
    ldp  x29, x30, [sp], #16
    ret

// _print_num: print x0 as signed decimal plus a trailing space. Clobbers x0-x7.
_print_num:
  stp x29, x30, [sp, #-16]!
  sub sp, sp, #32               // 32-byte digit buffer on the machine stack
  add x4, sp, #32               // x4 = one past the end; we fill backwards
  mov x7, x4                    // x7 = end marker for the print loop
  mov x5, #10
  mov x6, x0                    // keep the original for the sign test
  cmp x0, #0
  cneg x0, x0, lt               // x0 = |x0|
1:
  udiv x1, x0, x5               // x1 = x0 / 10
  msub x2, x1, x5, x0           // x2 = x0 - x1*10   (the digit)
  add x2, x2, #'0'
  strb w2, [x4, #-1]!
  mov x0, x1
  cbnz x0, 1b
  tbz x6, #63, 2f               // sign bit clear? skip the minus
  mov w2, #'-'
  strb w2, [x4, #-1]!
2:
  ldrb w0, [x4], #1
  bl _emit                      // _emit only clobbers x1-x3, so x4-x7 survive
  cmp x4, x7
  b.lo 2b
  mov w0, #' '
  bl _emit
  add sp, sp, #32
  ldp x29, x30, [sp], #16
  ret
.ltorg 

// _word: read the next whitespace-delimited token into word_buffer. 
// Returns x0 = address, x1 = length. 
_word:
  stp x29, x30, [sp, #-16]!

// Skip leading whitespace
1:
  bl _key               // next char -> w0
  cmp w0, #'\\'         // backslash?
  b.eq 3f               // yes? go skip the comment
  cmp w0, #' '
  b.ls 1b               // loop if still whitespace 

  ldr x4, =word_buffer  // write pointer = start of buffer

// Collect the token
2:
  strb w0, [x4], #1
  bl _key
  cmp w0, #' '
  b.hi 2b               // char > space -> part of the token

  ldr x0, =word_buffer
  sub x1, x4, x0        // length = write pointer - start
  ldp x29, x30, [sp], #16 
  ret

3:                      // backslash comment
  bl _key
  cmp w0, #10           // LF?
  b.ne 3b               // not yet, keep looping
  b 1b                  // back to whitespace skipping
  
// _number: given addr in x0 and len in x1, walk the characters
// and build the value digit by digit
_number:
  mov x2, x0                // move address to read pointer
  mov x3, #0                // initialize accumulator (x3) to 0
  mov x6, #0                // initialize negative flag (x6) to 0
  ldr x4, =var_BASE         // address of the base cell
  ldr x4, [x4]              // value at that address
  cbz x1, 9f                // empty token -> value 0, unparsed 0

// leading minus check
  ldrb w5, [x2]             // peek first character
  cmp w5, #'-'
  b.ne 1f                   // not a minus, go straight to the number loop
  mov x6, #1                // set the negative flag
  add x2, x2, #1            // advance the read pointer past the '-'
  sub x1, x1, #1            // decrement the length 
  cbnz x1, 1f               // more chars -> number loop 
  mov x1, #1                // bare '-': not a number, report 1 unparsed
  b 9f

// number loop
1:
  ldrb w5, [x2], #1
  sub w5, w5, #'0'
  cmp w5, #10
  b.lo 2f                   // 0-9 -> it's a digit, check against base
  sub w5, w5, #('A' - '0')
  cmp w5, #26
  b.lo 4f                   // A-Z -> add 10 below
  sub w5, w5, #('a' - 'A')
  cmp w5, #26
  b.hs 8f                   // not a-z, stop parsing
4:
  add w5, w5, #10           // letters are digits 10..35
2:
  cmp x5, x4                // digit vs base 
  b.hs 8f                   // digit >= base, stop parsing
  madd x3, x3, x4, x5       // accumulator = accumulator * base + digit 
  sub x1, x1, #1            // one more char consumed
  cbnz x1, 1b               // more left -> loop again

// Finish
8:
  cbz x6, 9f                // flag clear -> skip negate 
  neg x3, x3
9:
  mov x0, x3
  ret

// _find: takes the token word left, leaves the header
// address if a word by that name exists, or 0 
// ---- REGISTERS ----
// x2 -- current header
// w3 -- that header's len|flags byte, masked
// x4 -- pointer into the header's name
// x5 -- pointer into the token
// x6 -- chars left to compare
// w7, w8 -- one char from each
_find:
  ldr x2, =var_LATEST
  ldr x2, [x2]
1:
  cbz x2, 4f                // link of 0 means end of chain and header not found
  ldrb w3, [x2, #8]         // len | flags byte
  and w3, w3, #(F_HIDDEN | F_LENMASK)
  cmp x3, x1                // same length as token?
  b.ne 3f                   // no? next header 
  add x4, x2, #9            // name starts after link(8) + len (1)
  mov x5, x0                // token pointer 
  mov x6, x1                // count 
2:
  ldrb w7, [x4], #1 
  ldrb w8, [x5], #1 
  cmp w7, w8
  b.ne 3f                   // token mismatch -> next header 
  sub x6, x6, #1 
  cbnz x6, 2b
  mov x0, x2                // every char matched -> return this header 
  ret
3:
  ldr x2, [x2]              // follow the link to the previous header 
  b 1b
4:
  mov x0, #0
  ret

// _tcfa: converts a header address into an execution token 
_tcfa:
  ldrb w1, [x0, #8]
  and w1, w1, #F_LENMASK
  add x0, x0, #9          // past link + len byte
  add x0, x0, x1          // past the name 
  add x0, x0, #7 
  and x0, x0, #~7         // round up to a multiple of 8
  ret

// The three stacks 
.bss 
.balign 16 
  .space 8192 
machine_stack_top:    // sp starts here 
  .space 8192
data_stack_top:
  .space 8192         // x21 starts here 
return_stack_top:     // x22 starts here 
word_buffer:
  .space 32
