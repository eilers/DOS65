;CBMDIR
;List the directory of a Commodore disk.
;
;	CBMDIR <unit>
;
;The whole directory is printed. There is no name pattern. The
;unit is the Commodore device number, normally 8 or 9, and it is
;not a DOS/65 drive letter. Drive A is unit 8 and drive B is unit 9.
;Use the unit DOS/65 is not logged into: that drive's command
;channel is already open.
;
;The listing is the drive's own directory. Each line is a block
;count and then the text the drive sent, which includes the name
;and the file type. Nothing is written to either disk.

.CPU	6502

tea	=	$200
	.STORE tea,ende-tea,"disk/CBMDIR.COM"
	*=	tea
	jmp	main
	.INCLUDE "../cbmkern.asm"

main	cld
	lda	#0			;the unit, and nothing after it
	jsr	parse
	bcc	m1
	rts
m1	jsr	cbmcmd
	bcc	dcmd
	jmp	nodev
dcmd	lda	#'$'		;the drive's name for its directory
	sta	cbmnam
	lda	#1
	sta	nmlen
	lda	#0		;secondary address 0 is the directory
	jsr	cbmopen
	bcc	mrd
	jmp	nodev
mrd	jsr	cbmstat
	bcc	mlist
	jsr	prstat
	bcs	cerr
	jmp	done
cerr	lda	#<mdrive
	ldy	#>mdrive
	jsr	sayln
	jmp	done
mlist	lda	#<mhead
	ldy	#>mhead
	jsr	say
	lda	unit
	jsr	prbyte
	jsr	crlf
	jsr	chdata
	bcs	dio
	jsr	cbmin		;the two-byte load address is not a line
	bcs	dend
	jsr	cbmin
	bcs	dend
mline	jsr	cbmin		;link to the next BASIC line
	bcs	dend
	sta	hold		;cbmin reuses tmp, so the low byte lives here
	jsr	cbmin
	bcs	dend
	ora	hold
	beq	dend		;a link of 0,0 is the end of the listing
	jsr	cbmin
	bcs	dend
	sta	blklo
	jsr	cbmin
	bcs	dend
	sta	blkhi
	lda	#0
	sta	reclen
mtext	jsr	cbmin
	bcs	mtextend
	cmp	#0		;the line ends with a zero, not a return
	beq	mshow
	and	#$7f		;PETSCII: clear the shifted-space bit
	cmp	#' '
	bcc	mtext
	ldy	reclen
	cpy	#127
	bcs	mtext		;keep reading so the next line stays aligned
	sta	recbuf,y
	inc	reclen
	jmp	mtext
mtextend
	cmp	#0
	bne	dio		;a fault, not a clean end
	jsr	mprint		;show the short line, then stop
	jmp	dend
mshow	jsr	mprint
	jsr	chdata		;back to the directory for the next line
	bcc	mline
dio	jsr	clrch
	jsr	cbmstat
	jsr	prstat
	bcc	done
	lda	#<mdrive
	ldy	#>mdrive
	jsr	sayln
	jmp	done
dend	jsr	clrch
done	jsr	clchn
	rts

nodev	cmp	#5
	bne	nopen
	lda	#<mabsent
	ldy	#>mabsent
	jmp	nmsg
nopen	lda	#<mopen
	ldy	#>mopen
nmsg	jsr	sayln
	jmp	done

;Print one directory line. The input channel is released first so
;that console output cannot read the next byte of the directory.
mprint	jsr	clrch
	jsr	prblk
	lda	#' '		;one space, as a Commodore listing prints it
	jsr	cout
	lda	#0
	sta	idx
mp1	lda	idx
	cmp	reclen
	bcs	mp2
	ldy	idx
	lda	recbuf,y
	jsr	cout
	inc	idx
	jmp	mp1
mp2	jmp	crlf

mhead	.byte	'CBMDIR UNIT $'
mabsent	.byte	'DEVICE NOT PRESENT$'
mopen	.byte	'CANNOT OPEN$'
mdrive	.byte	'DRIVE ERROR$'

ende
