; Kernel entry points
CURSOR	=	$FF35		;enable (C=0) or disable (C=1) cursor
SETLFS	=	$FFBA		;set LA, FA, SA
SETNAM	=	$FFBD		;set length & file name address
OPEN	=	$FFC0		;open logical file
CLOSE	=	$FFC3		;close logical file
CHKIN	=	$FFC6		;set channel in
CKOUT	=	$FFC9		;set channel out
CLRCH	=	$FFCC		;restore default channel
BASIN	=	$FFCF		;input from channel
BSOUT	=	$FFD2		;output to channel
CHROUT	=	$FFD2		;Char Out .. same as BSOUT
GETIN	=	$FFE4		;get a character (normally keyboard)
CLALL	=	$FFE7		;close all files & channels
SETBNK  =       $FF6B           ;set bank

; Kernel vectors for interrupts
NMI_VECT	= $FFFA
RESET_VECT	= $FFFC
IRQ_VECT	= $FFFE

; Interrupt Entry points
_NMI_KERNEL	= $22c9
_IRQ_KERNEL	= $22f9

; Exchange area for preserving interrupt related data
IRQ_PF	= $fe77		; Processor flags for IRQ on Bank 5
NMI_PF	= $fe7e		; Processor flags for NMI on Bank 5

; Entrypoints SIM -> Transfer -> Kernel
_CURSOR                 = $20f9
_SETLFS			= $211c
_SETNAM			= $213f
_OPEN			= $216f
_CLOSE			= $2192
_CHKIN			= $21b5
_CKOUT			= $21d8
_CLRCH			= $21fb
_BASIN			= $221e
_BSOUT                  = $2241
_GETIN			= $2264
_CLALL			= $2287

; Bridge copy buffer
COPY_BUFFER             = $2354

_INIT_AFTER_LOAD        = $fe04 ; Cold boot enry after initial load
