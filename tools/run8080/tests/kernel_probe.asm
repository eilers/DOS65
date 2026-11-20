;What the MEGA65 kernel and a 1581 actually return.
;
;The host tests used to invent this. This program runs inside xemu,
;calls the same kernel entries the copy programs call, and writes
;the bytes and the status to a sequential file. Nothing here is
;the DOS/65 bridge. It is the kernel the bridge is supposed to
;pass through.
;
;Each sample is two hex bytes, status then the byte from BASIN,
;so a log line can be read back without PETSCII translation.
;Samples are stored in memory first. Opening the log while a file
;is being read would switch the drive to another channel and end
;the read, which is not what the copy loop does.

.CPU 6502

readst	=	$ffb7
setlfs	=	$ffba
setnam	=	$ffbd
open	=	$ffc0
close	=	$ffc3
chkin	=	$ffc6
ckout	=	$ffc9
clrch	=	$ffcc
basin	=	$ffcf
bsout	=	$ffd2

loglo	=	$10
loghi	=	$11
byte	=	$12
stsave	=	$13
ysav	=	$14
cntlo	=	$16
cnthi	=	$17
fill	=	$18
opna	=	$19
flags	=	$1a
ptr	=	$1b
nlen	=	$1d
nread	=	$1e
sa	=	$1f

	*=	$2000
	.LOAD
	.STORE $2000, ende-$2000, "kernel_probe.prg"

	jmp	main

;---- memory log -------------------------------------------------

loginit	lda	#0
	sta	loglo
	lda	#$40
	sta	loghi
	rts

logbyte	sty	ysav
	ldy	loghi
	cpy	#$60
	bcs	logy
	ldy	#0
	sta	(loglo),y
	inc	loglo
	bne	logy
	inc	loghi
logy	ldy	ysav
	rts

logcr	lda	#13
	jmp	logbyte

logstr	sta	ptr
	sty	ptr+1
	ldy	#0
ls1	lda	(ptr),y
	beq	lsx
	jsr	logbyte
	iny
	bne	ls1
lsx	rts

hexbyte	pha
	lsr	a
	lsr	a
	lsr	a
	lsr	a
	jsr	hexnib
	pla
hexnib	and	#$0f
	cmp	#10
	bcc	hexd
	adc	#6
hexd	adc	#'0'
	jmp	logbyte

;READST alone, before any BASIN, so a status already raised
;is not confused with a byte that arrived with that status.
logst	jsr	readst
	sta	stsave
	lda	#'S'
	jsr	logbyte
	lda	#'T'
	jsr	logbyte
	lda	#'='
	jsr	logbyte
	lda	stsave
	jsr	hexbyte
	jmp	logcr

;Status, a space, the BASIN byte, and a return.
logpair	lda	stsave
	jsr	hexbyte
	lda	#' '
	jsr	logbyte
	lda	byte
	jsr	hexbyte
	jmp	logcr

;Carry and A from the OPEN just executed. JSR does not change
;them, and this routine saves them before it logs.
logopen	php
	sta	opna
	pla
	sta	flags
	lda	#'C'
	jsr	logbyte
	lda	#'='
	jsr	logbyte
	lda	flags
	and	#1
	clc
	adc	#'0'
	jsr	logbyte
	lda	#' '
	jsr	logbyte
	lda	#'A'
	jsr	logbyte
	lda	#'='
	jsr	logbyte
	lda	opna
	jsr	hexbyte
	jmp	logcr

;---- kernel helpers ---------------------------------------------

;Open logical file 3 on device 8. A is the secondary address,
;X is the name length, and the name is at ptr.
open3	sta	sa
	stx	nlen
	lda	#3
	ldx	#8
	ldy	sa
	jsr	setlfs
	lda	nlen
	ldx	ptr
	ldy	ptr+1
	jsr	setnam
	jmp	open

;Read X bytes from the channel already selected. Each BASIN is
;followed at once by READST, with no channel change between them.
readn	stx	nread
rn1	jsr	basin
	sta	byte
	jsr	readst
	sta	stsave
	jsr	logpair
	dec	nread
	bne	rn1
	rts

;The command channel, logical file 15, must already be open.
errch	ldx	#15
	jsr	chkin
	ldx	#24
	jsr	readn
	jmp	clrch

;Create the sequential file named at ptr. cntlo/cnthi is how
;many bytes of fill to write. Zero writes none.
makeseq	lda	#3
	ldx	nlen
	jsr	open3
	bcs	mkx
	ldx	#3
	jsr	ckout
	bcs	mkc
	jsr	writen
mkc	jsr	clrch
	lda	#3
	jsr	close
mkx	rts

writen	lda	cntlo
	ora	cnthi
	beq	wx
w1	lda	fill
	jsr	bsout
	lda	cntlo
	bne	w2
	dec	cnthi
w2	dec	cntlo
	lda	cntlo
	ora	cnthi
	bne	w1
wx	rts

;Point ptr at the text after the call and set nlen from the
;length byte in front of it. The call is jsr named / .byte len / text.
;JSR leaves the address of the length byte minus one on the stack.
named	pla
	sta	ptr
	pla
	sta	ptr+1
	ldy	#1
	lda	(ptr),y
	sta	nlen
	clc
	lda	ptr
	adc	#2
	sta	ptr
	bcc	nm1
	inc	ptr+1
nm1	clc
	lda	ptr
	adc	nlen
	sta	byte
	lda	ptr+1
	adc	#0
	sta	stsave
	sec
	lda	byte
	sbc	#1
	tay
	lda	stsave
	sbc	#0
	pha
	tya
	pha
	rts

;---- the cases --------------------------------------------------

mark	jmp	bsout

main	jsr	loginit
	lda	#'0'
	jsr	mark
	lda	#<banner
	ldy	#>banner
	jsr	logstr

	lda	#15
	ldx	#8
	ldy	#15
	jsr	setlfs
	lda	#0
	jsr	setnam
	jsr	open

	lda	#'1'
	jsr	mark
	lda	#<sone
	ldy	#>sone
	jsr	logstr
	jsr	named
	.byte	7
	.byte	"ONE,S,W"
	lda	#3
	ldx	nlen
	jsr	open3
	jsr	logopen
	ldx	#3
	jsr	ckout
	lda	#$01
	jsr	bsout
	lda	#$08
	jsr	bsout
	lda	#$5a
	jsr	bsout
	jsr	clrch
	lda	#3
	jsr	close
	jsr	errch
	jsr	named
	.byte	7
	.byte	"ONE,S,R"
	lda	#3
	ldx	nlen
	jsr	open3
	jsr	logopen
	ldx	#3
	jsr	chkin
	jsr	logst
	ldx	#8
	jsr	readn
	jsr	clrch
	lda	#<sre
	ldy	#>sre
	jsr	logstr
	ldx	#3
	jsr	chkin
	jsr	logst
	ldx	#2
	jsr	readn
	jsr	clrch
	lda	#3
	jsr	close

	lda	#'2'
	jsr	mark
	lda	#<sempty
	ldy	#>sempty
	jsr	logstr
	jsr	named
	.byte	9
	.byte	"EMPTY,S,W"
	lda	#0
	sta	cntlo
	sta	cnthi
	jsr	makeseq
	jsr	errch
	jsr	named
	.byte	9
	.byte	"EMPTY,S,R"
	lda	#3
	ldx	nlen
	jsr	open3
	jsr	logopen
	ldx	#3
	jsr	chkin
	jsr	logst
	ldx	#8
	jsr	readn
	jsr	clrch
	lda	#3
	jsr	close

	lda	#'3'
	jsr	mark
	lda	#<sgone
	ldy	#>sgone
	jsr	logstr
	jsr	named
	.byte	8
	.byte	"GONE,S,R"
	lda	#3
	ldx	nlen
	jsr	open3
	jsr	logopen
	jsr	errch
	lda	#3
	jsr	close

	lda	#'4'
	jsr	mark
	lda	#<sexists
	ldy	#>sexists
	jsr	logstr
	jsr	named
	.byte	7
	.byte	"ONE,S,W"
	lda	#3
	ldx	nlen
	jsr	open3
	jsr	logopen
	jsr	errch
	lda	#3
	jsr	close
	jsr	named
	.byte	7
	.byte	"ONE,S,R"
	lda	#3
	ldx	nlen
	jsr	open3
	ldx	#3
	jsr	chkin
	ldx	#4
	jsr	readn
	jsr	clrch
	lda	#3
	jsr	close

	lda	#'5'
	jsr	mark
	lda	#<sscratch
	ldy	#>sscratch
	jsr	logstr
	jsr	named
	.byte	8
	.byte	"TEMP,S,W"
	lda	#1
	sta	cntlo
	lda	#0
	sta	cnthi
	lda	#$11
	sta	fill
	jsr	makeseq
	ldx	#15
	jsr	ckout
	ldy	#0
sc1	lda	scratch,y
	jsr	bsout
	iny
	cpy	#8
	bcc	sc1
	jsr	clrch
	jsr	errch

	lda	#'7'
	jsr	mark
	lda	#<sdir
	ldy	#>sdir
	jsr	logstr
	lda	#15
	jsr	close
	jsr	named
	.byte	1
	.byte	"$"
	lda	#0
	ldx	nlen
	jsr	open3
	jsr	logopen
	ldx	#3
	jsr	chkin
	jsr	logst
	lda	#0
	sta	cntlo
	sta	cnthi
dirloop	jsr	basin
	sta	byte
	jsr	readst
	sta	stsave
	jsr	logpair
	inc	cntlo
	bne	dir1
	inc	cnthi
dir1	lda	stsave
	and	#$40
	bne	direx
	lda	cnthi
	cmp	#2
	bcc	dirloop
	jmp	dirdone
direx	ldx	#3
	jsr	readn
dirdone	jsr	clrch
	lda	#3
	jsr	close

	lda	#'8'
	jsr	mark
	lda	#<sdone
	ldy	#>sdone
	jsr	logstr
	jmp	savelog

;---- write the log and leave ------------------------------------

savelog	lda	#2
	ldx	#8
	ldy	#3
	jsr	setlfs
	lda	#7
	ldx	#<nlog
	ldy	#>nlog
	jsr	setnam
	jsr	open
	bcs	sexit
	ldx	#2
	jsr	ckout
	bcs	sclose
	lda	#0
	sta	ptr
	lda	#$40
	sta	ptr+1
sloop	lda	ptr
	cmp	loglo
	bne	sgo
	lda	ptr+1
	cmp	loghi
	beq	sdone2
sgo	ldy	#0
	lda	(ptr),y
	jsr	bsout
	inc	ptr
	bne	sloop
	inc	ptr+1
	jmp	sloop
sdone2	jsr	clrch
sclose	lda	#2
	jsr	close
sexit	lda	#$42
	sta	$d6cf
	rts

banner	.byte	"KPROBE1",13,0
sone	.byte	">ONE",13,0
sempty	.byte	">EMPTY",13,0
sgone	.byte	">GONE",13,0
sexists	.byte	">EXISTS",13,0
sscratch .byte	">SCRATCH",13,0
sre	.byte	">RESELECT",13,0
sdir	.byte	">DIR",13,0
sdone	.byte	">DONE",13,0
scratch	.byte	"S0:TEMP",13
nlog	.byte	"LOG,S,W"

ende
