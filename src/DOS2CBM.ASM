;DOS2CBM
;Copy one file from the current DOS/65 drive onto a Commodore disk.
;
;	DOS2CBM <unit> <filename>
;
;The file that is read is the one on the drive at the prompt. A>
;is Commodore unit 8 and B> is unit 9. The number in the command
;is the other disk, the Commodore one, and it has to be a different
;unit: DOS/65 is already using the command channel of its own drive.
;
;The Console Command Module folds the line to upper case first, so
;the name is stored in capitals. On the Commodore disk the spaces
;stay and 16 characters is the limit. On this side the spaces are
;removed, 8 characters before the dot and 3 after. MY LONG FILE.BAS
;is MYLONGFI.BAS here and MY LONG FILE.BAS on the Commodore disk.
;
;Every byte of every 128-byte DOS/65 record is written, including a
;program file's load address, so the new file ends on a 128-byte
;boundary. It is always a sequential file. A file that is already
;there is left alone. If the copy fails, the new file is removed
;and the DOS/65 original is not.

.CPU	6502

tea	=	$200
	.STORE tea,ende-tea,"disk/DOS2CBM.COM"
	*=	tea
	jmp	main			;DOS/65 enters at $200
	.INCLUDE "../cbmkern.asm"

main	cld
	lda	#1			;unit and a file name
	jsr	parse
	bcc	m1
	rts
m1	jsr	chop
	bcc	m2
	rts			;BAD FILE NAME already printed
m2	jsr	opndos
	cmp	#$ff
	bne	mhave
	lda	#<mnof
	ldy	#>mnof
	jsr	sayln
	rts
mhave	lda	#1
	sta	dosopen		;the source has to be closed on the way out
	jsr	cbmcmd
	bcc	dcmd
	jmp	nodev
dcmd	lda	#sadata		;read it first, to see if the name is taken
	jsr	cbmopen
	bcc	mrd
	jmp	nodev
mrd	jsr	cbmstat
	lda	stcode
	beq	mtaken		;00: the Commodore file is already there
	cmp	#1
	beq	mnew		;62: not there, so it may be created
	jsr	prstat
	bcs	mrd2
	jmp	bad
mrd2	lda	#<mdrive
	ldy	#>mdrive
	jsr	sayln
	jmp	bad
mtaken	lda	#<mexists
	ldy	#>mexists
	jsr	sayln
	jmp	bad
mnew	lda	#lfdat
	jsr	close		;the read open, before the write open
	jsr	clrch
	jsr	addseq
	lda	#sadata
	jsr	cbmopen
	bcc	mwrop
	jmp	nodev
mwrop	jsr	cbmstat
	bcc	mgo		;00: the sequential file was created
	lda	stbuf		;63 means the old file is still there
	cmp	#'6'
	bne	mnewf
	lda	stbuf+1
	cmp	#'3'
	beq	mkeep
mnewf	lda	#1		;a partial file was created, so remove it
	sta	made
mkeep	jsr	prstat
	bcs	mk2
	jmp	bad
mk2	lda	#<mdrive
	ldy	#>mdrive
	jsr	sayln
	jmp	bad
mgo	lda	#1
	sta	made		;from here on a failure removes this new file
	jsr	copyout
	bcs	mio
	lda	#lfdat
	jsr	close		;finish the sequential file
	jsr	clrch
	jsr	cbmstat		;the drive reports a full disk here
	bcc	good
	jsr	prstat
	bcs	mfin
	jmp	bad
mfin	lda	#<mdrive
	ldy	#>mdrive
	jsr	sayln
	jmp	bad
mio	jsr	cbmstat
	jsr	prstat
	bcs	mio2
	jmp	bad
mio2	lda	#<mdrive
	ldy	#>mdrive
	jsr	sayln
bad	lda	#lfdat
	jsr	close
	jsr	clrch
	lda	made
	beq	bcl
	jsr	scratch		;only the file this run created
bcl	jsr	clchn
	jsr	doshut		;the DOS/65 original is closed, not deleted
	rts
good	jsr	clchn
	jsr	doshut
	lda	#<mcopied
	ldy	#>mcopied
	jsr	sayln
	rts

;OPEN failed. 5 is the kernel's "device not present".
nodev	cmp	#5
	bne	nopen
	lda	#<mabsent
	ldy	#>mabsent
	jmp	nmsg
nopen	lda	#<mopen
	ldy	#>mopen
nmsg	jsr	sayln
	jmp	bad

;Append the sequential-write suffix. rawlen still names the file
;for the scratch command if the copy later fails.
addseq	ldy	rawlen
	lda	#','
	sta	cbmnam,y
	iny
	lda	#'S'
	sta	cbmnam,y
	iny
	lda	#','
	sta	cbmnam,y
	iny
	lda	#'W'
	sta	cbmnam,y
	iny
	sty	nmlen
	rts

;PEM read returns 0 for a real record, 1 at the end, and 2 for an
;unwritten record. Both 1 and 2 end the copy, and the record that
;failed is not written. Every accepted record is 128 bytes.
copyout	jsr	setrec
	jsr	rddos
	cmp	#0
	bne	codone
	jsr	ckdata
	bcs	cobad
	lda	#0
	sta	idx
co1	ldy	idx
	lda	recbuf,y
	jsr	cbmout
	bcs	cobad
	inc	idx
	lda	idx
	cmp	#128
	bne	co1
	jsr	clrch		;PEM wants the screen back on the next read
	jmp	copyout
codone	clc
	rts
cobad	sec
	rts

mnof	.byte	'FILE NOT FOUND$'
mexists	.byte	'FILE EXISTS$'
mabsent	.byte	'DEVICE NOT PRESENT$'
mopen	.byte	'CANNOT OPEN$'
mdrive	.byte	'DRIVE ERROR$'
mcopied	.byte	'COPIED$'

ende
