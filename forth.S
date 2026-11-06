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

// DUP: ( n -- n n )
defcode "dup", DUP 
  ldr x0, [x21]
  PUSH x0 
  NEXT 

// ADD: ( a b -- a + b )
defcode "+", ADD
  
// Test 
.data
.balign 8 
test:
  .quad LIT, 65, EMIT 
  .quad LIT, 66, EMIT 
  .quad BRANCH, -56


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

.ltorg 

// The three stacks 
.bss 
.balign 16 
  .space 8192 
machine_stack_top:    // sp starts here 
  .space 8192
data_stack_top:
  .space 8192         // x21 starts here 
return_stack_top:     // x22 starts here 
