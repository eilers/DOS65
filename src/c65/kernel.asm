; Kernel entry points
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
_NMI_KERNEL	= $22b4
_IRQ_KERNEL	= $22e4

; Exchange area for preserving interrupt related data
IRQ_PF	= $ff83		; Processor flags for IRQ on Bank 5
NMI_PF	= $ff8a		; Processor flags for NMI on Bank 5

; Entrypoints SIM -> Transfer -> Kernel
_SETLFS			= $20fb
_SETNAM			= $211f
_OPEN			= $2150
_CLOSE			= $2174
_CHKIN			= $2198
_CHKOUT			= $21e0
_CLRCH			= $21e0
_BASIN			= $2204
_BSOUT                  = $2228
_GETIN			= $224c
_CLALL			= $2270

; Interface copy buffer
COPY_BUFFER             = $233f

_INIT_AFTER_LOAD        = $ff31 ; Cold boot enry after initial load
