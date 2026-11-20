;Shared support for DOS2CBM, CBM2DOS, and CBMDIR.
;
;This file is included. It does not set the origin. The program sets
;the origin at the transient execution area, $200, jumps over this
;file to its own code, and then includes it. The names below are
;equates, so they do not move that origin.
;
;DOS/65 calls go through the Primitive Execution Module (PEM) at
;$103. PEM keeps eight bytes of page zero, $02 through $09, and
;swaps them aside for the duration of a call. The kernel, the
;Commodore ROM that talks to the serial bus, keeps its own data
;from $90 upward. Everything this file remembers sits at $10 and
;up, which neither of them uses.
;
;On the Commodore 64 the kernel really is at the addresses below.
;On the MEGA65 the System Interface Module (SIM) plants a jump at
;the same addresses. The programs use only 6502 instructions, so
;the same source can be built for the Commodore 64 port.
;
;Two logical files are used, and only those two are closed.
;Logical file 3, secondary address 3, carries the file bytes.
;Secondary address 3 returns every byte, including the two-byte
;load address at the front of a program file. Logical file 4,
;secondary address 15, is the drive's command and error channel.
;The SIM already holds logical files 2 and 15 open for the DOS/65
;disk, and it borrows logical file 4 only while it prints. These
;programs never turn printer echo on, and they close file 4
;before they return.
;
;Reading a byte does not by itself say that the file has ended.
;The kernel's status byte has to be read after the byte. Bit 6
;means end of file, and the byte that came with it is a carriage
;return, not file data. That status entry is READST at $FFB7.

;kernel entries. Same numbers on a Commodore 64 and a MEGA65.
readst	=	$ffb7		;serial status. Bit 6 is end of file
setlfs	=	$ffba		;set logical file, device, secondary address
setnam	=	$ffbd		;set name length and address
open	=	$ffc0		;open the file set up above
close	=	$ffc3		;close one logical file
chkin	=	$ffc6		;take input from a logical file
ckout	=	$ffc9		;send output to a logical file
clrch	=	$ffcc		;back to the keyboard and the screen
basin	=	$ffcf		;read one byte from the input file
bsout	=	$ffd2		;write one byte to the output file

;PEM at $103. X is the function, A and Y are the value or address.
pem	=	$103
conout	=	2		;print the character in A
strout	=	9		;print the string at A,Y up to $
openf	=	15		;open the file control block at A,Y
closef	=	16		;close it
dltf	=	19		;delete it
readf	=	20		;read one 128-byte record. 0 is ok
writf	=	21		;write one record. 0 is ok
makef	=	22		;create it. 255 means the disk is full
dmaf	=	26		;the next record goes to the address in A,Y

;The Console Command Module leaves the text after the program
;name at $128. The first byte is the length. The text itself
;starts with the space that followed the program name.
dflbuf	=	$128

lfdat	=	3		;logical file for the bytes
lfcmd	=	4		;logical file for the error channel
sadata	=	3		;secondary address for the bytes
sacmd	=	15		;secondary address for the error channel
cr	=	13
lf	=	10
ctz	=	26		;Ctrl-Z, used to pad a short final record

;page zero
unit	=	16		;Commodore device number, 8 to 30
nmlen	=	17		;bytes currently in cbmnam
rawlen	=	18		;name length before ",S,W" is added
mode	=	19		;0 = unit only, 1 = unit and a name
tailn	=	20		;length of the command tail
taili	=	21		;index into the tail, first character is 1
sawdot	=	22		;nonzero after the DOS/65 name's first dot
dosix	=	23		;next free slot in the 11-character name
dosopen	=	24		;nonzero when the DOS/65 file is open
made	=	25		;nonzero when this run created the destination
stcode	=	26		;0 = "00", 1 = "62" not found, 2 = other
reclen	=	27		;bytes gathered into the current record
blklo	=	28		;directory block count, low byte
blkhi	=	29		;directory block count, high byte
lead	=	30		;nonzero once a decimal digit has been printed
hold	=	31		;a saved index or a saved byte
ndig	=	32		;how many digits the unit number had
idx	=	33		;a loop count that has to survive a kernel call
tmp	=	34
tmp2	=	35

;---- command tail -----------------------------------------------
;A = 0 to read only the unit, A = 1 to read the unit and a name.
;Carry set means a message has already been printed.
;The command module folds the whole line to upper case before
;the program starts, so the name arrives in capitals.
parse	sta	mode
	lda	#0
	sta	made
	sta	dosopen
	lda	dflbuf		;length of the text after the name
	sta	tailn
	lda	#1		;the text starts one byte past the length
	sta	taili
	jsr	skpspc
	jsr	rdunit
	bcc	par1
	cmp	#0		;no number at all
	beq	pcmd
	jmp	pdev
par1	lda	mode
	bne	par2
	jsr	skpspc		;a directory allows nothing after the unit
	jsr	nxtchr
	bcs	pdone
	jmp	pcmd
par2	jsr	skpspc
	jsr	rdname
	bcs	pnam
pdone	clc
	rts
pcmd	lda	#<mcmd
	ldy	#>mcmd
	jmp	perr
pdev	lda	#<mbaddev
	ldy	#>mbaddev
	jmp	perr
pnam	lda	#<mname
	ldy	#>mname
perr	jsr	sayln
	sec
	rts

;Next tail character in A. Carry set when the tail is finished.
nxtchr	lda	taili
	cmp	tailn
	bcc	nx1
	beq	nx1		;the last character is still waiting
	sec
	rts
nx1	ldy	taili
	lda	dflbuf,y
	inc	taili
	clc
	rts

;Step over spaces. A character that is not a space is put back.
;Carry set means the tail ended while the spaces were skipped.
skpspc	jsr	nxtchr
	bcs	skend
	cmp	#' '
	beq	skpspc
	dec	taili
	clc
skend	rts

;Unit number. One or two digits, then not a digit.
;8 to 30 is accepted. A third digit is rejected so the multiply
;cannot overflow a byte. Carry set: A = 0 if there was no number,
;A = 1 if the number was out of range.
rdunit	lda	#0
	sta	unit
	sta	ndig
ru1	jsr	nxtchr
	bcs	ruend
	cmp	#'0'
	bcc	ruput
	cmp	#'9'+1
	bcs	ruput
	pha			;the digit itself, wanted after the *10
	inc	ndig
	lda	ndig
	cmp	#3
	bcs	ruhi
	lda	unit
	asl
	sta	tmp		;unit * 2
	lda	unit
	asl
	asl
	asl			;unit * 8
	clc
	adc	tmp
	sta	unit
	pla
	sec
	sbc	#'0'
	clc
	adc	unit
	sta	unit
	jmp	ru1
ruput	dec	taili		;the separator belongs to the next field
ruend	lda	ndig
	beq	runone
	lda	unit
	cmp	#8
	bcc	rurange
	cmp	#31		;30 is the last unit accepted
	bcs	rurange
	clc
	rts
runone	lda	#0
	sec
	rts
ruhi	pla			;drop the third digit
rurange	lda	#1
	sec
	rts

;Commodore name. Spaces inside the name stay, trailing spaces go,
;and anything past 16 characters after that trim is an error.
;Comma, star, and question mark are rejected so the ",S,W" added
;later cannot be doubled and a wildcard cannot match several files.
rdname	lda	#0
	sta	nmlen
rn1	jsr	nxtchr
	bcs	rnend
	cmp	#','
	beq	rnbad
	cmp	#':'
	beq	rnbad		;would change the scratch command
	cmp	#'*'
	beq	rnbad
	cmp	#'?'
	beq	rnbad
	ldy	nmlen
	cmp	#' '
	beq	rnsp
	cpy	#16
	bcs	rnbad		;a 17th real character
	sta	cbmnam,y
	inc	nmlen
	jmp	rn1
rnsp	cpy	#16
	bcs	rn1		;spaces past 16 are only the trailing ones
	sta	cbmnam,y
	inc	nmlen
	jmp	rn1
rnend	ldy	nmlen
	beq	rnbad
rntr	dey
	bmi	rnbad		;the name was nothing but spaces
	lda	cbmnam,y
	cmp	#' '
	beq	rntr
	iny
	sty	nmlen
	sty	rawlen		;remember it before ",S,W" is added
	clc
	rts
rnbad	sec
	rts

;Build the DOS/65 file control block from the Commodore name.
;Spaces are dropped. At most 8 characters are kept before the
;first dot and 3 after it. MY LONG FILE.BAS becomes MYLONGFI.BAS.
;Carry set, and BAD FILE NAME already printed, when those 8
;characters are all spaces.
chop	ldx	#32
	lda	#0
zfcb	sta	dosfcb,x		;drive 0 means the current drive
	dex
	bpl	zfcb
	ldx	#10
	lda	#' '
zsp	sta	dosfcb+1,x		;11 blanks: 8 of name and 3 of type
	dex
	bpl	zsp
	lda	#0
	sta	sawdot
	sta	dosix
	tay			;Y walks the Commodore name. No kernel calls here.
ch1	cpy	nmlen
	bcs	chend
	lda	cbmnam,y
	iny
	cmp	#' '
	beq	ch1		;the DOS/65 name has no spaces
	cmp	#'.'
	bne	chput
	lda	sawdot
	bne	chdot		;a later dot is an ordinary character
	inc	sawdot
	lda	#8		;the type starts at character 9
	sta	dosix
	jmp	ch1
chdot	lda	#'.'
chput	ldx	dosix
	cpx	#8
	bcc	chsto
	ldx	sawdot
	beq	ch1		;the 8-character name is full, wait for the dot
	ldx	dosix
	cpx	#11
	bcs	ch1		;the type is full too
chsto	ldx	dosix
	sta	dosfcb+1,x
	inc	dosix
	jmp	ch1
chend	ldx	#7
	lda	#' '
chem	cmp	dosfcb+1,x		;the 8-character name, not the type
	bne	chok
	dex
	bpl	chem
	lda	#<mname
	ldy	#>mname
	jsr	sayln
	sec
	rts
chok	clc
	rts

;---- DOS/65 file ------------------------------------------------
;Every call passes the file control block again. PEM only keeps
;the address while the call is running.
dosadr	lda	#<dosfcb
	ldy	#>dosfcb
	rts

;Clear the extent and the counters, leave the name. Used before
;a file is created, so a failed open earlier cannot leak into it.
dosnew	lda	#0
	ldy	#12
dn1	sta	dosfcb,y
	iny
	cpy	#33
	bne	dn1
	rts

opndos	jsr	dosadr
	ldx	#openf
	jmp	pem		;A = 255 when the name is not there

clsdos	jsr	dosadr
	ldx	#closef
	jmp	pem

rddos	jsr	dosadr
	ldx	#readf
	jmp	pem		;A = 0 ok, 1 end, 2 unwritten record

wrdos	jsr	dosadr
	ldx	#writf
	jmp	pem		;A nonzero means the disk is full

mkdos	jsr	dosadr
	ldx	#makef
	jmp	pem		;A = 255 when there is no room

dldos	jsr	dosadr
	ldx	#dltf
	jmp	pem

;Close the DOS/65 file if this run opened it.
doshut	lda	dosopen
	beq	doshx
	jsr	clsdos
	lda	#0
	sta	dosopen
doshx	rts

setrec	lda	#<recbuf
	ldy	#>recbuf
	ldx	#dmaf
	jmp	pem

;---- console ----------------------------------------------------
;PEM function 9 prints until the dollar sign. The line ending is
;sent on its own, the same way the other utilities do it.
say	ldx	#strout
	jsr	pem
	rts

sayln	jsr	say
	jmp	crlf

crlf	lda	#cr
	jsr	cout
	lda	#lf
cout	ldx	#conout
	jmp	pem

;---- Commodore file ---------------------------------------------
;Open the error channel. The name is empty, so the drive is not
;given a command. Carry is the kernel's carry.
cbmcmd	lda	#lfcmd
	ldx	unit
	ldy	#sacmd
	jsr	setlfs
	lda	#0
	jsr	setnam
	jmp	open

;Open cbmnam. A is the secondary address on entry:
;3 for file bytes, 0 for the directory.
cbmopen	sta	tmp
	lda	#lfdat
	ldx	unit
	ldy	tmp
	jsr	setlfs
	lda	nmlen
	ldx	#<cbmnam
	ldy	#>cbmnam
	jsr	setnam
	jmp	open

;Close logical files 3 and 4 and restore the keyboard and screen.
;Files 2 and 15 belong to the SIM and are left open.
clchn	lda	#lfdat
	jsr	close
	lda	#lfcmd
	jsr	close
	jmp	clrch

;Read the error channel into stbuf.
;stcode is 0 when the text starts with 00, 1 when it starts with
;62 (the drive's "file not found"), and 2 for any other text.
;Carry is clear only for 00. The channel is released before return.
cbmstat	ldx	#lfcmd
	jsr	chkin
	bcs	sterr
	lda	#0
	sta	idx
st1	jsr	basin
	sta	tmp
	jsr	readst
	and	#$82		;device gone or the byte timed out
	bne	sterr
	ldy	idx
	lda	tmp
	cmp	#cr
	beq	st2
	cmp	#0
	beq	st2
	sta	stbuf,y
	inc	idx
	lda	idx
	cmp	#46
	bcc	st1
st2	ldy	idx
	lda	#0
	sta	stbuf,y
	jsr	clrch
	lda	stbuf
	cmp	#'0'
	bne	st62
	lda	stbuf+1
	cmp	#'0'
	bne	st62
	lda	#0
	sta	stcode
	clc
	rts
st62	lda	stbuf
	cmp	#'6'
	bne	stbad
	lda	stbuf+1
	cmp	#'2'
	bne	stbad
	lda	#1
	sta	stcode
	sec
	rts
stbad	lda	#2
	sta	stcode
	sec
	rts
sterr	lda	#0
	sta	stbuf
	lda	#2
	sta	stcode
	jsr	clrch
	sec
	rts

;Print the error text. PETSCII bit 7 is cleared, so a shifted
;space becomes a space. Carry set means there was no text.
prstat	lda	stbuf
	bne	pr1
	sec
	rts
pr1	ldy	#0
pr2	lda	stbuf,y
	beq	pr3
	iny
	sty	hold		;cout does not keep Y
	and	#$7f
	cmp	#' '
	bcc	pr4
	jsr	cout
pr4	ldy	hold
	jmp	pr2
pr3	jsr	crlf
	clc
	rts

;One byte from the Commodore file.
;Carry clear: the byte is in A.
;Carry set and A = 0: end of file. The carriage return that came
;with that status is not file data, so it is discarded.
;Carry set and A nonzero: the status itself, a real fault.
;Uses tmp and tmp2. Does not use hold, reclen, or the block count.
cbmin	jsr	basin
	sta	tmp
	jsr	readst
	sta	tmp2
	and	#$bf		;ignore the end-of-file bit for a moment
	bne	cinbad
	lda	tmp2
	and	#$40
	bne	cineof
	lda	tmp
	clc
	rts
cineof	lda	#0
	sec
	rts
cinbad	lda	tmp2
	sec
	rts

;Write A to the Commodore file. Carry set when the status is
;anything but zero. The output channel has to be selected first,
;and again after any PEM call, because PEM restores the screen.
cbmout	jsr	bsout
	jsr	readst
	beq	cook
	sec
	rts
cook	clc
	rts

;Select the data file. Carry is the kernel's carry.
chdata	ldx	#lfdat
	jmp	chkin

ckdata	ldx	#lfdat
	jmp	ckout

;Remove the sequential file this run just created. The error
;channel is still open. rawlen is the name without ",S,W".
;Drive 0 is the drive inside a 1541 or a 1581.
scratch	lda	rawlen		;an empty name must not become S0:
	beq	scrx
	ldx	#lfcmd
	jsr	ckout
	bcs	scrx
	lda	#'S'
	jsr	bsout
	lda	#'0'
	jsr	bsout
	lda	#':'
	jsr	bsout
	lda	#0
	sta	idx		;bsout does not keep Y
sc1	ldy	idx
	cpy	rawlen
	bcs	sc2
	lda	cbmnam,y
	jsr	bsout
	inc	idx
	jmp	sc1
sc2	lda	#cr
	jsr	bsout
	jsr	clrch
	jsr	cbmstat		;the reply is not the caller's error
scrx	rts

;---- decimal ----------------------------------------------------
;Print blklo, blkhi with no leading spaces. 0 is printed "0".
;A directory line from the drive already contains the spaces that
;line the names up, counted for a block count printed as digits
;only. Padding the count again shifts the short numbers right.
;The value is consumed.
prblk	lda	#0
	sta	lead
	ldy	#0
pcol	ldx	#0
psub	inx
	sec
	lda	blklo
	sbc	p10lo,y
	sta	tmp
	lda	blkhi
	sbc	p10hi,y
	bcc	pgot		;one subtract too far
	sta	blkhi
	lda	tmp
	sta	blklo
	jmp	psub
pgot	dex			;the digit that actually fitted
	txa
	bne	pnz
	lda	lead
	bne	pzero		;a zero after a real digit is printed
	jmp	pskip		;a leading zero is not printed
pzero	lda	#'0'
	jmp	pout
pnz	lda	#1
	sta	lead
	txa
	ora	#'0'
pout	sty	hold
	jsr	cout
	ldy	hold
pskip	iny
	cpy	#4
	bcc	pcol
	lda	blklo		;whatever is left is the ones digit
	ora	#'0'
	jmp	cout

p10lo	.byte	$10,$e8,$64,$0a	;10000, 1000, 100, 10
p10hi	.byte	$27,$03,$00,$00

;A as a decimal number from 0 to 99. Used for the unit.
prbyte	ldx	#'0'
pb1	cmp	#10
	bcc	pb2
	inx
	sec
	sbc	#10
	jmp	pb1
pb2	pha
	cpx	#'0'
	beq	pb3		;no tens digit
	txa
	jsr	cout
pb3	pla
	ora	#'0'
	jmp	cout

mcmd	.byte	'BAD COMMAND$'
mbaddev	.byte	'BAD DEVICE$'
mname	.byte	'BAD FILE NAME$'

;The file control block is 33 bytes: drive, 8 of name, 3 of type,
;then the extent and the record counters through byte 32.
;The Commodore name has room for 16 characters plus ",S,W".
dosfcb
	*=	*+33
cbmnam
	*=	*+20
recbuf
	*=	*+128
stbuf
	*=	*+48
