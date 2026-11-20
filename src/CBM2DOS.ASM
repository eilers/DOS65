;CBM2DOS
;Copy one file from a Commodore disk onto the current DOS/65 drive.
;
;	CBM2DOS <unit> <filename>
;
;The number is the Commodore unit. The file is written to the drive
;at the prompt, and that unit has to be a different one, because
;DOS/65 is already using the command channel of its own drive.
;
;The name is folded to upper case by the command module. Spaces stay
;on the Commodore side and are removed on this side, 8 characters
;before the dot and 3 after. The bytes are copied unchanged, so a
;program file's two-byte load address is still the first two bytes.
;The new file is an ordinary DOS/65 file. A short last record is
;filled with Ctrl-Z ($1A). A file that is already on this drive is
;left alone. If the copy fails, the new DOS/65 file is removed and
;the Commodore original is not.
;
;An empty Commodore file is created here and no record is written.
;A program file comes back as a sequential file if it is later
;copied the other way: this program does not choose a Commodore type.

.CPU	6502

tea	=	$200
	.STORE tea,ende-tea,"disk/CBM2DOS.COM"
	*=	tea
	jmp	main
	.INCLUDE "../cbmkern.asm"

main	cld
	lda	#1
	jsr	parse
	bcc	m1
	rts
m1	jsr	chop
	bcc	m2
	rts
m2	jsr	opndos		;refuse to replace a file that is already here
	cmp	#$ff
	beq	mfree
	jsr	clsdos
	lda	#<mexists
	ldy	#>mexists
	jsr	sayln
	rts
mfree	jsr	cbmcmd
	bcc	dcmd
	jmp	nodev
dcmd	lda	#sadata
	jsr	cbmopen
	bcc	mrd
	jmp	nodev
mrd	jsr	cbmstat
	lda	stcode
	beq	mgot		;00: the Commodore file is there
	cmp	#1
	beq	mnf		;62: nothing of that name
	jsr	prstat
	bcc	bad
	lda	#<mdrive
	ldy	#>mdrive
	jsr	sayln
	jmp	bad
mnf	lda	#<mnof
	ldy	#>mnof
	jsr	sayln
	jmp	bad
mgot	jsr	dosnew		;do not inherit the failed open's counters
	jsr	mkdos
	cmp	#$ff
	bne	mmade
	lda	#<mroom
	ldy	#>mroom
	jsr	sayln
	jmp	bad
mmade	lda	#1
	sta	made		;a failure from here removes this new file
	jsr	opndos
	cmp	#$ff
	bne	mopen
	jmp	bad
mopen	lda	#1
	sta	dosopen
	jsr	copyin
	bcs	mhow
	jsr	cbmstat
	bcc	good
	jsr	prstat
	bcc	bad
	lda	#<mdrive
	ldy	#>mdrive
	jsr	sayln
	jmp	bad
mhow	cmp	#2
	bne	mio
	lda	#<mfull
	ldy	#>mfull
	jsr	sayln
	jmp	bad
mio	jsr	cbmstat
	jsr	prstat
	bcc	bad
	lda	#<mdrive
	ldy	#>mdrive
	jsr	sayln
bad	jsr	clchn
	lda	dosopen
	beq	b2
	jsr	clsdos
	lda	#0
	sta	dosopen
b2	lda	made
	beq	b3
	jsr	dldos		;the Commodore file is not touched
b3	rts
good	jsr	clchn
	jsr	doshut
	lda	#<mcopied
	ldy	#>mcopied
	jsr	sayln
	rts

nodev	cmp	#5
	bne	nopen
	lda	#<mabsent
	ldy	#>mabsent
	jmp	nmsg
nopen	lda	#<mcant
	ldy	#>mcant
nmsg	jsr	sayln
	jmp	bad

;Read until end of file. A full 128 bytes is written at once.
;The last short record is filled with Ctrl-Z and then written.
;No bytes at all means the created file gets no record.
;Carry clear on a clean end. Carry set, A = 2 when the DOS/65
;disk is full, A = 1 when the Commodore read failed.
copyin	jsr	chdata
	bcs	cibad
	lda	#0
	sta	reclen
ci1	jsr	cbmin
	bcs	ciend
	ldy	reclen
	sta	recbuf,y
	inc	reclen
	lda	reclen
	cmp	#128
	bne	ci1
	jsr	clrch
	jsr	setrec
	jsr	wrdos
	cmp	#0
	bne	cifull
	jsr	chdata		;PEM took the input channel back
	bcs	cibad
	lda	#0
	sta	reclen
	jmp	ci1
ciend	cmp	#0
	bne	cibad		;A still holds the status from cbmin
	lda	reclen
	beq	cidone		;empty file, or an exact multiple of 128
	lda	#ctz
	ldy	reclen
cipad	sta	recbuf,y
	iny
	cpy	#128
	bne	cipad
	jsr	clrch
	jsr	setrec
	jsr	wrdos
	cmp	#0
	bne	cifull
cidone	clc
	rts
cibad	lda	#1
	sec
	rts
cifull	lda	#2
	sec
	rts

mnof	.byte	'FILE NOT FOUND$'
mexists	.byte	'FILE EXISTS$'
mroom	.byte	'NO ROOM$'
mfull	.byte	'DISK FULL$'
mabsent	.byte	'DEVICE NOT PRESENT$'
mcant	.byte	'CANNOT OPEN$'
mdrive	.byte	'DRIVE ERROR$'
mcopied	.byte	'COPIED$'

ende
