;dos/65 system interface module (sim)
;for C64 and SYSGEN 2.15
;version 3.04
;based on my S-100 6502 SIM 3.01 and both BIOS65.ASM & BIOS80.ASM
;as well as C64S302.ASM.
;for the C64 CP/M cartridge.
;released:	5 april 2008
;last revision:
;	5 april 2008
;		corrected linefeed character
;		changed to 40 char per line
;		changed to 25 lines per screen
;		made iotype initialized to 1 & in fixed location
;		eliminated use of data in conout
;		corrected error near end of conin
;		added jsr CLALL at cold boot start
;		forced function keys to return space
;		corrected error in read code after la3f
;		corrected & added drive select logic
;		increased to 10 pages
;		modified console in & out for delete & bs
;		changed key code for DEL
;		removed conin test for BS
;		modified warm boot to use full sim deblocking
;		corrected one entry in key code table for "="
;		corrected track numbering
;		reduced allocation map to 17 bytes (8*17=136)
;		changed CDB entries & conout code
;	6 april 2008
;		increased to 52K
;	7 april 2008
;		changed from internal keyboard scanning to use of kernel
;		enabled interrupts
;		reintroduced flashing control
;		added quote mode control to conout
;	9 april 2008
;		added blank dcb table entries for drives 2-7 (c-h)

.CPU  45GS02 

; Shared constants and macros
	.INCLUDE "../constants.asm"
	.INCLUDE "kernel.asm"
	.INCLUDE "macros.asm"
;base addresses
wbtjmp	=	$100		;warm boot entry
pemjmp	=	$103		;pem entry
iostat	=	$106		;io status byte
dflbuf	=	$128		;default buffer
;C64 KERNAL (kernel) entry points & assigned memeory
flash	=	$cc		;enable cursor flas if 0
cursor	=	$cf		;cursor chaaracter (BLNON in PRG)
qtsw	=	$d4		;quote mode 0=no
;pem constants on entry to write
wrall	=	0		;write to allocated
wrdir	=	1		;write to directory
wrual	=	2		;write to unallocated
;module addresses
simlng	=	pages*256	;sim length in bytes
pem	=	memlng-simlng-pemlng	;pem start
ccm	=	pem-ccmlng	;ccm start
length	=	ccmlng+pemlng	;length less sim
nsects	=	length/128	;number sectors

;main program
StartSim =	memlng-simlng
	*=	StartSim	;start of sim
	.STORE StartSim,EndSim-StartSim,"c65sim.bin"
;jump vector used by pem
sim	jmp	boot		;from cold start
wboote	jmp	wboot		;from warm boot
	jmp	const		;check for input
	jmp	conin		;get input
	jmp	conout		;send to terminal
	jmp	list		;printer output
	nop			;punch output - dummy for now
	nop
	rts
	nop			;reader input - dummy for now
	nop
	rts
	jmp	home		;home drive
	jmp	seldsk		;select disk
	jmp	seltrk		;set track
	jmp	selsec		;set sector
	jmp	setdma		;set buffer address
	jmp	read		;read sector
	jmp	write		;write sector
	lda	#1		;printer always ready
	rts
	ldx	#128		;clock entry
	rts
;translate record number
;input: ay = logical record number
;return: ay = logical record number if no translation or interleave
;	physical sector number if translation
	nop			;translate - do not change logical #
	nop
	rts
;console definition block
;some do not fully implement the functions:
;	clear to eol is a lf as recommended by SIG
;	clear to eos is not implemented
	.byte	0		;scratch
sysdef	.byte	8		;backspace
	.byte	10		;clear to end of line
	.byte	29		;forward space
	.byte	1		;normal video
	.byte	18		;invert video
	.byte	25		;lines per screen
	.byte	40		;char per line
	.byte	12		;formfeed
	.byte	19		;home
	.byte	0		;clear to end of screen
;I/O control byte
;as implemented there is no code in SIM to alter this but it is placed in a fixed location
;after CDB to allow for future changes by external or internal code
;bit 0 = 
;bit 1 =
;bit 2 = printer type - 0 if 1515, 1 if 4022
;bit 3 =
;bit 4 =
;bit 5 =
;bit 6 =
;bit 7 =
iotype	.byte	1
;opening id message
opnmsg	.byte	cr,lf,"C65 64K DOS/65 2.15 "
	.byte	"SIM 3.04",0
;cold entry from loader
boot
;first clear all files and channels
	jsr	CLALL		;loader should do this but make sure
;now send a series of characters to screen to set it up
	lda	#' '		;set cursor
	sta	cursor		;to space
;now enable interrupts and set up screen
	cli			;enable interrupts
 	LDA	#9		;enable char set change
	JSR	BSOUT		;output to channel
 	LDA	#14		;switch to upper/lower case
	JSR	BSOUT		;output to channel
 	LDA	#8		;disable char set change
	JSR	BSOUT		;output to channel
 	LDA	#147		;clear & home
	JSR	BSOUT		;output to channel
 	LDA	#CR		;return & do line feed
	JSR	BSOUT		;output to channel
;next section addresses C64 specific setup
	lda	#<opnmsg	;point to message
	ldy	#>opnmsg
	jsr	outmsg		;send it
;set up jumps into dos/65 in page one
setup	ldx	#0		;clear index
;first clear key dba & other variables
	stx	hstact		;host buffer inactive
	stx	unacnt		;clear unalloc count
setupl	lda	inttbl,x	;get byte
	sta	$100,x		;insert at start
	inx
	cpx	#6
	bne	setupl		;loop until done
	lda	#<dflbuf	;get low buffer
	ldy	#>dflbuf	;and high
	jsr	setdma		;and set
	lda	sekdsk		;get disk
	jmp	ccm		;and go to ccm
;initialization table
inttbl	.byte	$4c
	.word	wboote
	.byte	$4c
	.word	pem
;warm boot-read dos/65 back except sim and then
; jump to ccm.
wboot	ldx	#$ff		;set stack
	txs			;pointer
	cld			;set binary mode
;set up parameters for warm boot
	lda	#nsects		;get number sectors
	sta	count		;and set count
	lda	#0		;set zero
	sta	wbtrk		;clear track
	jsr	seldsk		;and select drive zero
	lda	#1
	sta	wbsec		;first record
	lda	#<ccm
	ldy	#>ccm
	sta	wbdma
	sty	wbdma+1		;first dma address
;the following uses SIM deblocking
rdblk	lda	wbtrk		;get track
	ldy	wbtrk+1
	jsr	seltrk		;and set
	lda	wbsec		;get sector
	ldy	wbsec+1
	jsr	selsec		;and set
	lda	wbdma		;get dma address
	ldy	wbdma+1
	jsr	setdma		;and set
	jsr	read		;then do read
	and	#$ff		;test for error
	bne	rderr		;if error handle it
;first see if more
	dec	count		;drop record count
	beq	aldon		;done if zero
;adjust parameters for next record
;first do dma address
	clc			;clear carry
	lda	wbdma		;get buffer address
	adc	#128		;and raise it
	sta	wbdma
	bcc	nodmaw		;skip if no carry
	inc	wbdma+1		;bump high
;now do sector but assume records per track = 34
nodmaw	inc	wbsec		;dump sector
	lda	wbsec		;get new low
	cmp	#34		;see if past last
	bne	rdblk		;if not record OK & track unchanged
;we now must reset record and increase track
	lda	#0		;starting record =0 after track 0
	sta	wbsec		;save it
	inc	wbtrk		;bump track (0 to 1)
	bne	rdblk		;loop always
aldon	lda	sekdsk		;set default drive
	sta	hstdsk
	jmp	setup		;go setup
rderr	jmp	($fffc)		;go to kernel
;warm boot variables
wbtrk	.word	0		;track (0 logical - SIM will translate to C64)
wbsec	.word	1		;record (0 = BOOT, 1 = first CCM)
wbdma	.word	ccm		;address
;character save
chrsav	.byte	0		;saves last character from keyboard 0=none
;console status
;input: none
;return: a<>0 if character ready, a=0 if not
const	lda	chrsav		;see if character still there
	bne	constx		;done if one there
	jsr	getin		;else try to get char
	and	#%11111111	;see if any bits set
	beq	constx		;done if none
	sta	chrsav		;save but do not convert
constx	rts
;console input - waits for character to be typed
;this routine should not display the character entered
;input: none
;return: character in a
conin	lda	#0		;turn on flash
	sta	flash
coninl	jsr	const		;check status
	and	#%11111111	;see if something there
	beq	coninl		;loop if nothing
	lda	chrsav		;get character
	pha			;save it
	lda	#0		;clear save
	sta	chrsav
	lda	#%00000001	;turn off flash
	sta	flash
	lda	#' '		;send space
	jsr	conout
	lda	#157		;cursor left command
	jsr	conout		;bypass filter
	pla			;get character back
;start processing character to get normal ASCII for most keys
	cmp	#20		;see if unshifted DEL
	bne	cin1		;is not so try next
	lda	#127		;get normal delete
	bne	coninx		;and return
cin1	cmp	#193		;see if < shift-A
	bcc	cin2		;is so jump ahead
	cmp	#219		;see if > shift-Z
	bcs	cin2		;is so jump ahead
;character is shifted a-z so adjust
	sec			;subtract 128
	sbc	#128		;is now upper case a-z
	bne	coninx		;so return that code
;character is anything except DEL & shift a-z
;first see if unshifted a-z
cin2	cmp	#65		;see if < A
	bcc	cin3		;is so jump ahead
	cmp	#91		;see if > Z
	bcs	cin3		;is so jump ahead
;character is unshifted A-Z so adjust
	clc			;add 32
	adc	#32		;to make lower case
	bne	coninx		;and return that code
;any remaining characters > 95 are ignored by following section
;this may get changed in later versions
cin3	cmp	#96		;see if > 95
	bcs	conin		;if so loop for another
;any other character < 128 is then returned
coninx	rts
;console output of char in a
conout	pha			;save char
	lda	iotype		;get config
	and	#%00010000	;if bit 4 set print as received
	bne	cout5
	pla			;get char back
	jsr	swap		;swap upper & lower case
;start testing for special functions
	cmp	#12		;see if clear screen
	bne	cout1		;is not
	lda	#147		;is so get Commodore clear cmd
	bne	coutdo		;and go send
cout1	cmp	#8		;see if backspace
	bne	cout2		;is not
	lda	#157		;go left
	jsr	coutdo		;and send to screen
	lda	#32		;now send space
	jsr	coutdo
	lda	#157		;go left again
	bne	coutdo		;and send
cout2	cmp	#lf		;see if linefeed
	bne	cout3		;is not
	lda	#17		;get Commodore linefeed
	bne	coutdo		;and send it
cout3	cmp	#cr		;see if cr
	bne	cout4		;is not
	jsr	coutdo		;send that
	lda	#145		;now up 1 line due to auto lf
	bne	coutdo		;and send
cout4	cmp	#18		;see if reverse on
	beq	coutdo		;is so send
	cmp	#1		;see if normal video
	bne	cout6		;not so try next
	lda	#146		;get C64 normal
	bne	coutdo		;and send it
cout6	cmp	#19		;see if home
	beq	coutdo		;if so send it
	cmp	#29		;see if forward space
	beq	coutdo		;if so send it
	cmp	#' '		;see if other control char
	bcc	coutx		;ignore if is
	cmp	#157		;see if left
	beq	coutdo		;if so send
	cmp	#128		;see if not ASCII
	bcs	coutx		;done if not ASCII
	pha			;save for the moment
cout5	pla			;get character back
coutdo	pha			;save char
	lda	#0		;turn off quote mode
	sta	qtsw
	pla			;get it back
	jsr	BSOUT		;output to channel
coutx	rts
;swap upper and lower case for C64
swap	cmp	#'A'		;see if < A
	bcc	swapx		;done if is
	cmp	#'Z'+1		;see if upper case
	bcc	swap1		;is so handle
	cmp	#'a'		;see if under lc a
	bcc	swapx		;done if is
	cmp	#'z'+1		;see if lower case
	bcs	swapx		;if not done
swap4	and	#%01011111	;clear bit 5
swapx	rts
swap1	ora	#%00100000	;turn on bit 5
	rts
;similar for printer
swap2	cmp	#'A'		;see if < A
	bcc	swapx		;done if is
	cmp	#'a'-1		;see if < a
	bcs	swap4		;not so convert
	ora	#%10000000	;is so make > 128
	rts
;print of message
;the call to outmsg passes address in ay,
;binary zero as the end.
outmsg	sta	getmsg+1	;address into			
	sty	getmsg+2	;operand
getmsg	lda	$ffff		;get the char
	beq	n3		;branch if done
	jsr	conout		;print char
lpnext	inc	getmsg+1	;bump the pointer
	bne	getmsg		;no carry so loop
	inc	getmsg+2	;bump high byte
	jmp	getmsg		;go back for more
n3	rts			;return past mess.
;send char in a to printer
;should be able to move the LA9F routine up to be in line
list	pha			;save char
	lda	iotype		;get config
	and	#%00000100	;0 if 1515, 1 if 4022
	bne	list2		;jump if no swap
	lda	iotype		;get config back
	and	#%00001000	;see what kind of swap
	bne	list1		;4022 swap
	pla			;get char
	jsr	swap		;regular swap
	jmp	list21		;and go send
list1	pla			;get char back
	jsr	swap2		;do 4022 swap
	pha			;save char
list2	pla			;get char back
list21	sta	data		;save
LA9F	LDA	DATA		;get character
	CMP	#LF		;see if line feed
	beq	lac5		;if is do nothing
LAA7	LDX	#4		;else set channel out to 4
	JSR	CKOUT		;set channel out
	BCS	LAB7		;if error try to fix
	LDA	DATA		;if OK get character again
	JSR	BSOUT		;output to channel
LAB4	JMP	CLRCH		;restore default channel & exit
LAB7	CMP	#3		;see if not opened
	BNE	LAC0		;some other error so exit
	JSR	LAC6		;try to open printer
	BCC	LA9F		;successful so try again
LAC0	LDA	#$FF		;put error code
	STA	DATA		;in data for Z80
LAC5	RTS
;open printer channel
LAC6	LDY	#7		;SA =7 prints in upper & lower case
	JSR	LADE		;close & open printer channel
	LDA	IOTYPE		;get I/O type
	AND	#$02
	BEQ	LAC5		;if 1515 then done
	LDX	#4		;set LA as 4
	JSR	CKOUT		;set channel out
	LDA	#CR		;send a CR
	JSR	BSOUT		;output to channel
	LDY	#0		;set SA to 0
;close printer and then open
LADE	LDA	#4		;logical file 4
	JSR	CLOSE		;close logical file
	LDA	#4		;now set LA to 4
	LDX	#4		;and device FA to 4
	JSR	SETLFS		;set LA, FA, SA
	LDA	#0		;zero length name
	JSR	SETNAM		;set length & file name address
	JMP	OPEN		;open logical file
;select disk
;input: a = drive number (0 to 7)
;return: ay = address of dcb for drive
;	0 if drive not present
seldsk	and	#7		;three lsbs only
	sta	sekdsk		;save for later
	asl	a		;multiply by two
	tax			;make an undex
	lda	dcbtbl,x	;get address
	ldy	dcbtbl+1,x
	rts
;set sector number
;input: ay = physical record number
;return: none
selsec	sta	seksec		;save low and high
	sty	seksec+1
	rts
;set buffer address
;input: ay = starting address of record
;return: none
setdma	sta	dmaadr		;store low
	sty	dmaadr+1	;and high
	rts
;set track
;input: ay = track number
;return: none
seltrk	sta	sektrk		;save number
	sty	sektrk+1
	rts
;table of dcb addresses
dcbtbl	.word	dcba
	.word	dcbb
	.word	0
	.word	0
	.word	0
	.word	0
	.word	0
	.word	0
;see if deblocking required for sekdsk
;returns number of dos/65 sectors per physical
;sector in a and
;returns z=1 if no deblocking reguired else z=0
tstdbl	ldx	sekdsk		;get desired disk
;see if deblocking required for disk x
tstdbx	lda	spttbl,x	;get dos/65 sectors/host
	cmp	#1		;test for no deblock
	rts
;table containing number of dos/65 sectors
;per host physical sector.  if entry is 1
;then deblocking is skipped.
spttbl	.byte	2,2
;table of records/block
rbltbl	.byte	8,8
;home the selected disk
;input: none
;return: none
home	lda	hstwrt		;check for pending write
	bne	homed		;there is so skip
	sta	hstact		;clear host active flag
homed	rts			;do nothing
;the read entry point takes the place of
;the previous sim definition for read.
;read the selected dos/65 sector
;input: none
;return: a=0 if read OK
;	<> 0 if error
read	ldx	#0		;x <-- 0
	stx	unacnt		;clear unallocated count
	inx			;x <-- 1
	stx	readop		;say is read operation
	stx	rsflag		;must read data
	inx			;x <-- wrual
	stx	wrtype_		;treat as unalloc
	jmp	rwoper		;to perform the read
;The write entry point takes the place of
;the previous sim defintion for write.
;write the selected dos/65 sector
;input: a=0 if write to allocated block
;	=1 if write to directory
;	=2 if write to unallocated block
write	sta	wrtype_		;save param from pem
	jsr	tstdbl		;see if one rec/sec
	bne	usewrt		;if not use type passed
	lda	#wrdir		;if is say directory
	sta	wrtype_		;to force write
usewrt	ldx	#0		;say is
	stx	readop		;not a read operation
	lda	wrtype_		;get write type back
	cmp	#wrual		;write unallocated?
	bne	chkuna		;check for unalloc
;write to unallocated, set parameters
	ldx	sekdsk		;get next disk number
	lda	rbltbl,x	;get records/block
	sta	unacnt
	stx	unadsk		;unadsk <-- sekdsk
	lda	sektrk
	ldy	sektrk+1
	sta	unatrk		;unatrk <-- sectrk
	sty	unatrk+1
	lda	seksec
	ldy	seksec+1
	sta	unasec		;unasec <-- seksec
	sty	unasec+1
;check for write to unallocated sector
chkuna	lda	unacnt		;any unalloc remain?
	beq	alloc		;skip if not
;more unallocated records remain
	dec	unacnt		;unacnt <-- unacnt-1
	lda	sekdsk
	cmp	unadsk		;sekdsk = unadsk?
	bne	alloc		;skip if not
;disks are the same
	lda	unatrk		;sektrk = unatrk?
	cmp	sektrk
	bne	alloc		;no so skip
	lda	unatrk+1
	cmp	sektrk+1
	bne	alloc		;skip if not
;tracks are the same
	lda	unasec		;seksec = unasec?
	cmp	seksec
	bne	alloc		;no so skip
	lda	unasec+1
	cmp	seksec+1
	bne	alloc		;skip if not
;match, move to next sector for future ref
	inc	unasec		;unasec = unasec+1
	bne	nounsc
	inc	unasec+1
;calculate dos/65 sectors/track
nounsc	lda	sekdsk		;get disk number
	asl	a		;mult by two
	tax			;make an index
	lda	dcbtbl,x	;get dcb start
	ldy	dcbtbl+1,x
	sta	getspt+1	;set low operand
	sty	getspt+2	;then high operand
;point has address now get spt at byte 2,3
	ldy	#2		;start at byte 2
	ldx	#0		;start save in low
getspt	lda	$ffff,y		;get value
	sta	d65spt,x	;and save
	iny
	inx
	cpx	#2		;see if done
	bne	getspt		;loop if not
;check for end of track
	lda	unasec		;end of track?
	cmp	d65spt		;count dos/65 sectors
	lda	unasec+1
	sbc	d65spt+1
	bcc	noovf		;skip if no overflow
;overflow to next track
	lda	#0		;unasec <-- 0
	sta	unasec
	sta	unasec+1
	inc	unatrk		;unatrk <-- unatrk+1
	bne	noovf
	inc	unatrk+1
;match found, mark as unnecessary read
noovf	lda	#0		;0 to accumulator
	sta	rsflag		;rsflag <-- 0
	beq	rwoper		;to perform the write
;not an unallocated record, requires pre-read
alloc	ldx	#0		;x <-- 0
	stx	unacnt		;unacnt <-- 0
;say preread required
	inx			;x <-- 1
	stx	rsflag		;rsflag <-- 1
;check for single record/sector - and if so
;then say preread not required.
	jsr	tstdbl		;test
	bne	rwoper		;more than one
	lda	#0		;say no preread
	sta	rsflag
;common code for read and write follows
;enter here to perform the read/write
rwoper	lda	#0		;zero to accum
	sta	erflag		;no errors (yet)
	lda	seksec		;compute host sector
	ldy	seksec+1
	sta	sekhst
	sty	sekhst+1
	jsr	tstdbl		;get records/sector
	lsr	a		;divide by two
	tax			;make a counter
	beq	noshif		;done if zero
shflpe	lsr	sekhst+1	;do high
	ror	sekhst		;then low
	dex
	bne	shflpe		;loop if more
;active host sector?
;at this point x=0
noshif	lda	hstact		;host active flag
	pha			;save
	inx			;x <-- 1
	stx	hstact
	pla			;get flag back
	beq	filhst		;fill host if not active
;host buffer active, same as seek buffer?
	lda	sekdsk
	cmp	hstdsk		;same disk?
	bne	nmatch
;same disk, same track?
	lda	hsttrk		;sektrk = hsttrk?
	cmp	sektrk
	bne	nmatch		;no
	lda	hsttrk+1
	cmp	sektrk+1
	bne	nmatch
;same disk, same track, same sector?
	lda	sekhst		;sekhst = hstsec?
	cmp	hstsec
	bne	nmatch		;no
	lda	sekhst+1
	cmp	hstsec+1
	beq	match		;skip if match
;proper disk, but not correct sector
nmatch	lda	hstwrt		;host written?
	beq	filhst		;skip if was
	jsr	writeh		;else clear host buff
;may have to fill the host buffer
;so set host parameters
filhst	lda	sekdsk
	sta	hstdsk
	lda	sektrk
	ldy	sektrk+1
	sta	hsttrk
	sty	hsttrk+1
	lda	sekhst
	ldy	sekhst+1
	sta	hstsec
	sty	hstsec+1
	lda	rsflag		;need to read?
	beq	noread		;no
;read desired physical sector from host
	jsr	hcom		;set parameters
	jsr	la3f		;to rom
	sta	erflag		;save result
noread	lda	#0		;0 to accum
	sta	hstwrt		;no pending write
;copy data to or from buffer
match	lda	#0		;clear write move pointer
	sta	wmoved+1	;later we'll set read read
	sta	wmoved+2
	jsr	tstdbl		;get records/sector
	beq	endmve		;done if no deblocking
	tax			;drop by one
	dex
	txa
	and	seksec		;mask sector number
	tax			;make a counter
	beq	nooff		;done if zero
clcpnt	clc
	lda	wmoved+1
	adc	#128
	sta	wmoved+1
	lda	wmoved+2
	adc	#0
	sta	wmoved+2
	dex
	bne	clcpnt		;loop if more
;operand has relative host buffer address
nooff	clc			;add hstbuf
	lda	#<hstbuf
	adc	wmoved+1
	sta	wmoved+1
	lda	#>hstbuf
	adc	wmoved+2
	sta	wmoved+2
;at this point wmove operand contains the address of the
;sector of interest in the hstbuf buffer.
;so now set the operands for the possible read move
	lda	wmoved+1
	sta	rmove+1
	lda	wmoved+2
	sta	rmove+2
;now set address of record in associated operands
	lda	dmaadr
	sta	wmove+1
	sta	rmoved+1
	lda	dmaadr+1
	sta	wmove+2
	sta	rmoved+2
;at this point the pointers are all set for read or write
	ldy	#127		;length of move - 1
	ldx	readop		;which way?
	bne	rmove		;skip if read
;write operation so move from dmaadr
	inx			;x <-- 1
	stx	hstwrt		;hstwrt <-- 1
wmove	lda	$ffff,y
wmoved	sta	$ffff,y
	dey
	bpl	wmove		;loop if more
	bmi	endmve		;else done
;read operation so move to dmaadr
rmove	lda	$ffff,y
rmoved	sta	$ffff,y
	dey
	bpl	rmove		;loop if more
;data has been moved to/from host buffer
endmve	lda	wrtype_		;write type
	cmp	#wrdir		;to directory?
	bne	nodir		;done if not
;clear host buffer for directory write
	lda	erflag		;get error flag
	bne	nodir		;done if errors
	sta	hstwrt		;say buffer written
	jsr	writeh
nodir	lda	erflag
	rts	
;writeh performs the physical write to
;the host disk.
writeh	jsr	hcom		;setup params
	jsr	la57		;to kernal
	sta	erflag		;save result
	rts
;set parameters for host (physical) read/write
;as coded this is limited to reading or writing to the c64 cp/m
;disk format for the 1541, i.e.,
;1541 drive numbers are
;	drive 0 --> device 8
;	drive 1 --> device 9
;1541 track numbers go from 1 to 35 however 1541 track
;	number 18 is reserved for the 1541 directory
;	and can not be used by cp/m or dos/65. Net
;	result is that dos/65 track must be increased by
;	one and if track is 18 or more it is increased by one
;	more to skip directory track
;1541 sector numbers go from 0 to 16
hcom	lda	hstdsk		;get disk number
;now calculate device number
	clc			;by adding "8"
	adc	#8		;to drive number
	sta	device
;ignore high byte of track and sector for 1541
	lda	hsttrk
	sta	phytrk
	inc	phytrk		;bump track by one
	lda	phytrk		;now check for 18
	cmp	#18		;since that is reserved
	bcc	nobump		;if < 18 do nothing
	inc	phytrk		;else bump 18-->19, 19-->20 etc 
nobump	lda	hstsec		;then sector
	sta	physec
	rts			;done
;following section contains core C64 I/O routines
;change drive by sensing new drive and then closing 15 & 2
;and then reopening 15 & 2 with new device number
chkdrv	lda	hstdsk		;get new drive number
	cmp	lstdrv		;see if same as last
	beq	chkdrx		;done if is
	sta	lstdrv		;save new for next
	jsr	lb97
chkdrx	rts
;read sector
;returns a=0 if ok else a<>0 with flags set appropriately
;as currently implemented it should never return an error code
LA3F	jsr	chkdrv		;check & change drive
	LDA	#'1'		;"1" in "U1"
	JSR	LAF2		;set up USER 1 mode
	JSR	LBDE		;set up read from LA 2
	LDX	#0		;do full 256 bytes
LA49	JSR	BASIN		;input from channel
	STA	HSTBUF,X	;& put in host buffer
	INX			;go to next
	BNE	LA49		;loop if more
	stx	data		;set return
	jsr	clrch		;restore default
	lda	data		;get error code
	rts			;exit always
;do sector write but first initialize diskette
LA54	JSR	LB97		;initialize diskette
	jmp	la571		;skip drive check
;write sector
;returns a=0 if ok else a<>0 with flags set appropriately
LA57	jsr	chkdrv		;check and change drive
la571	JSR	LBF4		;set up to write to command channel
	LDY	#8		;8 characters
LA5C	LDA	LB80,X		;send block command
	JSR	BSOUT		;output to channel
	INX
	DEY
	BNE	LA5C
	JSR	CLRCH		;restore default channel
	JSR	LBCE		;read command results
	BNE	LA54		;error so initialize
	JSR	CLRCH		;restore default channel
	JSR	LBE9		;set up write to channel 2
	LDX	#0
LA76	LDA	HSTBUF,X	;get byte from buffer
	JSR	BSOUT		;output to channel
	INX
	BNE	LA76		;loop until all 256 written
	JSR	CLRCH		;restore default channel
	LDA	#'2'		;"2" in "U2", block write
;set up user mode
;error return: a=$ff & z=0 else a=0 & z=1
;returns: a
LAF2	STA	LB62+1		;save "1" or "2" for mode
	LDA	phytrk		;now get track number
	JSR	LB89		;convert to ASCII
	STX	LB62+7		;and store in string
	STA	LB62+8
	LDA	physec		;once more for sector
	JSR	LB89		;convert to ASCII
	STX	LB62+10		;and store in string
	STA	LB62+11
	LDA	#2		;set DATA for 2 tries
	STA	DATA
LB1B	JSR	LBF4		;set up command channel
	LDY	#13		;string is 13 characters
LB20	LDA	LB62,X		;get character and
	JSR	BSOUT		;output to channel
	INX
	DEY
	BNE	LB20
	JSR	CLRCH		;restore default channel
	JSR	LBCE		;read error channel
	BEQ	LB3D		;if no error say so & exit
	DEC	DATA		;else drop counter
	BEQ	LB45		;if everything tested then error
	JSR	LB97		;else initialize diskette
	JMP	LB1B		;and try again
LB3D	LDA	#0		;set flag for no error
LB3F	STA	DATA		;in data
	jsr	CLRCH		;restore default channel
	lda	data		;get error code back
	rts			;exit
LB45	LDA	#$FF		;set flag for error
	BNE	LB3F		;and always save
;text strings for disk operations
LB62	.byte	"U1:2 0 TT SS", CR
LB6F	.byte	"#"		;random access
LB80	.byte	"B-P 2 0", CR
LB88	.byte	"I"		;initialize
;convert binary in A to ASCII in X (upper) and A (lower)
;this assumes maximum value of binary is 99
LB89	CLD
	LDX	#'0'		;set upper to zero
	SEC
LB8D	SBC	#10		;A-10 to A
	BCC	LB94		;less than zero so done
	INX			;X+1 to X
	BCS	LB8D		;and try again
LB94	ADC	#'0'+10		;add 10 back & convert
	RTS
;Diskette initialization & set up for direct access
;error return: c=1
;return: a = error code
;start by closing command channel
LB97	LDA	#15		;logical file (LA) 15
	JSR	CLOSE		;close logical file
;now open command channel as logical file 15
	LDA	#15		;logical file (LA) 15
	LDX	device		;device per hcom to (FA)
	LDY	#15		;secondary address (SA) 15
	JSR	SETLFS		;set LA, FA, SA
;now send initialize command to drive
	LDA	#1		;only one character
	LDX	#<LB88		;command is "I"
	LDY	#>LB88
	JSR	SETNAM		;set length & file name address
;now open
	JSR	OPEN		;open logical file
;if logical file 2 is open close it
LBB1	LDA	#2		;logical file (LA) = 2
	JSR	CLOSE		;close logical file
;now open logical file 2
	LDA	#2		;logical file (LA) 2
	LDX	device		;device per hcom to (FA)
	LDY	#2		;secondary address (SA) 2
	JSR	SETLFS		;set LA, FA, SA
	LDA	#1		;single character
	LDX	#<LB6F		;Filename "#"
	LDY	#>LB6F
	JSR	SETNAM		;set length & file name address
	JMP	OPEN		;open logical file
;initialize and then set input to command channel
LBCB	JSR	LB97		;initialize diskette
;set input to command channel and check for errors
LBCE	LDX	#15		;logical address = 15
	JSR	CHKIN		;set channel in
	BCS	LBCB		;if error try to initialize
	JSR	BASIN		;input from channel
	CMP	#'0'		;test error code "0"
	RTS
;close and open LA 2 and then
LBDB	JSR	LBB1		;set for random access
;set up read from channel 2
LBDE	LDX	#2		;channel 2
	JSR	CHKIN		;set channel in
	BCS	LBDB		;if error try to initialize
	RTS
;close and open LA 2 and then
LBE6	JSR	LBB1		;set for random access
;set up write to channel 2
LBE9	LDX	#2		;channel 2
	JSR	CKOUT		;set channel out
	BCS	LBE6		;if error close and open
	RTS 
;initialize diskette then set up for command channel write
LBF1	JSR	LB97		;initialize disk - ignore errors
;set up for write to command channel
;error return: none
;return: x=0
LBF4	LDX	#15		;LA 15 for command channel
	JSR	CKOUT		;set channel out
	BCS	LBF1		;if error initialize
	LDX	#0		;x = 0 to start transfer after RTS
	RTS
;disk control blocks
;both for C64 1541
;drive a
dcba	.word	135		;max block number
	.word	34		;records per track
	.word	2		;number system tracks
	.byte	0		;block size = 1024
	.word	63		;max directory number
	.word	almpa		;address of map for a
	.byte	0		;do checksums
	.word	ckmpa		;checksum map
;drive b
dcbb	.word	135		;max block number
	.word	34		;records per track
	.word	2		;number system tracks
	.byte	0		;block size = 1024
	.word	63		;max directory number
	.word	almpb		;address of map for a
	.byte	0		;do checksums
	.word	ckmpb		;checksum map
;data area
sekdsk	.byte	0		;seek disk number
hstwrt	.byte	0		;0=written,1=pending host write
data	.byte	0		;io data
lstdrv	.byte	8		;last drive used - start as illegal
;allocate the following data areas to unused ram space
contmp				;temp in conin
	*=	*+1
kychar				;keyboard character
	*=	*+1
savsec				;save sector for warm boot
	*=	*+1
count				;counter in warm boot
	*=	*+1
temp				;save hstdsk for warm boot
	*=	*+1
hstact				;host active flag
	*=	*+1
unacnt				;unalloc rec cnt
	*=	*+1
sektrk				;seek track number
	*=	*+2
seksec				;seek sector number
	*=	*+2
hstdsk				;host disk number
	*=	*+1
hsttrk				;host track number
	*=	*+2
hstsec				;host sector number
	*=	*+2
sekhst				;seek shr secshf
	*=	*+2
unadsk				;last unalloc disk
	*=	*+1
unatrk				;last unalloc track
	*=	*+2
unasec				;last unalloc sector
	*=	*+2
erflag				;error reporting
	*=	*+1
rsflag				;read sector flag
	*=	*+1
readop				;1 if read operation
	*=	*+1
wrtype_				;write operation type
	*=	*+1
d65spt				;dos/65 records/track
	*=	*+2
dmaadr				;record address
	*=	*+2
device				;c64 iec bus device
	*=	*+1
phytrk				;physical  track
	*=	*+2
physec				;physical sector
	*=	*+2
;allocation maps
;drive a
almpa
	*=	*+17
;drive b
almpb
	*=	*+17
;checksum maps
;drive a
ckmpa
	*=	*+16
;drive b
ckmpb
	*=	*+16
;deblocking buffer for dba
hstbuf
	*=	*+256		;256 byte sectors

; Code to switch to Kernel

_SETLFS_S
	JSR	_SetBank5WithInterface
	JSR	_SETLFS
	JMP	_RETURN_S
_SETNAM_S
	JSR	_SetBank5WithInterfaceAndDMA
	JSR	COPY_TO_COPY_BUFFER
	JSR	_SetBank5WithInterface
	JSR 	_SETNAM
	JMP	_RETURN_S

_OPEN_S
	JSR	_SetBank5WithInterface
	JSR	_OPEN
	JMP	_RETURN_S
_CLOSE_S
	JSR	_SetBank5WithInterface
	JSR	_CLOSE
	JMP	_RETURN_S
_CHKIN_S
	JSR	_SetBank5WithInterface
	JSR	_CHKIN
	JMP	_RETURN_S
_CKOUT_S
	JSR	_SetBank5WithInterface
	JSR	_CKOUT
	JMP	_RETURN_S
_CLRCH_S
	JSR	_SetBank5WithInterface
	JSR	_CLRCH
	JMP	_RETURN_S
_BASIN_S
	JSR	_SetBank5WithInterface
	JSR	_BASIN
	JMP	_RETURN_S
_BSOUT_S
	JSR	_SetBank5WithInterface
	JSR	_BSOUT
	JMP	_RETURN_S
_GETIN_S
	JSR	_SetBank5WithInterface
	JSR	_GETIN
	JMP	_RETURN_S
_CLALL_S
	JSR	_SetBank5WithInterface
	JSR	_CLALL
	JMP	_RETURN_S
_NMI_S
	SEI
	STQ	NMI_QADDR	; Save A,X,Y,Z
	PLA			; Pull processor flags
	STA	NMI_PF		; and save
	PLA			; Pull <PC for RTI
	STA	NMI_PC 		; and save
	PLA			; Pull >PC for RTI
	STA	NMI_PC + 1	; and save
	JSR	_SetBank5WithInterfaceIRQ
	JSR	_NMI_KERNEL
	JSR	_RETURN_IRQ_S
	LDA	NMI_PC + 1	; Restore >PC for RTI
	PHA
	LDA	NMI_PC 		; Restore <PC for RTI
	PHA
	LDA	NMI_PF		; Restore processor registers
	PHA
	LDQ	NMI_QADDR	; Restore A,X,Y,Z
	EOM			; Release Interrupt Latch
	RTI
_RESET_S
	RTS
_IRQ_KERNEL_S 			; IRQ is disabled from here
	STQ	IRQ_QADDR	; Save A,X,Y,Z
	PLA			; Pull processor flags
	STA	IRQ_PF		; and save
	PLA			; Pull <PC for RTI
	STA	IRQ_PC 		; and save
	PLA			; Pull >PC for RTI
	STA	IRQ_PC + 1	; and save
	JSR	_SetBank5WithInterfaceIRQ
	JSR	_IRQ_KERNEL
	JSR	_RETURN_IRQ_S
	LDA	IRQ_PC + 1	; Restore >PC for RTI
	PHA
	LDA	IRQ_PC 		; Restore <PC for RTI
	PHA
	LDA	IRQ_PF		; Restore processor registers
	PHA
	LDQ	IRQ_QADDR	; Restore A,X,Y,Z
	EOM			; Release Interrupt Latch
	RTI

_SetBank5WithInterface
	SetBank5WithInterface(S_AXYZ, S_P)
	RTS

_SetBank5WithInterfaceAndDMA
	SetBank5WithInterfaceAndDMA(S_AXYZ, S_P)
	RTS

_SetBank5WithInterfaceIRQ
	SetBank5WithInterfaceIRQ(S_AXYZI, S_PI)
	RTS

_RETURN_S	; TODO RENAME!
	SetBank5Only(S_AXYZ, S_P)
	RTS

_RETURN_IRQ_S
	SetBank5OnlyIRQ(S_AXYZI, S_PI)
	RTS

; This is called from the c65run after copying
; the ccm + pem + sim to its final memory location.
_INIT_AFTER_LOAD
	SetBank5Only(S_AXYZ, S_P)
	JMP	sim	; start cold boot..

; Fast copy bytes into copy buffer.
; A: Length
; X: SRC Address Low
; Y; SRC Address High
COPY_TO_COPY_BUFFER
	STA	CPYLEN		; Only low byte required
	STX	CPYSRL
	STY	CPYSRH
	PHA			; Protect the length
	LDA	#$05		; DMA list exists in Bank 0
	STA	$D702
	LDA	#>CPY_DMA
	STA	$D701
	LDA	#<CPY_DMA
	STA	$D700		; Execute copy via DMS
	PLA			; Restore length
	RTS
CPY_DMA
	.byte	$00			; Command low byte: COPY
CPYLEN	.word	0 			; How many bytes
CPYSRL	.byte   0			; From address Low
CPYSRH	.byte 	0			; From address High
	.byte	$05			; Source Bank
	.word	COPY_BUFFER 		; Destination address
	.byte   $00			; Destination Bank
	.byte	$00			; Command high byte
	.word   $0000			; Modulo (ignored for COPY)

S_AXYZ	.byte	0,0,0,0	; Save A, X, Y, Z
S_P	.byte	0	; Save Processor flags
S_AXYZI	.byte	0,0,0,0	; Save A, X, Y, Z for Interrupts
S_PI	.byte	0	; Save Processor flags from Bank 5 for Interrupts
IRQ_PF	.byte	0	; Store Processor register for IRQ
IRQ_PC	.word	0	; Stores IRQ return adress for RTI
IRQ_QADDR .byte	0,0,0,0	; Stores A,X,Y,Z for IRQ
NMI_PF	.byte	0	; Store Processor register for NMI
NMI_PC	.word	0	; Stores IRQ return address for NMI
NMI_QADDR .byte	0,0,0,0	; Stores A,X,Y,Z for NMI

; --------------------------------------
; Mapping of Mega65 Kernel calls:
; 1. Enable Interface bank ($2000-$3FFF)
; 2. 
; --------------------------------------
	*= SETLFS
	JMP	_SETLFS_S
	*= SETNAM
	JMP	_SETNAM_S
	*= OPEN
	JMP	_OPEN_S
	*= CLOSE
	JMP	_CLOSE_S
	*= CHKIN
	JMP	_CHKIN_S
	*= CKOUT
	JMP	_CKOUT_S
	*= CLRCH
	JMP	_CLRCH_S
	*= BASIN
	JMP	_BASIN_S
	*= BSOUT
	JMP	_BSOUT_S
	*= GETIN
	JMP	_GETIN_S
	*= CLALL
	JMP	_CLALL_S
	.end	

	* = $fffa
	.word _NMI_S	;processor hardware vectors
	.word _RESET_S
	.word _IRQ_KERNEL_S
EndSim 	
