;dos/65 system interface module (SIM)
;version 4.15X
;This is the native format version of SIM415W.ASM.
;This version is designed to work with MON10xx
;to handle DSDD and DSHD floppy disks and the
;S100 Computers Dual IDS-CF board.
;disk configuration:
; a CF 8MB (IDE0.1)
; b CF 8MB (IDE0.0) CP/M
; c CF 8MB (IDE0.2)
; d CF 8MB (IDE0.3)
; e 5 inch 80t DSHD (1.2 MB) - physical drive 3 - 1 system track
; f 5 inch 40t DSDD (Kaypro IV) - physical drive 2
; g 5 inch 40t SSDD (Kaypro II) - physical drive 2
; H 5 inch 80t DSHD (1.2 MB) - physical drive 3 - 2 system tracks
;released:	6 February 2015 (4.11X)
;			increased CCM length to 2304 & PEM to 3328
;			made iostat parameter passing approach
;			cleaned up boot disk selection
;		12 February 2015 (4.12X)
;			added drives e, f, and h
;			changed SIM pages to 16
;		15 February 2015 (4.13X)
;			changes memory for SYSGN3-8.ASM
;		23 February 2015 (4.14X)
;			baseline for SYSGN300 - initial release
;		1 March 2015 (4.15X)
;			reordered drives
;			verified with SYSGN301
;last revision
;Note that under DOS/65 3.00 the code and initialized data
;portions of SIM can be no longer than 1920 bytes long
;and still fit on the system track of a 5.25 in, 80t, DSHD diskette.
;PAGES defines the total space allocated to SIM in terms
;of 256 byte pages. This includes code, initialized data,
;and uninitialized data.
;base addresses
msize	=	62		;memory size in 1k blocks
pages	=	16		;pages in SIM
io	=	$f800		;i/o page base address
wbtjmp	=	$100		;warm boot entry
pemjmp	=	$103		;pem entry
iostat	=	$106		;io status byte
dflbuf	=	$128		;default buffer
;my system i/o routines in rom
sysrom	=	$f900		;monitor start
intlz	=	sysrom		;system initialization
consts	=	sysrom+6	;console status
conrde	=	sysrom+9	;console read
conwrt	=	sysrom+12	;console write
setdrv	=	sysrom+15	;set drive number
settrk	=	sysrom+18	;set track
setsec	=	sysrom+21	;set sector
setbuf	=	sysrom+24	;set disk buffer address
rdesec	=	sysrom+27	;read sector
wrtsec	=	sysrom+30	;write sector
fhome	=	sysrom+33	;home floppy
prnwrt	=	sysrom+36	;printer
rdtime	=	sysrom+39	;read clock
wrecal	=	sysrom+42	;reset HD system
warm	=	sysrom+45	;warm boot
outmsg	=	sysrom+48	;output message
;pem constants on entry to write
wrall	=	0		;write to allocated
wrdir	=	1		;write to directory
wrual	=	2		;write to unallocated
;module addresses
memlng	=	msize*1024	;memory length in bytes
simlng	=	pages*256	;sim length in bytes
pemlng	=	3072		;pem length in bytes
ccmlng	=	2560		;ccm length in bytes
pem	=	memlng-simlng-pemlng	;pem start
ccm	=	pem-ccmlng	;ccm start
length	=	ccmlng+pemlng	;length less sim
nsects	=	length/128	;number sectors
;fixed parameters
cr	=	$d		;carriage return
lf	=	$a		;linefeed
;establish key system RAM addresses - in current
;version only host buffer "hstbuf" location is
;important as it is common between MONITOR and SIM.
sramln	=	64		;reserve 64 bytes
sysram	=	io-sramln
hstbuf	=	sysram-512	;host buffer
;main program
*	=	memlng-simlng	;start of sim
;jump vector used by PEM
sim	jmp	boot		;from cold start
wboote	jmp	wboot		;from warm boot
	jmp	consts		;check for input
	jmp	conrde		;get input
	jmp	conwrt		;send to terminal
	jmp	prnwrt		;printer output
	nop			;punch output
	nop
	rts
	nop			;reader input
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
	ldx	#128		;clock entry - disable for now
	rts
	jmp	xlate		;translate
;console definition block
	.byte	0		;scratch
	.byte	8		;backspace
	.byte	1		;clear to end of line
	.byte	$c		;forward space
	.byte	0		;normal video
	.byte	'^'		;invert video
	.byte	24		;lines per screen
	.byte	80		;char per line
	.byte	$c		;form feed
	.byte	$1e		;home
	.byte	2		;clear to end of screen
;opening id message
opnmsg	.byte	cr,lf,"62K DOS/65 V3.01 SIM V4.15X",0
;cold entry from loader
boot	jsr	wrecal		;recal HD system
	lda	#<opnmsg	;point to message
	ldy	#>opnmsg
	jsr	outmsg		;send it
;initialize iostat
	lda	#0		;drive 0 and user 0
	sta	iostat
;set up jumps into dos/65 in page one
setup	ldx	#0		;clear index
;first clear key de-blocking variables
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
	jmp	ccm		;and go to CCM
;initialization table
inttbl	.byte	$4c
	.word	wboote
	.byte	$4c
	.word	pem
;warm boot-read DOS/65 back except SIM and then
;jump to CCM. IOSTAT and hence the default drive
;and user are not altered by warm boot.
wboot	ldx	#$ff		;set stack
	txs			;pointer
	cld			;set binary mode
	jsr	intlz		;initialize interrupts
	lda	#0		;boot from drive A
	jsr	seldsk		;by telling MONITOR
	jsr	warm		;read system from disk
	lda	iostat		;set default drive
	and	#%00000111	;eight drives only
	jsr	seldsk
	jmp	setup		;go set up
rderr	jmp	($fffc)		;go to monitor
;select disk
seldsk	and	#7		;three LSB's only
	jsr	setdrv		;go to ROM
	sta	sekdsk		;save for later
	asl	a		;multiply by two
	tax			;make an index
	lda	dcbtbl,x	;get address
	ldy	dcbtbl+1,x
	rts
;table of dcb addresses - this version retains old assignment
;letters but re-ordered. will fix that in later version.
dcbtbl	.word	dcbd
	.word	dcbc
	.word	dcbe
	.word	dcbf
	.word	dcba
	.word	dcbb
	.word	dcbg
	.word	dcbh
;see if de-blocking required for sekdsk
;returns number of dos/65 records per physical
;sector in a and
;returns z=1 if no de-blocking required else z=0
tstdbl	ldx	sekdsk		;get desired disk
;see if de-blocking required for disk x
tstdbx	lda	spttbl,x	;get dos/65 records/host sector
	cmp	#1		;test for no deblock
	rts
;table containing number of dos/65 sectors
;per host physical sector.  if entry is 1
;then de-blocking is skipped.
spttbl	.byte	4,4,4,4,4,4,4,4
;table of records/block
rbltbl	.byte	16,16,16,16,16,16,8,16
;home the selected disk
home	lda	hstwrt		;check for pending write
	bne	homed		;there is so skip
	sta	hstact		;clear host active flag
	jmp	fhome		;then home drive
homed	rts			;do nothing
;translate record in ay for nxtdrv - translation is only done for 8 in, sssd
;drives - no longer in system. 
xlate	rts			;do nothing
;	tax			;move low to x
;	lda	sekdsk		;get next drive
;	cmp	#2		;see if drive c
;	beq	doxlate		;if so translate
;	cmp	#3		;see if drive d
;	bne	setshd		;if not no translate
;doxlate	lda	xlt8,x		;else get 8 inch value
;	rts
;setshd	txa			;restore low
;	rts
;sector translation tables
;8 inch
;xlt8	.byte	1,7,13,19,25,5,11,17,23,3,9,15,21
;	.byte	2,8,14,20,26,6,12,18,24,4,10,16,22
;the read entry point takes the place of
;the previous sim definition for read.
;read the selected dos/65 record.
read	ldx	#0		;x <-- 0
	stx	unacnt		;clear unallocated count
	inx			;x <-- 1
	stx	readop		;say is read operation
	stx	rsflag		;must read data
	inx			;x <-- wrual
	stx	wrtype		;treat as unalloc
	jmp	rwoper		;to perform the read
;The write entry point takes the place of
;the previous sim definition for write.
;write the selected dos/65 record.
write	sta	wrtype		;save param from pem
	jsr	tstdbl		;see if one rec/sec
	bne	usewrt		;if not use type passed
	lda	#wrdir		;if is say directory
	sta	wrtype		;to force write
usewrt	ldx	#0		;say is
	stx	readop		;not a read operation
	lda	wrtype		;get write type back
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
;check for write to unallocated record
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
;calculate dos/65 records/track
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
	jsr	rdesec		;to rom
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
;write operation so move from dmaadr to mvepnt
	inx			;x <-- 1
	stx	hstwrt		;hstwrt <-- 1
wmove	lda	$ffff,y
wmoved	sta	$ffff,y
	dey
	bpl	wmove		;loop if more
	bmi	endmve		;else done
;read operation so move from mvepnt to dmaadr
rmove	lda	$ffff,y
rmoved	sta	$ffff,y
	dey
	bpl	rmove		;loop if more
;data has been moved to/from host buffer
endmve	lda	wrtype		;write type
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
writeh	jsr	hcom		;set-up params
	jsr	wrtsec		;to rom
	sta	erflag		;save result
	rts
;set parameters for host read/write
hcom	lda	hstdsk		;set disk number
	jsr	setdrv
	lda	hsttrk		;then track
	ldy	hsttrk+1
	jsr	settrk
	lda	hstsec		;then sector
	ldy	hstsec+1
	jsr	setsec
	ldx	hstdsk		;get host disk
	jsr	tstdbx		;see if de-blocking
	beq	ndblh		;branch if none
	lda	#<hstbuf	;finally address
	ldy	#>hstbuf
	jmp	setbuf
ndblh	lda	dmaadr		;send normal address
	ldy	dmaadr+1	;for no de-blocking
	jmp	setbuf
;set sector number
selsec	sta	seksec		;save low and high
	sty	seksec+1
	jmp	setsec		;go to rom also
;set buffer address
setdma	sta	dmaadr		;store low
	sty	dmaadr+1	;and high
	jmp	setbuf		;go to rom also
;set track
seltrk	sta	sektrk		;save number
	sty	sektrk+1
	jmp	settrk		;go to rom also
;disk control blocks
;drive e (5 inch 1.2 MB) - 1 system track
dcba	.word	595		;max block number
	.word	60		;records per track
	.word	1		;number system tracks
	.byte	1		;block = 2048
	.word	255		;max directory
	.word	almpa		;address of allocation map
	.byte	0		;do checksums
	.word	ckmpa		;address of checksum map
;drive f (Kaypro IV)
dcbb	.word	196		;max block number
	.word	40		;records per track
	.word	1		;number system tracks
	.byte	1		;block size = 2048
	.word	127		;max directory number
	.word	almpb		;address of allocation map
	.byte	0		;do checksums
	.word	ckmpb		;address of checksum map
;drive b (CF 8MB)
dcbc	.word	4095		;max block number
	.word	1024		;records per track
	.word	1		;number system tracks
	.byte	1		;block size = 2048
	.word	1023		;max directory
	.word	almpc		;address of allocation map
	.byte	128		;do not do checksums
	.word	0		;phony address
;drive a (CF 8MB)
dcbd	.word	4095		;max block number
	.word	1024		;records per track
	.word	1		;number system tracks
	.byte	1		;block size = 2048
	.word	1023		;max directory
	.word	almpd		;address of allocation map
	.byte	128		;do not do checksums
	.word	0		;phony address
;drive c (CF 8MB)
dcbe	.word	4095		;max block number
	.word	1024		;records per track
	.word	1		;number system tracks
	.byte	1		;block size = 2048
	.word	1023		;max directory
	.word	almpe		;address of allocation map
	.byte	128		;do not do checksums
	.word	0		;phony address
;drive d (CF 8MB)
dcbf	.word	4095		;max block number
	.word	1024		;records per track
	.word	1		;number system tracks
	.byte	1		;block size = 2048
	.word	1023		;max directory
	.word	almpf		;address of allocation map
	.byte	128		;do not do checksums
	.word	0		;phony address
;drive g (kaypro 2)
dcbg	.word	194		;max block number
	.word	40		;sectors per track
	.word	1		;one system track
	.byte	0		;1024 byte blocks
	.word	127		;128 directory entries
	.word	almpg		;address of allocation map
	.byte	0		;do checksums
	.word	ckmpg		;address of checksum map
;drive h (5 inch 1.2 MB) - 2 system track
dcbh	.word	591		;max block number
	.word	60		;records per track
	.word	2		;number system tracks
	.byte	1		;block = 2048
	.word	255		;max directory
	.word	almph		;address of allocation map
	.byte	0		;do checksums
	.word	ckmph		;address of checksum map
;data area
sekdsk	.byte	0		;seek disk number
hstwrt	.byte	0		;0=written,1=pending host write
;allocate the following data areas to unused ram space
savsec	*=*+1			;save sector for warm boot
count	*=*+1			;counter in warm boot
temp	*=*+1			;save hstdsk for warm boot
hstact	*=*+1			;host active flag
unacnt	*=*+1			;unalloc rec cnt
sektrk	*=*+2			;seek track number
seksec	*=*+2			;seek sector number
hstdsk	*=*+1			;host disk number
hsttrk	*=*+2			;host track number
hstsec	*=*+2			;host sector number
sekhst	*=*+2			;seek shr secshf
unadsk	*=*+1			;last unalloc disk
unatrk	*=*+2			;last unalloc track
unasec	*=*+2			;last unalloc sector
erflag	*=*+1			;error reporting
rsflag	*=*+1			;read sector flag
readop	*=*+1			;1 if read operation
wrtype	*=*+1			;write operation type
d65spt	*=*+2			;dos/65 records/track
dmaadr	*=*+2			;record address
;allocation and checksum maps
;drive e
almpa	*=*+75
ckmpa	*=*+64
;drive f
almpb	*=*+25
ckmpb	*=*+32
;drive b
almpc	*=*+512
;drive a
almpd	*=*+512
;drive c
almpe	*=*+512
;drive d
almpf	*=*+512
;drive g
almpg	*=*+25
ckmpg	*=*+32
;drive h
almph	*=*+74
ckmph	*=*+64
	end
