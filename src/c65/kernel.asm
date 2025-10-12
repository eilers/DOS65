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
_SETLFS			= $20ec
_SETNAM			= $2110
_OPEN			= $2141
_CLOSE			= $2165
_CHKIN			= $2189
_CHKOUT			= $21ad
_CLRCH			= $21d1
_BASIN			= $21f5
_BSOUT                  = $2219
_GETIN			= $223d
_CLALL			= $2261

; Interface copy buffer
COPY_BUFFER             = $229c

_INIT_AFTER_LOAD        = $ff0c ; Cold boot enry after initial load
