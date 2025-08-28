pzstrt	=	$2		;start of page zero "free" RAM
btejmp	=	$100		;warm boot jump
pemjmp	=	$103		;jump to pem
iostat	=	$106		;i/o status
dflfcb	=	$107		;default fcb
dflbuf	=	$128		;default buffer
tea	=	$200		;tea start
ccmlng	=	2037		;ccm length
pemlng	=	3047		;pem length
msize	=	64		;memory size in 1k blocks
pages	=	10		;pages in sim
memlng	=	msize*1024	;memory length in bytes

;fixed parameters
lf	=	$a		;linefeeed
cr	=	$d		;return
eof	=	$1a		;end of file
null	=	0		;null
ctlc	=	3		;abort
ctle	=	5		;physical cr lf
ctli	=	9		;tab character
ctlp	=	$10		;toggle printer
ctlr	=	$12		;repeat line
ctls	=	$13		;freeze
ctlx	=	$18		;cancel
semico	=	$3b		;semicolon
delete	=	$7f		;delete character
numcmd	=	36		;number commands
