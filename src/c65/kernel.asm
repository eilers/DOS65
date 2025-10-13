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

; Entrypoints SIM -> Transfer -> Kernel
_SETLFS			= $20f6
_SETNAM			= $2124
_OPEN			= $215f
_CLOSE			= $218d
_CHKIN			= $21bb
_CHKOUT			= $21ad
_CLRCH			= $2217
_BASIN			= $2245
_BSOUT                  = $2273
_GETIN			= $22a1
_CLALL			= $22cf

; Interface copy buffer
COPY_BUFFER             = $2319

_INIT_AFTER_LOAD        = $ff0c ; Cold boot enry after initial load
