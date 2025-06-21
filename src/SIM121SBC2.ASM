		globals	on
		case	off
;dos/65 system interface module (SIM)
;version 1.20-W
;This is the WDC tools version derived from SIM415X.ASM.
;This version is designed to work on the SBC2-2.5 with
;the SPI driven micro SD interface.
;disk configuration:
; a SD 8MB (SD.0)
; b SD 8MB (SD.1)
; c SD 8MB (SD.2)
; d SD 8MB (SD.3)
;last revision:
;	29 July 2017 (1.20W)
;		baseline release
;	30 August 2017 (1.21W
;		updated version to match MON change

;		code

;system i/o routines in monitor
mon_intlz	equ	mon_mon		;system initialization
mon_setbuf	equ	mon_mon+24	;set disk buffer address
mon_fhome	equ	mon_mon+33	;home floppy
mon_rdtime	equ	mon_mon+39	;read clock
mon_wrecal	equ	mon_mon+42	;reset SD system
mon_outmsg	equ	mon_mon+48	;output message
;pem constants on entry to write
wrall		equ	0		;write to allocated
wrdir		equ	1		;write to directory
wrual		equ	2		;write to unallocated
;main program
;start of sim
sim
;opening id message
sim_opnmsg	byte	cr,lf,"32K ROM DOS/65 V3.02 SIM V1.21 FOR SBC2",0
;cold entry from loader
sim_boot	lda	#<sim_opnmsg	;point to message
		ldy	#>sim_opnmsg
		jsr	mon_outmsg	;send it
;initialize iostat
		lda	#0		;drive 0 and user 0
		sta	iostat
;set up jumps into dos/65 in page one
sim_setup	ldx	#0		;clear index
;first clear key de-blocking variables
		stx	sim_hstact	;host buffer inactive
		stx	sim_unacnt	;clear unalloc count
?L2		lda	sim_inttbl,x	;get byte
		sta	$100,x		;insert at start
		inx
		cpx	#6
		bne	?L2		;loop until done
		lda	#<dflbuf	;get low buffer
		ldy	#>dflbuf	;and high
		jsr	sim_setdma	;and set
		jmp	ccmram		;and go to CCM
;initialization table
sim_inttbl	byte	$4c
		word	sim_wboote
		byte	$4c
		word	pemram
;warm boot-read DOS/65 back except SIM and then
;jump to CCM. IOSTAT and hence the default drive
;and user are not altered by warm boot.
sim_wboot	ldx	#$ff		;set stack
		txs			;pointer
		cld			;set binary mode
;		jsr	mon_intlz	;initialize interrupts
		lda	#0		;boot from drive A
		jsr	sim_seldsk	;by telling MONITOR
		jsr	mon_warm	;read system from disk
		lda	iostat		;set default drive
		and	#%00000111	;eight drives only
		jsr	sim_seldsk
		jmp	sim_setup	;go set up

;select disk
sim_seldsk	and	#7		;three LSB's only
		jsr	mon_setdrv	;go to ROM
		sta	sim_sekdsk	;save for later
		asl	a		;multiply by two
		tax			;make an index
		lda	sim_dcbtbl,x	;get address
		ldy	sim_dcbtbl+1,x
		rts
;table of dcb addresses.
sim_dcbtbl	word	dcba
		word	dcbb
		word	dcbc
		word	dcbd
		word	0
		word	0
		word	0
		word	0
;see if de-blocking required for sekdsk
;returns number of dos/65 records per physical
;sector in a and
;returns z=1 if no de-blocking required else z=0
sim_tstdbl	ldx	sim_sekdsk	;get desired disk
;see if de-blocking required for disk x
sim_tstdbx	lda	sim_spttbl,x	;get dos/65 records/host sector
		cmp	#1		;test for no deblock
		rts
;table containing number of dos/65 records
;per host physical sector.  if entry is 1
;then de-blocking is skipped.
;note that these two tables contain eight
;entries even though only the first four are used.
sim_spttbl	byte	4,4,4,4,4,4,4,4
;table of records/block
sim_rbltbl	byte	16,16,16,16,16,16,16,16
;home the selected disk
sim_home	lda	sim_hstwrt	;check for pending write
		bne	?X2		;there is so skip
		sta	sim_hstact	;clear host active flag
		jmp	mon_fhome	;then home drive if floppy
?X2		rts			;do nothing
;translate record in ay for nxtdrv - translation is only done for 8 in, sssd
;drives - no longer in system. 
sim_xlate	rts			;do nothing
;read the selected dos/65 record.
sim_read	ldx	#0		;x <-- 0
		stx	sim_unacnt	;clear unallocated count
		inx			;x <-- 1
		stx	sim_readop	;say is read operation
		stx	sim_rsflag	;must read data
		inx			;x <-- wrual
		stx	sim_wrtype	;treat as unalloc
		jmp	sim_rwoper	;to perform the read
;write the selected dos/65 record.
sim_write	sta	sim_wrtype	;save param from pem
		jsr	sim_tstdbl	;see if one rec/sec
		bne	?B2		;if not use type passed
		lda	#wrdir		;if is say directory
		sta	sim_wrtype	;to force write
?B2		ldx	#0		;say is
		stx	sim_readop	;not a read operation
		lda	sim_wrtype	;get write type back
		cmp	#wrual		;write unallocated?
		bne	?B3		;check for unalloc
;write to unallocated, set parameters
		ldx	sim_sekdsk	;get next disk number
		lda	sim_rbltbl,x	;get records/block
		sta	sim_unacnt
		stx	sim_unadsk	;unadsk <-- sekdsk
		lda	sim_sektrk
		ldy	sim_sektrk+1
		sta	sim_unatrk	;unatrk <-- sectrk
		sty	sim_unatrk+1
		lda	sim_seksec
		ldy	sim_seksec+1
		sta	sim_unasec	;unasec <-- seksec
		sty	sim_unasec+1
;check for write to unallocated record
?B3		lda	sim_unacnt	;any unalloc remain?
		beq	sim_alloc	;skip if not
;more unallocated records remain
		dec	sim_unacnt	;unacnt <-- unacnt-1
		lda	sim_sekdsk
		cmp	sim_unadsk	;sekdsk = unadsk?
		bne	sim_alloc	;skip if not
;disks are the same
		lda	sim_unatrk	;sektrk = unatrk?
		cmp	sim_sektrk
		bne	sim_alloc	;no so skip
		lda	sim_unatrk+1
		cmp	sim_sektrk+1
		bne	sim_alloc	;skip if not
;tracks are the same
		lda	sim_unasec	;seksec = unasec?
		cmp	sim_seksec
		bne	sim_alloc	;no so skip
		lda	sim_unasec+1
		cmp	sim_seksec+1
		bne	sim_alloc	;skip if not
;match, move to next sector for future ref
		inc	sim_unasec	;unasec = unasec+1
		bne	?B4
		inc	sim_unasec+1
;calculate dos/65 records/track
?B4		lda	sim_sekdsk	;get disk number
		asl	a		;mult by two
		tax			;make an index
		lda	sim_dcbtbl,x	;get dcb start
		ldy	sim_dcbtbl+1,x
		sta	sim_dcbpnt	;set low operand
		sty	sim_dcbpnt+1	;then high operand
;point has address now get spt at byte 2,3
		ldy	#2		;start at byte 2
		ldx	#0		;start save in low
?B5		lda	(sim_dcbpnt),y	;get value
		sta	sim_d65spt,x	;and save
		iny
		inx
		cpx	#2		;see if done
		bne	?B5		;loop if not
;check for end of track
		lda	sim_unasec	;end of track?
		cmp	sim_d65spt	;count dos/65 sectors
		lda	sim_unasec+1
		sbc	sim_d65spt+1
		bcc	?B6		;skip if no overflow
;overflow to next track
		lda	#0		;unasec <-- 0
		sta	sim_unasec
		sta	sim_unasec+1
		inc	sim_unatrk	;unatrk <-- unatrk+1
		bne	?B6
		inc	sim_unatrk+1
;match found, mark as unnecessary read
?B6		lda	#0		;0 to accumulator
		sta	sim_rsflag	;rsflag <-- 0
		beq	sim_rwoper	;to perform the write
;not an unallocated record, requires pre-read
sim_alloc	ldx	#0		;x <-- 0
		stx	sim_unacnt	;unacnt <-- 0
;say preread required
		inx			;x <-- 1
		stx	sim_rsflag	;rsflag <-- 1
;check for single record/sector - and if so
;then say preread not required.
		jsr	sim_tstdbl	;test
		bne	sim_rwoper	;more than one
		lda	#0		;say no preread
		sta	sim_rsflag
;common code for read and write follows
;enter here to perform the read/write
sim_rwoper	lda	#0		;zero to accum
		sta	sim_erflag	;no errors (yet)
		lda	sim_seksec	;compute host sector
		ldy	sim_seksec+1
		sta	sim_sekhst
		sty	sim_sekhst+1
		jsr	sim_tstdbl	;get records/sector
		lsr	a		;divide by two
		tax			;make a counter
		beq	?B2		;done if zero
?L2		lsr	sim_sekhst+1	;do high
		ror	sim_sekhst	;then low
		dex
		bne	?L2		;loop if more
;active host sector?
?B2		lda	sim_hstact	;host active flag
		pha			;save
		inx			;x <-- 1
		stx	sim_hstact
		pla			;get flag back
		beq	sim_filhst	;fill host if not active
;host buffer active, same as seek buffer?
		lda	sim_sekdsk
		cmp	sim_hstdsk	;same disk?
		bne	sim_nmatch
;same disk, same track?
		lda	sim_hsttrk	;sektrk = hsttrk?
		cmp	sim_sektrk
		bne	sim_nmatch	;no
		lda	sim_hsttrk+1
		cmp	sim_sektrk+1
		bne	sim_nmatch
;same disk, same track, same sector?
		lda	sim_sekhst	;sekhst = hstsec?
		cmp	sim_hstsec
		bne	sim_nmatch	;no
		lda	sim_sekhst+1
		cmp	sim_hstsec+1
		beq	sim_match	;skip if match
;proper disk, but not correct sector
sim_nmatch	lda	sim_hstwrt	;host written?
		beq	sim_filhst	;skip if was
		jsr	sim_writeh	;else clear host buff
;may have to fill the host buffer
;so set host parameters
sim_filhst	lda	sim_sekdsk
		sta	sim_hstdsk
		lda	sim_sektrk
		ldy	sim_sektrk+1
		sta	sim_hsttrk
		sty	sim_hsttrk+1
		lda	sim_sekhst
		ldy	sim_sekhst+1
		sta	sim_hstsec
		sty	sim_hstsec+1
		lda	sim_rsflag	;need to read?
		beq	sim_noread	;no
;read desired physical sector from host
		jsr	sim_hcom	;set parameters
		jsr	mon_rdesec	;to rom
		sta	sim_erflag	;save result
sim_noread	lda	#0		;0 to accum
		sta	sim_hstwrt	;no pending write
;copy data to or from buffer
sim_match	lda	#0		;clear move pointer
		sta	sim_movepnt	;later we'll set read
		sta	sim_movepnt+1
		jsr 	sim_tstdbl	;get records/sector
		beq	sim_endmve		;done if no deblocking
		tax			;drop by one
		dex
		txa
		and	sim_seksec	;mask sector number
		tax			;make a counter
		beq	sim_nooff	;done if zero
?L2		clc
		lda	sim_movepnt
		adc	#128
		sta	sim_movepnt
		lda	sim_movepnt+1
		adc	#0
		sta	sim_movepnt+1
		dex
		bne	?L2		;loop if more
;pointer has relative host buffer address
sim_nooff		clc		;add hstbuf
		lda	#<hstbuf
		adc	sim_movepnt
		sta	sim_movepnt
		lda	#>hstbuf
		adc	sim_movepnt+1
		sta	sim_movepnt+1
;at this point pointer contains the address of the
;record of interest in the hstbuf buffer.
		ldy	#127		;length of move - 1
		ldx	sim_readop	;which way?
		bne	sim_rmove	;skip if read
;write operation so move from dmaadr to mvepnt
		inx			;x <-- 1
		stx	sim_hstwrt	;hstwrt <-- 1
?L2		lda	(sim_dmaadr),y
		sta	(sim_movepnt),y
		dey
		bpl	?L2		;loop if more
		bmi	sim_endmve	;else done
;read operation so move from mvepnt to dmaadr
sim_rmove	lda	(sim_movepnt),y
		sta	(sim_dmaadr),y
		dey
		bpl	sim_rmove	;loop if more
;data has been moved to/from host buffer
sim_endmve	lda	sim_wrtype	;write type
		cmp	#wrdir		;to directory?
		bne	?B2		;done if not
;clear host buffer for directory write
		lda	sim_erflag	;get error flag
		bne	?B2		;done if errors
		sta	sim_hstwrt	;say buffer written
		jsr	sim_writeh
?B2		lda	sim_erflag
		rts	
;writeh performs the physical write to
;the host disk.
sim_writeh	jsr	sim_hcom	;set-up params
		jsr	mon_wrtsec	;to rom
		sta	sim_erflag	;save result
		rts
;set parameters for host read/write
sim_hcom	lda	sim_hstdsk	;set disk number
		jsr	mon_setdrv
		lda	sim_hsttrk	;then track
		ldy	sim_hsttrk+1
		jsr	mon_settrk
		lda	sim_hstsec	;then sector
		ldy	sim_hstsec+1
		jsr	mon_setsec
		ldx	sim_hstdsk	;get host disk
		jsr	sim_tstdbx	;see if de-blocking
		beq	?B2		;branch if none
		lda	#<hstbuf	;finally address
		ldy	#>hstbuf
		jmp	mon_setbuf
?B2		lda	sim_dmaadr	;send normal address
		ldy	sim_dmaadr+1	;for no de-blocking
		jmp	mon_setbuf
;set sector number
sim_selsec	sta	sim_seksec	;save low and high
		sty	sim_seksec+1
		jmp	mon_setsec	;go to rom also
;set buffer address
sim_setdma	sta	sim_dmaadr	;store low
		sty	sim_dmaadr+1	;and high
		jmp	mon_setbuf	;go to rom also
;set track
sim_seltrk	sta	sim_sektrk	;save number
		sty	sim_sektrk+1
		jmp	mon_settrk	;go to rom also
;disk control blocks
;drive a (SD 8MB)
dcba		word	4095		;max block number
		word	1024		;records per track
		word	0		;number system tracks
		byte	1		;block size = 2048
		word	1023		;max directory
		word	almpa		;address of allocation map
		byte	128		;do not do checksums
		word	0		;phony address
;drive b (SD 8MB)
dcbb		word	4095		;max block number
		word	1024		;records per track
		word	0		;number system tracks
		byte	1		;block size = 2048
		word	1023		;max directory
		word	almpb		;address of allocation map
		byte	128		;do not do checksums
		word	0		;phony address
;drive c (SD 8MB)
dcbc		word	4095		;max block number
		word	1024		;records per track
		word	0		;number system tracks
		byte	1		;block size = 2048
		word	1023		;max directory
		word	almpc		;address of allocation map
		byte	128		;do not do checksums
		word	0		;phony address
;drive d (SD 8MB)
dcbd		word	4095		;max block number
		word	1024		;records per track
		word	0		;number system tracks
		byte	1		;block size = 2048
		word	1023		;max directory
		word	almpd		;address of allocation map
		byte	128		;do not do checksums
		word	0		;phony address
;data area
;sim_sekdsk	byte	0		;seek disk number
;sim_hstwrt	byte	0		;0=written,1=pending host write
;allocate the following data areas to unused ram space
;sim_hstact	defs	1		;host active flag
;sim_unacnt	defs	1		;unalloc rec cnt
;sim_sektrk	defs			;seek track number
;sim_seksec	defs	2		;seek sector number
;sim_hstdsk	defs	1		;host disk number
;sim_hsttrk	defs	2		;host track number
;sim_hstsec	defs	2		;host sector number
;sim_sekhst	defs	2		;seek shr secshf
;sim_unadsk	defs	1		;last unalloc disk
;sim_unatrk	defs	2		;last unalloc track
;sim_unasec	defs	2		;last unalloc sector
;sim_erflag	defs	1		;error reporting
;sim_rsflag	defs	1		;read sector flag
;sim_readop	defs	1		;1 if read operation
;sim_wrtype	defs	1		;write operation type
;sim_d65spt	defs	2		;dos/65 records/track
;;allocation and checksum maps
;drive a
;almpa		defs	512
;drive b
;almpb		defs	512
;drive c
;almpc		defs	512
;drive d
;almpd		defs	512
;host buffer
;hstbuf		defs	512		;

;		ends

		end
