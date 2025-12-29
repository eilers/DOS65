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
_NMI_KERNEL	= $22d8
_IRQ_KERNEL	= $2308

; Exchange area for preserving interrupt related data
IRQ_PF	= $feb3		; Processor flags for IRQ on Bank 5
NMI_PF	= $feba		; Processor flags for NMI on Bank 5

; Entrypoints SIM -> Transfer -> Kernel
_CURSOR                 = $20fb
_SETLFS			= $211f
_SETNAM			= $2143
_OPEN			= $2174
_CLOSE			= $2198
_CHKIN			= $21bc
_CKOUT			= $21e0
_CLRCH			= $2204
_BASIN			= $2228
_BSOUT                  = $224c
_GETIN			= $2270
_CLALL			= $2294

; Interface copy buffer
COPY_BUFFER             = $2363

_INIT_AFTER_LOAD        = $fe61 ; Cold boot enry after initial load
