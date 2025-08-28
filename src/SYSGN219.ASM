-;sysgen
;version 2.19-S
;released:	30 november 1985 (2.10)
;last revised:
;	2 may 1996 (2.11)
;		eliminated word mode for 1024 blocks
;		made extent a single byte
;	3 may 1996 (2.12)
;		added initial exm related code
;	11 may 1996 (2.13)
;		added use of exm in getblk
;		added code to set exm & cexm1f
;		corrected errors
;	19 may 1996 (2.14)
;		changed ccm ren to "to from" syntax
;		allowed _ in file names
;	13 march 2008 (2.15)
;		reformatted for TASM & ASM210+
;		eliminated dependence on "IBM" format
;		  by reading first sector # using SIM+51
;		  TRANSLATE code. If translate
;		  does not have first physical sector in first
;		  position this approach may not work.
;		  SIM can also perform no translation at all.
;		  Also assumes BOOT & SIM both know correct
;		  starting sector for cold & warm boot. It
;		  should work regardless of physical sector
;		  size as long as existing SIM is configured
;		  correctly for destination drive. BOOT
;		  must correctly handle sectors > 128 bytes
;		  as must WARM BOOT in SIM.
;		  In any case BOOT and WARM BOOT must
;		  read sectors in sequential order, i.e.,
;		  no interleave.
;	17 december 2009 (2.16)
;		added page zero start variable - pzstrt
;		change page zero start & switch to use pzstrt
;	1 march 2011 (2.17)
;		change opening message
;	6 March 2015 (2.18)
;		corrected calculations associated with writing image
;	19 August 2015 (2.19)
;		corrected file name parsing
;this program contains the complete dos/65 operating
;system except for the boot and sim.
;when used by the system operator this program
;provides the capability to construct a new
;operating system including the users boot and sim.
;the system is relocated to fit the memory size
;specified by the user and is written onto
;the system tracks of the specified drive.
;improvements over version 2.0 include:
;	use of "from to" syntax for ren
;	addition of go command
;	addition of load command
;	ability to enter numbers as decimal or hex
;	address parameter added to save
;	error checking in sysgen (write)
;	write type for deblocking added
;	page zero 0 & 1 not used (see also pzstrt use)
;	allow _ in file names
;base addresses and definitions
	.INCLUDE "../constants.asm"
paglim	=	((ccm+ccmlng+pemlng)/256)+1	;allow one page for sim
;zero page for setup
	*=	pzstrt
trknum				;current track
	*=	*+2
dcbadd				;dcb address
	*=	*+2
nmsstr				;number system tracks
	*=	*+2
nsectr				;number sectors per track
	*=	*+2
ttlsec				;total sectors to write
	*=	*+1
trkcnt				;track count for image write
	*=	*+2
size				;ascii size
	*=	*+2
lokim				;low kim limit
	*=	*+2
hikim				;high kim limit
	*=	*+2
offset				;relocation offset
	*=	*+2
kimcnt				;kim counter
	*=	*+1
pointr				;pointer
	*=	*+2
lengt				;inst length
	*=	*+1
point				;relocate pointer
	*=	*+2
adjust				;relocate distance
	*=	*+2
kimpnt				;kim file index
	*=	*+1
savex				;save for x
	*=	*+1
savey				;save for y
	*=	*+1
number				;input pack buffer
	*=	*+2
dstdrv				;destination drive
	*=	*+1
defalt				;default drive
	*=	*+1
seccnt				;sector count
	*=	*+2
secnum				;sector number
	*=	*+2
curccm				;start of current ccm
	*=	*+2
simlng				;length of sim
	*=	*+2
room				;memory needed for sysgen
	*=	*+2
stksav				;save stack register
	*=	*+1
frstsc				;first sector number of disk
	*=	*+1
lastzp

	.STORE Start,Ende-Start,"sysgn219.com"
Start	=	tea

;main program
	*=	Start		;start of tea
	jmp	sysgen		;jump to main
;copyright notice
	.byte	"COPYRIGHT (C) 2009 - "
	.byte	"RICHARD A. LEARY"
sysgen	ldy	btejmp+2	;get sim page from boot vector
	sty	jshome+2
	sty	jsseld+2
	sty	jssett+2
	sty	jssets+2
	sty	jssetd+2
	sty	jswrit+4
	sty	jsxlat+2
;initialize
	ldx	#pzstrt		;set start location
	lda	#0		;clear accum
clrzp	sta	$00,x		;clear mem
	inx			;bump index
	cpx	#lastzp		;see if past end
	bne	clrzp		;loop if not
;save stack register for exit
	tsx			;move to x
	stx	stksav		;save it
;calculate current ccm start
	sec			;set carry
	lda	pemjmp+1	;subtract ccm length from pem start
	sbc	#<ccmlng
	sta	curccm
	lda	pemjmp+2
	sbc	#>ccmlng
	sta	curccm+1
	lda	#<opnmsg	;send
	ldy	#>opnmsg	;"opening"
	jsr	wrtmsg		;message
	ldx	#25		;read
	jsr	pemjmp		;default drive
	sta	defalt		;and save
	jsr	gns		;get new size
	jsr	bcdbyt		;pack into byte
	sta	adjust		;and save
;convert xx k to bytes
	ldx	#10		;multiply
m1024	asl	adjust		;by
	rol	adjust+1	;1024
	dex			;to get
	bne	m1024		;size in bytes
;calculate room available for sysgen
	lda	adjust		;get msize
	ldy	adjust+1
	sec			;now subtract ccm image start
	sbc	#<ccm
	sta	room		;and save
	tya
	sbc	#>ccm
	sta	room+1
	lsr	room+1		;divide by two
	ror	room
;get sim length
	lda	#0		;clear size
	sta	size
	sta	size+1
	jsr	gss
	jsr	bcdbyt		;pack into byte
	sta	simlng		;and save
;convert xx pages to bytes
	ldx	#8
m256	asl	simlng		;multiply
	rol	simlng+1
	dex
	bne	m256
;calculate new system length
	clc			;by adding sim length to syslng
	lda	syslng
	adc	simlng
	sta	syslng
	lda	syslng+1
	adc	simlng+1
	sta	syslng+1	;and saving
;calculate new system start
	sec			;subtract
	lda	adjust		;system
	sbc	syslng		;length
	sta	adjust		;from
	lda	adjust+1	;top
	sbc	syslng+1	;limit to
	sta	adjust+1	;get new start
;make sure another sysgen is possible
	lda	room		;see if room
	cmp	syslng		;is >= syslng
	lda	room+1
	sbc	syslng+1
	bcs	rmok		;ok if is
	lda	#<bigmsg	;else send too big message
	ldy	#>bigmsg
	jmp	errext		;and exit
;now calculate relocation distance
rmok	sec			;now
	lda	adjust		;subtract
	sbc	#<ccm		;old start
	sta	adjust		;from new
	lda	adjust+1	;to get
	sbc	#>ccm		;relocation
	sta	adjust+1	;distance
;relocate ccm
	lda	#<ccm		;set
	ldy	#>ccm		;pointer
	sta	point
	sty	point+1
	jsr	strtrl		;relocate it
;then pem
	lda	#<pem		;set
	ldy	#>pem		;pointer
	sta	point
	sty	point+1
	jsr	strtrl		;do it
;get new boot and sim
	jsr	gnbte		;get new boot
	jsr	gnsim		;and sim
;write system to specified drive
wrtdrv	lda	#<crtmsg	;send
	ldy	#>crtmsg	;"dest drive"
	jsr	wrtmsg		;message
	jsr	rinclw		;get answer
	cmp	#'A'		;if less than "A"
	bcc	invd		;try again
	cmp	#'H'+1		;if over "H"
	bcs	invd		;also try again
	and	#%1111		;look at lsbs
	sec			;drop
	sbc	#1		;one
	sta	dstdrv		;and save
	iny			;if
	lda	ctxt,y		;anything else
	bne	invd		;is error
	lda	dstdrv		;get drive
	jsr	jsseld		;and set
	sta	dcbadd		;save dcb address
	sty	dcbadd+1
	ora	dcbadd+1	;see if legal
	bne	vld		;ok if not zero
invd	lda	#<invmsg	;else point to invalid drive message
	ldy	#>invmsg
	jsr	wrtmsg		;send it
	jmp	wrtdrv		;and try again
vld	ldy	#2		;get sectors per track
	lda	(dcbadd),y
	sta	nsectr
	iny
	lda	(dcbadd),y
	sta	nsectr+1
	iny			;get number systems tracks
	lda	(dcbadd),y
	sta	nmsstr
	iny
	lda	(dcbadd),y
	sta	nmsstr+1
;send a logical sector 0 to translate to determine first physical sector
	lda	#0		;low and high to 0
	tay
	jsr	jsxlat		;and translate
;only look at low - assume first is probably 0 or 1
	sta	frstsc		;and save
;calculate actual amount of data to write
	lda	pointr		;see if part
	and	#$7f		;of a sector
	beq	whlsec		;no so ok as is
	lda	pointr		;get again
	and	#$80		;capture mod 128
	clc			;then add 128
	adc	#128
	sta	pointr
	bcc	*+4		;with carry
	inc	pointr+1
whlsec	sec			;calculate actual data length
	lda	pointr
	sbc	#<ccm
	sta	syslng
	lda	pointr+1
	sbc	#>ccm
	sta	syslng+1	;and save
;calculate total sector count
	lda	syslng
	ldx	#7		;divide by 128
d128	lsr	syslng+1
	ror	a
	dex
	bne	d128
	clc			;add one for boot
	adc	#1
	sta	ttlsec
;At this time it is assumed that TTLSEC is valid
;as an 8-bit number. That is reasonable as that
;allows an image length of 255*128 = 32640 bytes.
;There is no circumstance in which a longer image
;makes any sense. We need to save TTLSEC for use
;in the actual image write so to
;calculate number of tracks needed we will use
;TRKCNT as a temp holder of TTLSEC.
	lda	ttlsec		;copy data
	sta	trkcnt
	lda	#0		;including missing
	sta	trkcnt+1	;high byte
	ldx	#0		;use x as counter
tcntl	inx
;do trkcnt - nmsstr --> trkcnt until result 0
;or there is no borrow
	sec
	lda	trkcnt
	sbc	nsectr		;drop by number in track
	sta	trkcnt
	lda	trkcnt+1
	sbc	nsectr+1
	sta	trkcnt+1
;check result if c=0 there was a borrow so x shows the
;number of tracks needed since nsectr > ttlsec. X also
;reflects number of tracks if final result is zero.
	bcc	knowx		;there was a borrow
;Now test for zero result
	lda	trkcnt		;or lower
	ora	trkcnt+1	;and upper
	bne	tcntl		;loop if more
knowx	stx	trkcnt		;set counter
	dex			;drop for compare
	cpx	nmsstr		;compare to avail
	bcs	romerr		;error if too big
	jsr	jshome		;home it
	lda	#<boot		;set pointer
	ldy	#>boot		;to
	sta	pointr		;boot
	sty	pointr+1	;start
wrsysl	jsr	writit		;write a track
	dec	trkcnt		;drop count
	bne	wrsysl		;loop if more
;done - clean up and exit
cupext	jsr	stdfbf		;point back to default
	ldx	stksav		;get stack register
	txs			;and set
	lda	defalt		;get default
	jmp	jsseld		;select it
;room error exit
romerr	lda	#<rommsg	;send not enough track message
	ldy	#>rommsg
errext	jsr	wrtmsg
	jmp	cupext		;clean up and exit
;pack bcd size into byte
bcdbyt	clc			;clear carry
	lda	#0		;and accum
	ldx	#10		;then add high
	adc	size+1		;to accum
	dex			;10
	bne	*-3		;times
	adc	size		;then add low
	rts			;and quit
;jumps to sim routines
;only the low part of the address is shown here - page is captured from
;existing warm boot entry point
;home
jshome	jmp	24
;select drive
jsseld	jmp	27
;set track
jssett	jmp	30
;set sector
jssets	jmp	33
;set dma
jssetd	jmp	36
;translate sectort
jsxlat	jmp	51
;write sector
jswrit	lda	#1		;force immediate write
	jsr	42
	and	#$ff		;check for error
	bne	twrerr		;if so quit
	rts
twrerr	lda	#<wermsg	;point to error msg
	ldy	#>wermsg
	jmp	errext		;and exit
;write nsectr sectors (records) in track but
;use ttlsec as counter to ensure only what must be written
;is actually written to drive.
writit	lda	trknum		;get track number
	ldy	trknum+1
	jsr	jssett		;set it
	inc	trknum		;bump for next
	bne	*+4
	inc	trknum+1
	lda	nsectr		;set counter
	ldy	nsectr+1
	sta	seccnt		;to number sectors in track
	sty	seccnt+1
	lda	frstsc		;from value captured earlier
	ldy	#0		;set starting sector
	sta	secnum		;number (probably 0 or 1)
	sty	secnum+1
wrtslp	lda	secnum		;get sector number
	ldy	secnum+1
	jsr	jssets		;set it
	lda	pointr		;get
	ldy	pointr+1	;pointer
	jsr	jssetd		;set address
	jsr	jswrit		;write sector
	dec	ttlsec		;drop count
	beq	ex00		;done if all written
	clc			;then
	lda	pointr		;bump
	adc	#128		;by
	sta	pointr		;128
	bcc	*+4		;for
	inc	pointr+1	;next
	inc	secnum		;bump sector number
	bne	*+4
	inc	secnum+1
	lda	seccnt
	bne	*+4
	dec	seccnt+1
	dec	seccnt		;drop count
	lda	seccnt
	ora	seccnt+1
	bne	wrtslp		;loop if more
ex00	rts
;get new boot
gnbte	lda	#<btemsg	;send
	ldy	#>btemsg	;"boot name"
	jsr	wrtmsg		;message
	jsr	rinclw		;get response
	jsr	inptfn		;convert to fcb
	bcs	gnberr		;branch if error
	lda	#<boot		;offset
	ldy	#>boot		;is same
	sta	offset		;as boot
	sty	offset+1	;start
	sta	lokim		;as is lower
	sty	lokim+1		;limit
	lda	#<(boot+128)	;set
	ldy	#>(boot+128)	;upper
	sta	hikim		;limit
	sty	hikim+1		;then
	jsr	xqread		;read file
	bcs	gnberr		;branch if error
	rts
gnberr	lda	#<flemsg	;send
	ldy	#>flemsg	;"file error"
	jmp	errext		;message and exit
;get new sim
gnsim	lda	#<simmsg	;send
	ldy	#>simmsg	;"sim name"
	jsr	wrtmsg		;message
	jsr	rinclw		;get input
	jsr	inptfn		;convert to fcb
	bcs	gnsirr		;branch if error
	lda	#<sim		;set lower
	ldy	#>sim		;limit
	sta	lokim		;for
	sty	lokim+1		;load
	lda	curccm		;and
	ldy	curccm+1	;upper
	sta	hikim		;limit
	sty	hikim+1		;for load
	lda	adjust		;get
	ldy	adjust+1	;relocation
	eor	#$ff		;distance
	sta	offset		;and
	tya			;complement
	eor	#$ff		;it
	sta	offset+1	;then
	inc	offset		;bump to
	bne	*+4		;get
	inc	offset+1	;load offset
	jsr	xqread		;read file
	bcs	gnsirr		;branch if error
	rts
gnsirr	jmp	gnberr		;error exit
;relocation routine
; point must be set to first code byte of segment
; to relocate. paglim must be set to
; upper address change limits.
strtrl	ldy	#0		;get opcode
	lda	(point),y	;from memory
	tay			;save in y
	ldx	#7		;search seven
rlloop	tya			;get opcode
	and	table1-1,x	;remove bits
	eor	table2-1,x	;test rest
	beq	gotopc		;if zero a match
	dex			;else try
	bne	rlloop		;next
gotopc	ldy	table3,x	;get length/flag
	bpl	skipby		;no change if positive
	iny			;add one
	bmi	exrelc		;exit if terminator
	iny			;else add one more
	lda	(point),y	;get low
	tax			;save in x
	iny			;then get
	lda	(point),y	;high
	cmp	#<paglim	;if at high limit
	bcs	norelc		;do nothing
	cmp	#>(tea+1)	;if above
	bne	trylow		;lower limit
	cpx	#<(tea+1)	;then
trylow	bcc	norelc		;do nothing
	pha			;else save high
	txa			;add offset
	clc			;to low
	adc	adjust		;and then
	tax			;save
	pla			;get high
	adc	adjust+1	;add again
norelc	sta	(point),y	;put back
	dey			;backup
	txa			;get low
	sta	(point),y	;save
	ldy	#3		;go up three
skipby	inc	point		;add one
	bne	*+4		;with
	inc	point+1		;carry
	dey			;loop if
	bne	skipby		;more
	beq	strtrl		;then start over
exrelc	rts
;relocation tables
table1	.byte	$c,$1f,$d,$87,$1f,$ff,$3
table2	.byte	$c,$19,$8,$0,$10,$20,$3
table3	.byte	2,$ff,$ff,1,1,2,$ff,$fe
;read input and convert lower case to upper
; error if no input or if input is all blanks.
; at exit y is index into ctxt
;         a is character at ctxt,y
rinclw	lda	#<cbuf		;point to
	ldy	#>cbuf		;buffer
	jsr	rdeinp		;read input
	lda	#lf		;send
	jsr	charot		;a lf
	ldy	#0		;clear index
	ldx	clng		;get length
	beq	rdiner		;error if zero
lwrcnv	lda	ctxt,y		;get char
	cmp	#'a'		;if less than a
	bcc	dochg		;is ok
	cmp	#'z'+1		;if over z
	bcs	dochg		;is ok
	and	#%01011111	;else convert
	sta	ctxt,y		;and save
dochg	iny			;bump index
	dex			;drop count
	bne	lwrcnv		;loop if more
	txa			;clear a
	sta	ctxt,y		;insert zero
	tay			;clear index
	jsr	spcskp		;find first non-blank
	beq	rdiner		;error if none
	rts			;else ok
rdiner	lda	#<iermsg	;point to
	ldy	#>iermsg	;input error message
	jsr	wrtmsg		;print it
	jmp	rinclw		;try all over
;check for decimal
; if decimal then c=1 else c=0
chkdec	cmp	#'0'		;if less than "0"
	bcc	*+7		;not number
	cmp	#'9'+1		;if less than "9"+1
	bcc	*+4		;is a number
	clc			;not a number
	rts
	sec			;a number
	rts
;get and save sim length
gss	lda	#<nwsmsg	;send "enter size"
	ldy	#>nwsmsg	;message
	jsr	wrtmsg
gssagn	jsr	rinclw		;get input
	jsr	chkdec		;see if first is decimal
	bcc	gsserr		;error if not
	cmp	#'1'		;if at least 1 is ok
	bcc	gsserr		;else error
	and	#%00001111	;get low nibble
	tax			;save in x
	sta	size+1		;store in high
	iny			;next char
	lda	ctxt,y		;get it
	bne	not1pg		;if not zero more than one
	stx	size		;else set low to old high
	sta	size+1		;and clear high
	rts
not1pg	jsr	chkdec		;see if decimal
	bcc	gsserr		;error if not
	and	#%00001111	;get nibble
	sta	size		;put in low
	iny			;next char
	lda	ctxt,y		;get it
	bne	gsserr		;error if not end
	rts
gsserr	lda	#<iermsg	;send illegal input message
	ldy	#>iermsg
	jsr	wrtmsg
	jmp	gssagn		;and loop
;get and save new memory size
; check for decimal and for 64k>=size>=16k
gns	lda	#<szemsg	;send
	ldy	#>szemsg	;"enter size"
	jsr	wrtmsg		;message
gnsagn	jsr	rinclw		;get input
	jsr	chkdec		;test for decimal
	bcc	gnserr		;error if not
	cmp	#'6'+1		;if over "6"
	bcs	gnserr		;is error
	cmp	#'0'		;if "0"
	beq	gnserr		;is error
	tax			;save in x
	and	#%00001111	;get low nibble only
	sta	size+1		;else save
	iny			;move to next
	lda	ctxt,y		;get char
	jsr	chkdec		;test it also
	bcc	gnserr		;error if not decimal
	cpx	#'1'		;if not one
	bne	gns20		;is 20 or more
	cmp	#'6'		;but if low under 6
	bcc	gnserr		;is an error
	bcs	gnshi		;else is ok (17 to 19)
gns20	cpx	#'6'		;if high not 6
	bne	gnshi		;is ok (20 to 59)
	cmp	#'4'+1		;if low over 4
	bcs	gnserr		;is error
gnshi	and	#%00001111	;get low nibble
	sta	size		;else ok so save low
	iny			;look past number
	lda	ctxt,y		;get char
	bne	gnserr		;error if not null
	rts			;else ok
gnserr	lda	#<iermsg	;send
	ldy	#>iermsg	;"illegal input"
	jsr	wrtmsg		;message
	jmp	gnsagn		;try again
;input file designator
; at input y must be set to first non-blank of field
inptfn	ldx	#11		;fill
	lda	#' '		;name
n01	sta	dflfcb,x	;and
	dex			;type
	bne	n01		;with spaces
	inx			;set index to one
	lda	ctxt,y		;get first char
	and	#%00001111	;convert to number
	sta	dflfcb		;set automatic
	iny			;point to next
	lda	ctxt,y		;get char
	cmp	#':'		;if : then
	beq	getnme		;then continue
	dey			;else backup
	dey			;two places
	lda	#0		;then clear
	sta	dflfcb		;automatic
getnme	iny			;go to next
gtmrnm	lda	ctxt,y		;get char
	beq	endall		;over if none
	cmp	#'.'		;see if name - type seperator
	bne	notdot		;if not test legal
e01	iny			;popint past '.'
	lda	ctxt,y		;get char
	ldx	#9		;point to type field
	bne	endall		;and done
notdot	jsr	lgltst		;make sure its legal
	beq	inperr		;if not error
	sta	dflfcb,x	;else put in fcb
	iny			;point to
	inx			;next positions
	cpx	#9		;if not too big
	bne	gtmrnm		;get more
	lda	ctxt,y		;get input
	beq	endall		;ok if no type field
	cmp	#'.'		;see if separator
	beq	e01		;ok if is
	bne	inperr		;then error
endall	dex			;and if no
	beq	inperr		;input is error
	clc			;no error
	rts			;else return
inperr	sec			;error
	rts
;read kim file
xqread	lda	#0		;clear
	ldx	#32		;fcb
zerfcb	sta	dflfcb,x	;except
	dex			;for name
	cpx	#11		;and type
	bne	zerfcb		;and drive
	ldx	#2		;set to
typset	lda	kimtyp,x	;move kim
	sta	dflfcb+9,x	;type to fcb
	dex			;count down
	bpl	typset		;and loop until done
	jsr	opndfl		;try to open
	bpl	*+5		;got it
	jmp	xqrerr		;else error
	lda	#128		;set pointer
	sta	kimpnt		;to illegal
kimlop	jsr	getchr		;get char
	bcc	*+5		;continue if ok
	jmp	xqrerr		;else error
	cmp	#'$'		;if $
	beq	endkim		;then done
	cmp	#eof		;if eof
	beq	endkim		;then done
	cmp	#semico		;if not file mark
	bne	kimlop		;try again
	jsr	gettwo		;get count
	beq	endkim		;done if zero
	sta	kimcnt		;set count
	jsr	gettwo		;get high addr
	sta	pointr+1	;and save
	jsr	gettwo		;get low addr
	clc			;add
	adc	offset		;offset
	sta	pointr		;and save
	pha			;locally
	lda	pointr+1	;get high
	adc	offset+1	;add offset
	sta	pointr+1	;and save
	tay			;set high
	pla			;and low
	pha			;save low again
	cmp	lokim		;see if
	tya			;too
	sbc	lokim+1		;small
	pla			;get low back
	bcs	*+5		;if ok continue
	jmp	xqrerr		;else error
	clc			;add
	adc	kimcnt		;count
	bcc	*+3		;to start
	iny			;and save
	sec			;set carry
	sbc	#1		;drop
	bcs	*+3		;by one to
	dey			;get last address
	cmp	hikim		;see if
	tya			;too
	sbc	hikim+1		;big
	bcc	*+5		;if ok continue
	jmp	xqrerr		;else error
kmhiok	jsr	gettwo		;get byte
	ldy	#0		;clear index
	sta	(pointr),y	;store byte
	inc	pointr		;bump low
	bne	*+4		;done if not zero
	inc	pointr+1	;else bump high
	dec	kimcnt		;count down
	bne	kmhiok		;loop if more
	jsr	gettwo		;ignore
	jsr	gettwo		;checksum
	jmp	kimlop		;and loop
endkim	clc			;no error
	rts
xqrerr	sec			;error
	rts
;skip blanks
spcskp	lda	ctxt,y		;get char
	beq	spcext		;done if none
	cmp	#' '		;if not space
	bne	spcext		;then done
	iny			;else loop
	bne	spcskp		;and try again
spcext	rts
;test for illegal
; if an error then z=1 else z=0
lgltst	lda	ctxt,y		;get char
	beq	lglext		;done if null
	cmp	#' '		;if less than space
	bcc	inptbd		;is an error
	beq	lglext
	cmp	#'?'
	beq	lglext
	cmp	#'*'
	beq	lglext
	cmp	#'='
	beq	lglext
	cmp	#'.'
	beq	lglext
	cmp	#':'
	beq	lglext
	cmp	#semico
	beq	lglext
	cmp	#'<'
	beq	lglext
	cmp	#'>'
lglext	rts
inptbd	lda	#0		;error
	rts
;get character
getchr	ldx	kimpnt		;get pointer
	bpl	noread		;if ok use
	jsr	rdedfl		;else read
	beq	getok		;if ok continue
	bpl	*+5		;ok if eof
	jmp	gcerr		;else error
	lda	#eof		;get an eof
	sta	dflbuf		;put in buffer
	lda	#0		;clear a to
getok	tax			;clear index
	stx	kimpnt		;and pointer
noread	inc	kimpnt		;bump pointer
	lda	dflbuf,x	;get char
	and	#%01111111	;mask out parity
	clc			;no error
	rts
gcerr	sec			;read error
	rts
;get byte
gettwo	lda	#0		;clear
	sta	number		;buffer
	sta	number+1	;so no error
	jsr	getone		;get nibble
	bcs	geterr		;branch if error
getone	jsr	getchr		;get char
	bcs	geterr		;branch if error
	jsr	pack		;pack and convert
	bcs	geterr		;error if carry
	lda	number		;else get result
	clc			;no error
geterr	rts
;pack ascii
pack	cmp	#'0'		;if too small
	bmi	packer		;then error
	cmp	#'9'+1		;if "0" to "9"
	bmi	decnum		;is decimal
	cmp	#'A'		;if less than "A"
	bmi	packer		;then error
	cmp	#'F'+1		;if more than "F"
	bpl	packer		;then error
	clc			;else add
	adc	#9		;nine
decnum	rol	a		;move
	rol	a		;to
	rol	a		;high
	rol	a		;nibble
	ldx	#4		;shift
packlp	rol	a		;input
	rol	number		;and
	rol	number+1	;buffer
	bcs	packer		;error if carry
	dex			;count down
	bne	packlp		;and loop
	rts
packer	sec			;error
	rts			;return
;output space
outspc	lda	#' '		;get space
;output with save
charot	pha			;save char
	stx	savex		;save x
	sty	savey		;and y
	jsr	outchr		;send
	ldy	savey		;restore
	ldx	savex		;x and y
	pla			;then char
	rts
;default file references
stdfbf	lda	#<dflbuf	;point to
	ldy	#>dflbuf	;default buffer
bufset	ldx	#26		;set dma
	bne	topem
opndfl	ldx	#15		;open file
	bne	setdfl
rdedfl	ldx	#20		;read record
setdfl	lda	#<dflfcb	;point to
	ldy	#>dflfcb	;default fcb
	jmp	topem		;go
;general pem references
chrinp	ldx	#1		;character input
	bne	topem
outchr	ldx	#2		;character output
	bne	topem
wrtmsg	ldx	#9		;write message
	bne	topem
select	ldx	#14		;select drive
	bne	topem
rdeinp	lda	#<cbuf		;read buffer
	ldy	#>cbuf
	ldx	#10
topem	jmp	pemjmp
;kim type field
kimtyp	.byte	"KIM"
;messages
opnmsg	.byte	"DOS/65 SYSGEN V2.19-S$"
szemsg	.byte	cr,lf,"ENTER MEMORY SIZE IN DECIMAL "
	.byte	"K BYTES (K=1024) $"
btemsg	.byte	cr,lf,"ENTER DRIVE AND NAME FIELD "
	.byte	"FOR BOOT .KIM FILE $"
flemsg	.byte	cr,lf
	.byte	"ILLEGAL FILE NAME, BAD DATA OR"
	.byte	cr,lf
	.byte	"ILLEGAL ADDRESS IN INPUT FILE "
	.byte	"- ABORTING$"
nwsmsg	.byte	cr,lf,"ENTER SIM LENGTH IN DECIMAL "
	.byte	"PAGES (PAGE=256) (1 TO 99) $"
simmsg	.byte	cr,lf,"ENTER DRIVE AND NAME "
	.byte	"FIELD FOR SIM .KIM FILE $"
iermsg	.byte	"ILLEGAL INPUT - REENTER $"
crtmsg	.byte	cr,lf,"INSERT DISKETTE THEN ENTER "
	.byte	"DESTINATION DRIVE (A-H) $"
rommsg	.byte	cr,lf,"NOT ENOUGH SYSTEM TRACKS - "
	.byte	"ABORTING$"
invmsg	.byte	cr,lf,"INVALID DRIVE - TRY AGAIN$"
bigmsg	.byte	cr,lf
	.byte	"SYSTEM IS TOO LONG - ABORTING$"
wermsg	.byte	cr,lf
	.byte	"ERROR DURING WRITE - ABORTING$"
;variables
syslng	.word	ccmlng+pemlng	;system length
;input buffer
cbuf
cmax	.byte	32		;input
clng	.byte	0		;buffer
ctxt
	*=	*+32
;align code on half page inorder to assist in
;debugging and to allow jmp (xxxx) to be
;placed at word boundary.
	*=	((*/256)*256)+384
;-------------------------------
;dos/65 boot
;-------------------------------
boot				;reserve space
	*=	*+128

;-------------------------------
; Include ccm + pem 
;-------------------------------
	.INCLUDE "../ccm.asm"
	.INCLUDE "../pem.asm"
;--------------------------------
;dos/65 system interface module (sim)
;--------------------------------
	*=	pem+pemlng
sim
	*=	*+55
sysdef
	.end
Ende 	
