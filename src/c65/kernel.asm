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
GETIN	=	$FFE4		;get a character (normally keyboard)
CLALL	=	$FFE7		;close all files & channels
CHROUT	=	$FFD2	        ;Char Out


; Entrypoints SIM -> Transfer -> Kernel
_SETLFS =       $20cd
