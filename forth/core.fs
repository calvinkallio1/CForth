\ MATH
\ ( a b -- a / b )
: / /mod swap drop ;
\ ( a b -- rem )
: mod /mod drop ;
\ negate ( n -- -n )
: negate 0 swap - ;
\ true   ( -- -1 )
: true -1 ;
\ false  ( -- 0 )
: false 0 ;
\ not    ( flag -- !flag )
: not 0= ;
\ nip    ( a b -- b )
: nip swap drop ;
\ tuck   ( a b -- b a b )
: tuck dup -rot ;
\ 0<     ( n -- flag )
: 0< 0 < ;
\ 0>     ( n -- flag )
: 0> 0 > ;
\ 0<>    ( n -- flag )
: 0<> 0= not ;
\ <=     ( a b -- flag )       
: <= > not ;
\ >=     ( a b -- flag )       
: >= < not ;
\ cell   ( -- 8 )
: cell 8 ;
\ cells  ( n -- n*8 )
: cells 8 * ;
\ cell+  ( a -- a+8 )
: cell+ 8 + ;

\ COMPILER
\ literal   immediate ( n -- )   compile lit, then n
: literal immediate ' lit , , ;
\ [']       immediate            compile lit; interpret supplies the next xt
: ['] immediate ' lit , ;
\ [compile] immediate            compile the next word even if it's immediate
: [compile] immediate word find >cfa , ;
\ recurse   immediate            compile the xt of the word being defined (via latest)
: recurse immediate latest @ >cfa , ;
\ char      ( -- c )             first byte of the next token
: char word drop c@ ;


\ CONTROL FLOW
\ if     immediate  compile 0branch + placeholder; leave placeholder addr
: if immediate ' 0branch , here @ 0 , ;
\ then   immediate  ( addr -- )  patch placeholder with here - addr
: then immediate dup here @ swap - swap ! ;
\ begin  immediate  ( -- addr )
: begin immediate here @ ;
\ until  immediate  ( addr -- ) 
: until immediate ' 0branch , here @ - , ;
\ again  immediate  ( addr -- )  
: again immediate ' branch , here @ - , ;
\ while  immediate  ( -- addr )  like if
: while immediate ' 0branch , here @ 0 , ;
\ repeat immediate  ( begin-addr while-addr -- ) 
: repeat immediate ' branch , swap here @ - , dup here @ swap - swap ! ;
\ else   immediate  ( if-addr -- else-addr )      
: else immediate ' branch , here @ 0 , swap dup here @ swap - swap ! ;
\ unless immediate  
: unless immediate ' 0= , [compile] if ;


\ STACK EFFECT COMMENTS
\ (  immediate
: ( immediate
  1
  begin
    key
    dup 40 = if drop 1+ else 41 = if 1- then then
    dup 0=
  until
  drop
;

\ DICTIONARY
\ aligned  ( addr -- addr' )   round up to 8
: aligned ( addr -- addr' ) 7 + 7 invert and ;
\ align    ( -- )              align here
: align ( -- ) here @ aligned here ! ;
\ allot    ( n -- )            advance here
: allot ( n -- ) here +! ;
\ c,       ( c -- )            append one byte at here
: c, ( c -- ) here @ c! 1 here +! ;
\ constant ( n -- )            
: constant word create docol , ' lit , , ' exit , ;
\ variable ( -- )             
: variable ( -- ) here @ 1 cells allot word create docol , ' lit , , ' exit , ;

\ OUTPUT
\ cr      ( -- )
: cr ( -- ) 10 emit ;
\ space   ( -- )
: space ( -- ) 32 emit ;
\ bl      ( -- 32 )
: bl ( -- 32 ) 32 ;
\ spaces  ( n -- )
: spaces ( n -- ) begin dup 0> while space 1- repeat drop ;
\ decimal ( -- )
: decimal 10 base ! ;
\ hex     ( -- )
: hex 16 base ! ;
\ u.      ( u -- )          unsigned in current base, no trailing space; recursive
: u. ( u -- ) base @ /mod ?dup if recurse then dup 10 < if 48 else 10 - 65 then + emit ;
\ uwidth  ( u -- n )        digit count in current base
: uwidth ( u -- n ) base @ / ?dup if recurse 1+ else 1 then ;
\ u.r     ( u width -- )
: u.r ( u width -- ) swap dup uwidth rot swap - spaces u. ;
\ .r      ( n width -- )
: .r ( n width -- ) 
  swap dup 0< if negate 1 swap rot 1- else 0 swap rot then
  swap dup uwidth rot swap - spaces swap
  if 45 emit then u.
;
\ .       ( n -- )          redefines the assembly . -- honors base, handles sign
: . ( n -- ) 0 .r space ;
\ u.      ( u -- )          redefine: old u. plus a space
: u. ( u -- ) u. space ;
\ ?       ( addr -- )
: ? ( addr -- ) @ . ;
\ depth   ( -- n )
: depth ( -- n ) dsp@ s0 @ swap - 8 / ;
\ .s      ( -- )            print the stack bottom to top, leave it intact
: .s ( -- ) dsp@ s0 @ begin cell - 2dup <= while dup @ u. repeat 2drop ;

\ STRINGS
\ s"  immediate ( -- addr len )  
\                                
: s" immediate ( -- addr len )
  state @ if
    ' litstring , here @ 0 ,
    begin key dup 34 <> while c, repeat drop
    dup here @ swap - 8 - swap !
    align
  else
    here @ begin key dup 34 <> while over c! 1+ repeat drop
    here @ - here @ swap
  then ;
\ ."  immediate ( -- )            
\                                 
: ." immediate ( -- )
  state @ if 
    [compile] s" ' type ,
  else
    begin key dup 34 = if drop exit then emit again
  then ;

\ INTROSPECTION
: ?hidden ( header -- flag ) 8 + c@ f_hidden and ;
: id. ( header -- ) 8 + dup c@ f_lenmask and swap 1+ swap type ;
: words latest @ begin ?dup while dup ?hidden not if dup id. space then @ repeat cr ;

." core.fs loaded" cr
