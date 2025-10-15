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
_SETLFS			= $2100
_SETNAM			= $212e
_OPEN			= $2169
_CLOSE			= $2197
_CHKIN			= $21c5
_CHKOUT			= $21ad
_CLRCH			= $2221
_BASIN			= $224f
_BSOUT                  = $227d
_GETIN			= $22ab
_CLALL			= $22d9

; Interface copy buffer
COPY_BUFFER             = $232d

_INIT_AFTER_LOAD        = $fe7a ; Cold boot enry after initial load
