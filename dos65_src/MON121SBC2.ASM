		globals	on
		case	off
		chip	65c02
		inclist	on
		condlist	on
;SBC2-2./5 MONITOR FOR SIM 1.21W
;Works with ROM version of DOS/65 based on v3.0.
;Console I/O uses the on board ACIA.
;This version is configured for the following disk drives:
;	A	SD 8 MB drive (SD.0)
;	B	SD 8 MB drive (SD.1)
;	C	SD 8 MB drive (SD.2)
;	D	SD 8 MB drive (SD.3)
;	E	n/a
;	F	n/a
;	G	n/a
;	H	n/a

;monitor, DOS/65, LBA design written by Richard Leary
;definition of the VIA registers, low level SPI interfsce,
;and much of the SD card interfasce written by Andre Fachat
;but heavily modified.

;    Copyright (C) 1989-1997 Andre Fachat 
;    Copyright (C) 1981-2017 Richard Leary

;    This program is free software; you can redistribute it and/or modify
;    it under the terms of the GNU General Public License as published by
;    the Free Software Foundation; either version 2 of the License, or
;    (at your option) any later version.

;    This program is distributed in the hope that it will be useful,
;    but WITHOUT ANY WARRANTY; without even the implied warranty of
;    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;    GNU General Public License for more details.

;    You should have received a copy of the GNU General Public License
;    along with this program; if not, write to the Free Software
;    Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

;****************************************************************************/
;released:	17 July 2017 (1.20W)
;			baseline 
;		29 August 2017 (1.21W)
;			incorporate fixes from SD_TEST 1.24
;fixed parameters
clreol		equ	1		;clear to eol (ctl-a)
clreos		equ	2		;clear to eos (ctl-b)
bs		equ	8		;backspace (ctl-h)
esc		equ	$1b		;escape char

;**********************************************************************
;i/o port assignments and data definitions
;**********************************************************************

;define base address of VIA
SD_VIA		EQU	$7F50

;VIA related definitions
SD_CLK		equ	8		;clock counter
SD_SEL		equ	4
SD_INVCLK	equ	2
SD_INVDAT	equ	1

VIA_DRB		equ	0
VIA_DRA		equ	1
VIA_DDRB	equ	2
VIA_DDRA	equ	3
VIA_T1CL	equ	4
VIA_T1CH	equ	5
VIA_T1LL	equ	6
VIA_T1LH	equ	7
VIA_T2CL	equ	8
VIA_T2CH	equ	9
VIA_SR		equ	10
VIA_ACR		equ	11
VIA_PCR		equ	12
VIA_IFR		equ	13
VIA_IER		equ	14
VIA_DRBX	equ	15

;define the ACIA addresses
ACIABase	equ	$7F70
ACIAdat		equ	ACIABase
ACIAsta		equ	ACIABase+1
ACIAcmd		equ	ACIABase+2
ACIActl		equ	ACIABase+3
;
;This code uses 32-bit LBA addressing.
**********************************************************************

		code
;**********************************************************************
;code section
;**********************************************************************
;jump vectors
;start DOS/65
		jmp	dos_entry
;system halt
		jmp	($fffc)		;jump to monitor
;console status
		jmp	chkc
;console read
		jmp	mon_conrde
;console write
		jmp	mon_conwrt
;set drive number
		jmp	mon_setdrv
;set track
		jmp	mon_settrk
;set sector
		jmp	mon_setsec
;set buffer location
		jmp	mon_setdma
;read sector
		jmp	mon_rdesec
;write sector
		jmp	mon_wrtsec
;home floppy drive
		jmp	mon_home
;printer write
		nop
		nop
		rts
;read clock
		nop
		nop
		rts
;recal SD & controller
		nop
		nop
		rts
;read CCM & PEM RAM data and code from ROM
		jmp	mon_warm
;send string to console
		jmp	mon_txtout
;data for main loop or global need
cmd0		byte	$40,0,0,0,0,$95
cmd1		byte	$41,0,0,0,0,$ff
cmd8		byte	$48,0,0,1,$aa,$87
cmd10		byte	$4A,0,0,0,0,$ff
cmd55		byte	$77,0,0,0,0,$ff
cmd58		byte	$7a,0,0,0,0,$ff
ac41		byte	$69,0,0,0,0,$ff
;show SD error message and restart monitor
SHOWERRORS	lda	#<ioemsg	;point to error message
		ldy	#>ioemsg
		jsr	mon_txtout	;send it
;monitor entry
dos_entry	ldx	#$ff		;set
		txs			;stack pointer
;initialize all of ram by transferring block from
;ROM location to start of RAM. All monitor and
;DOS/65 non-page 0 RAM is initialized.
		jsr	mon_coldsetup	;set up for cold boot
		jsr	mon_bootxfer	;do transfer
		cld
		sei			;disable interrupts
;output opening message
		lda	#<mon_opnmsg	;point to message
		ldy	#>mon_opnmsg
		jsr	mon_txtout	;send it
;set point to valid ram
		lda	#5		;use valid loc for WDC
		sta	mon_point	;save
		stz	mon_point+1
		jsr	mon_crlf
		jsr	sd_reset
		jsr	mon_crlf
		LDA	#<ocrmsg	;print OCR message
		ldy	#>OCRMSG
		JSR	mon_txtout
		jsr	sd_cmd58	;read OCR (Operations Condition Register)
		jsr	mon_crlf
		lda	#<cidmsg	;print cidmessage
		ldy	#>cidmsg
		jsr	mon_txtout
		jsr	sd_cmd10	;read CID (Card Identification register)

;put system in high clock rate mode
;---------------------------------
; Alternative 2 - shift out under Phi2
;
; if your hardware is fast enough, you can
; shift out under control of phi2

; set up shift register mode to output
; under phi2 control, which makes bits go out
; on half phi2.
		lda	SD_VIA+VIA_ACR
		and	#%11111011
		ora	#%00011000
		sta	SD_VIA+VIA_ACR

;dos/65 bootstrap from ROM by going to SIM to start
;the process. Code and data that the LINKER placed in ROM at
;ROM address has already been transfered.
mon_boot	jmp	sim_boot	;execute
;warm boot dos/65 CCM & PEM from ROM. this is called from
;SIM and returns where SIM executes refreshed system.
mon_warm	jsr	mon_warmsetup	;read parameters
		jsr	mon_bootxfer	;do transfer
		rts
;setup cold boot
mon_coldsetup	lda	#<romorg	;point to rom start
		ldy	#>romorg
		sta	mon_in		;set from pointer
		sty	mon_in+1
		lda	#<ccmram	;point to destination
		ldy	#>ccmram
		sta	mon_point	;set to pointer
		sty	mon_point+1
		ldx	#coldpages	;get number pages
		ldy	#0		;clear index
		rts

;do boot transfer
mon_bootxfer	lda	(mon_in),y	;get byte from rom
		sta	(mon_point),y	;move to ram
		iny
		bne	mon_bootxfer	;loop if more in page
		dex			;drop page count
		beq	?X2		;done if zero
		inc	mon_in+1	;else bump high pointers
		inc	mon_point+1
		bra	mon_bootxfer	;loop for next page
?X2		rts
;setup warm boot
mon_warmsetup	jsr	mon_coldsetup
		ldx	#warmpages
		rts

;standard character I/O routines

;wait for CR to be entered to proceed
mon_wait_cr	lda	#<mon_crmsg	;send message
		ldy	#>mon_crmsg
		jsr	mon_txtout
?L2		jsr	chkc		;see if character
		beq	?L2		;loop if none
		jsr	getc7		;get character
		cmp	#cr		;see if cr
		bne	?L2		;loop if not
		rts

;send null terminated string to console. note that routine will
;also be terminated if high byte of pointer wraps from $FF to $00.
;Input: a and y are low and high bytes of string start
;Output: carry clear
;Assumes: putc does not alter y
mon_txtout	sta	stdio_d1	;save pointer
		sty	stdio_d1+1
		ldy	#0
?L2		lda	(stdio_d1),y	;get character
		beq	?E2		;done if zero
		jsr	mon_conwrt	;send character
		iny			;bump index
		bne	?L2		;loop if no rollover
		inc	stdio_d1+1	;else bump high byte of pointer
		bne	?L2		;and loop unless rollover
?E2		clc			;say no error
		rts

;output byte as decimal. note that as written this code ignores 100s
;causing 100 to display as 00, 101 as 91 etc.
;Input: a
dzbout
?L2		tay			;save input in y
		sec
		sbc	#100		;subtract 100 while no borrow
		bcs	?L2
		lda	#0
		sta	stdio_d1
		tya			;get last value before borrow
?L3		tay			;use y as 1s holder
		sec
		sbc	#10
		bcc	?L4
		inc	stdio_d1	;bump 10s if no borrow then
		bcs	?L3		;loop
?L4		asl	stdio_d1	;shift 19s to hugh nibble
		asl	stdio_d1
		asl	stdio_d1
		asl	stdio_d1
		tya			;get 1s value
		ora	stdio_d1	;or with 10s and fall through

;output byte as two hex nibbles
hexout		pha			;save for low nibble
		lsr	a		;move high to low
		lsr	a
		lsr	a
		lsr	a
		jsr	nibout		;output high
		pla			;get input back
		and	#$0f		;zero out high
nibout		clc			;make AsCII
		adc	#'0'
		cmp	#'9'+1		;see if 0 to 9
		bcc	nibok		;is so ok
		adc	#6		;else make A to F
nibok		jmp	PUTC

;convert lowercase to uppercase
mon_LowrUppr	cmp	#'a'		;see if < a
		bcc	?X2		;done if is
		cmp	#'z'+1		;see if > z
		bcs	?X2		;done if is
		and	#$5f		;else convert
?X2		rts

;send byte to printer
mon_prnwrt	rts			;nothing for now

;same as PUTC but clear highest bir
PUTC7		and	#$7F
;print character in A to stdout
;keep X and Y, but not necessarily S
PUTC		pha			;save char
?E2		lda	ACIAsta		;get status
		and	#$10		;isolate xmit empty
		beq	?E2		;loop if not empty
		pla			;get char back
		sta	ACIAdat		;send it
		rts

;check for character ready at input
;returns a=0 and z=0 if none and a=1 and z-0 if ready 
mon_consts
CHKC		lda	ACIASta		;get status
		and	#$08		;check receive ready
		beq	?E2		;say not ready
		lda	#1		;say ready
?E2		rts

;wait until character ready then get character
WAITC		jsr	CHKC		;see if character
		beq	WAITC		;loop if none ekse
;get a character from stdin
;call only after CHKC says character is ready
;keep X and Y, but not necessarily S
;C=0 on return is ok, C=1 on return is eof
GETC		lda	ACIAdat		;get character
		clc
		rts

;same as GETC but clear high bit
GETC7		jsr	GETC
		and	#$7F
		rts

;get keyboard input
;this routine waits until a key is pressed. it also
;converts any input bs to a delete to match cp/m
;console behaviour.
mon_conrde	jsr	waitc		;wait for character
		and	#$7f
;see if backspace and if so convert to delete
		cmp	#bs		;check for bs
		bne	?X2		;use as is if not
		lda	#delete		;else make delete
?X2		rts
;monitor cr and lf
mon_crlf	lda	#cr
		jsr	mon_conwrt
		lda	#lf
		bne	mon_conwrt	;send and return
;output a space
mon_outsp	lda	#' '
;console write
;alters:a,p
;As written it implements some Wyse 50 screen handling.
mon_conwrt	pha			;save char on stack
		and	#$7f		;clear msb
		cmp	#delete		;see if delete
		bne	?B2		;isn't
		lda	#' '		;else make space
?B2		cmp	#clreol		;see if clear to eol
		bne	?B3		;not so skip
		lda	#esc		;else get an esc
		jsr	putc		;send it
		lda	#'T'		;then a cap T
		jsr	putc
		bra	?X2		;then exit
?B3		cmp	#clreos		;see if clear to eos
		bne	?B4		;not so jump
		lda	#esc		;send esc sequence
		jsr	putc
		lda	#'Y'		;and y
		jsr	putc
		bra	?X2		;then exit
?B4		jsr	putc		;send as regular char
?X2		pla			;get char back
		rts
;output pointer as two bytes
mon_outpnt	lda	mon_point+1	;high byte
		jsr	mon_outbyt
		lda	mon_point
;output byte as two nibbles
mon_outbyt	pha
		lsr	A
		lsr	A
		lsr	A
		lsr	A
		jsr	hex
		pla
;output a hex nibble
hex		and	#$F
		ora	#'0'
		cmp	#'9'+1
		bcc	hex1
		adc	#6
hex1		jmp	mon_conwrt		;go to output
;check for HD and set z=1 if HD is nxtdrv
testhd		lda	mon_nxtdrv	;get next
		cmp	#0		;see if A:
		beq	ishd		;done if is
		cmp	#1		;see if B:
		beq	ishd		;done if is
		cmp	#2		;see if C:
		beq	ishd		;done if is
		cmp	#3		;see if D:
ishd		rts
;set drive for rdesec/wrtsec/home/rest
mon_setdrv	sta	mon_nxtdrv	;save
		rts
;set sector number
mon_setsec	sta	mon_nxtsec		;save low and high
		sty	mon_nxtsec+1
		rts
;set buffer address
;alters:none
mon_setdma	sta	dma		;store low
		sty	dma+1		;and high
		rts			;then return
;move to track zero
;note that for IDE this entry does nothing!!!
mon_home	stz	mon_nxttrk		;clear current track
		stz	mon_nxttrk+1
		rts			;done
;set track
mon_settrk	sta	mon_nxttrk		;save number
		sty	mon_nxttrk+1
		rts
;delay twelve cpu cycles
twelve		rts
;hard disk routines
;
;Write the logical block address to the 32 bit storage area.
;In the following description I show them as MSB | LSB
;At entry nxtsec contains 0 to 255
;			00000000|ssssssss
;and nxttrk contains 0 to 63.
;			00000000|00tttttt
;first step is to copy nxtsec to lba with end result being
;			ssssssss in lba
;then copy nxttrk to lba+1 & clear lba+2 and lba+3
;so lba+3|lba+2|lba+1|lba look like:
;	00000000|00000000|00tttttt|ssssssss
;This is used as is for drive A and for other drives an
;offset of 16384 for each previous drive is added
;to the LBA number.
wrlba		lda	mon_nxtsec	;start with sector and
;save in lba
		sta	lba
;now copy nxttrk to chain
		lda	mon_nxttrk	;get low
		sta	lba+1		;save and clear next
		stz	lba+2		;and clear high byte
		stz	lba+3		;and highest byte
;The LBA data assumed drive always started at LBA=0.
;Initially that means drive A: is used as calculated.
;Drives B - D must have an offset added in.
;Each drive = 8 MB = 16384 512-byte sectors.
		lda	mon_nxtdrv	;get drive number
		asl	a		;multiply by two
		tax			;move offset index to
		clc			;clear carry
		lda	lba		;get lba
		adc	offset,x	;add low of offset
		sta	lba		;and save
		lda	lba+1		;do same for high
		inx
		adc	offset,x
		sta	lba+1
;now let's handle any carry - will possibly be in later partitions
		lda	lba+2		;get next two bytes
		adc	#0
		sta	lba+2		;including highest
		lda	lba+3
		adc	#0
		sta	lba+3
;now change lba to reflect fact that SDSC cards use a byte pointer.
;this means shifting lba 9 bits left. we will do the first 8
;by shifting whole bytes.
		lda	lba+2
		sta	lba+3
		lda	lba+1
		sta	lba+2
		lda	lba
		sta	lba+1
		stz	lba
;now shift one more bit in 0, 1, 2, and 3
		asl	lba
		rol	lba+1
		rol	lba+2
		rol	lba+3
;at this point LBA address is calculated and stored
		rts
;Table of LBA offsets for drives A, B, C, & D
Offset		word	0		;drive a
		word	16384		;drive b
		word	32768		;drive c
		word	49152		;drive d
;Read a block, specified by the 4 bytes in LBA
;Z on success, NZ call error routine if problem
mon_rdesec
READSECTOR
		jsr	WRLBA		;Compute which sector we want to read
		lda	lba+3		;fll in block in command
		sta	cmd17+1
		lda	lba+2
		sta	cmd17+2
		lda	lba+1
		sta	cmd17+3
		lda	lba
		sta	cmd17+4
		jmp	sd_read_blk

;Write a block, specified by the 4 bytes in LBA 
;Z on success, NZ to error routine if problem
;write dos/65 sector to SD
;return with a=0 if ok or a<>0 if error
mon_wrtsec
WRITESECTOR	jsr	WRLBA		;Compute sector we want to write
		lda	lba+3		;fill in write
		sta	cmd24+1
		lda	lba+2
		sta	cmd24+2
		lda	lba+1
		sta	cmd24+3
		lda	lba
		sta	cmd24+4
		jmp	sd_write_blk

;reset the sd card
sd_reset	jsr	SD_INIT

;send 10 $ff bytes while deselected
		jsr	SD_DESELECT
		jsr	SD_SENDRESETBYTES
;send up to 255 CMD0
		lda	#255
		sta	cmd_cnt		;try CMD0 10x
;send CMD0
sd_cmd0		jsr	SD_SELECT
		lda	#<cmd0
		ldy	#>cmd0
		jsr	sd_send_cmd
		jsr	sd_readbyte	;get response
		sta	cmd0_resp	;save it
		lda	#$ff		;send 8 clocks
		jsr	SD_SENDBYTEW
		jsr	SD_DESELECT	;deselect
		lda	cmd0_resp	;get response back
		cmp	#%00000001	;see if in idle
		beq	OK1		;it is so done
		dec	cmd_cnt		;drop count
		bne	sd_cmd0		;try again if not zeroe
		LDA	#<cmd0_msg
		ldy	#>cmd0_msg
		jsr	mon_txtout
		lda	cmd0_resp
		jsr	Hexout
		jmp	($FFFC)
;send cmd8
;This command must be sent immediately after CMD0. If
;an "illegal command" response is received the card is
;a V1 card.
OK1		jsr	SD_SELECT
		lda	#<cmd8
		ldy	#>cmd8
		jsr	sd_send_cmd
		jsr	sd_readbyte	;get response
		sta	cmd8_resp	;save it
		jsr	sd_readbyte	;read four more bytes
		jsr	sd_readbyte	;of response.
		jsr	sd_readbyte
		jsr	sd_readbyte
		lda	#$ff		;send 8 clocks
		jsr	SD_SENDBYTEW
		jsr	SD_DESELECT	;deselect
		lda	cmd8_resp	;get response back
		and	#%00000100	;look for illegal
		bne	V1card		;it is so done

V2Card
;continue initialization for V2 card by sending
;ACMD41 command with HCS = 0.
		jsr	sd_select
acloop		lda	#<ac41
		ldy	#>ac41
		jsr	sd_send_acmd
		jsr	sd_readbyte
		and	#%00000101
		beq	InitOK
;send cmd1
V1Card
;send up to 32768 CMD1
		lda	#255
		sta	cmd_cnt
		lda	#127
		sta	cmd_cnt+1
sd_cmd1		jsr	SD_SELECT
		lda	#<cmd1
		ldy	#>cmd1
		jsr	sd_send_cmd
		jsr	sd_readbyte	;save first byte
		sta	cmd1_resp
		jsr	sd_readbyte	;flush other bytes
		jsr	sd_readbyte
		jsr	sd_readbyte
		jsr	sd_readbyte
		jsr	sd_readbyte
		jsr	sd_readbyte
		lda	#$ff
		jsr	SD_SENDBYTEW
		jsr	SD_DESELECT
		lda	cmd1_resp
		cmp	#%00000000	;see if ready
		beq	OK2
		dec	cmd_cnt
		bne	sd_cmd1
		dec	cmd_cnt+1
		bne	sd_cmd1
		lda	#<cmd1_msg
		ldy	#>cmd1_msg
		jsr	mon_txtout
		lda	cmd1_resp	;get response again
		jsr	Hexout
		lda	#$ff
		jsr	SD_SENDBYTEW
		jsr	SD_DESELECT
		jmp	($FFFC)
initok
ok2
		lda	#$ff
		jsr	SD_SENDBYTEW
		jsr	SD_DESELECT
		rts


;read operations conditions register (ocr)
;response R3
sd_cmd58	jsr	SD_SELECT
		lda	#<cmd58
		ldy	#>cmd58
		jsr	sd_send_cmd
		jsr	sd_readbyte
		sta	cmd58_resp	;save for later
		jsr	SD_READBYTE
		jsr	Hexout
		jsr	SD_READBYTE
		jsr	Hexout
		jsr	SD_READBYTE
		jsr	Hexout
		jsr	SD_READBYTE
		jsr	Hexout
		lda	#$ff
		jsr	SD_SENDBYTEW
		jsr	SD_DESELECT
		clc
		rts

;write a single block to the SD card
sd_write_blk	jsr	SD_SELECT
		lda	#<cmd24
		ldy	#>cmd24
		jsr	sd_send_cmd
		jsr	sd_readbyte
		cmp	#0
		bne	wblk_err
		lda	#<hstbuf
		ldy	#>hstbuf
		sta	wblk_ptr
		sty	wblk_ptr+1
		lda	#$fe
		jsr	SD_SENDBYTEW	;start data token
		ldy	#0
?l3		lda	(wblk_ptr),y
		jsr	SD_SENDBYTEW
		iny
		bne	?l3
		inc	wblk_ptr+1
?l4		lda	(wblk_ptr),y
		jsr	SD_SENDBYTEW
		iny
		bne	?l4
		lda	#$FF
		jsr	SD_SENDBYTEW	;CRC
		lda	#$FF
		jsr	SD_SENDBYTEW	;CRC
		jsr	SD_READBYTE	;data response token
		sta	cmd24_resp	;save for later
		and	#%00011111
		cmp	#%00000101
		bne	wblk_err
;wait busy
?lbsy		jsr	SD_READBYTE
		cmp	#$ff
		bne	?lbsy
		jsr	sd_sendbytew
		jsr	SD_DESELECT
		clc
		lda	#0		;no error
		rts
;error exits
wblk_err	lda	#<cmd24_msg
		ldy	#>cmd24_msg
		jsr	mon_txtout
		lda	cmd24_resp
		jsr	Hexout
		jsr	sd_sendbytew
		jsr	sd_deselect
		sec
		lda	#1		;error
		rts

;read single block from SD card
sd_read_blk	jsr	SD_SELECT
		lda	#<cmd17
		ldy	#>cmd17
         	jsr	sd_send_cmd
		jsr	sd_readbyte
		sta	cmd17_resp
		lda	#<hstbuf
		ldy	#>hstbuf
 		sta	rblk_ptr
		sty	rblk_ptr+1
;get data block
?L5		jsr	SD_READBYTE
		cmp	#$fe
		bne	?L5		;loop for start token
		ldy	#0
?l3		jsr	SD_READBYTE
		sta	(rblk_ptr),y
		iny
		bne	?l3
		inc	rblk_ptr+1
?l4		jsr	SD_READBYTE
		sta	(rblk_ptr),y
		iny
		bne	?l4
		jsr	sd_readbyte	;read but ignore crc
		jsr	sd_readbyte
		lda	#$ff
		jsr	SD_SENDBYTEW
		jsr	SD_DESELECT
		clc
		lda	#0		;no error
		rts
;error handling
rblk_err	lda	#<cmd17_msg
		ldy	#>cmd17_msg
		jsr	mon_txtout
		lda	cmd17_resp
		jsr	Hexout
		lda	#$ff
		jsr	SD_SENDBYTEW
		jsr	SD_DESELECT
		sec
		lda	#1		;error
		rts

;read card id data (CID)
sd_cmd10	jsr	SD_SELECT
		lda	#<cmd10
		ldy	#>cmd10
		jsr	sd_send_cmd
		jsr	sd_readbyte
		sta	cmd10_resp
;get data block
?l2		jsr	SD_READBYTE
		cmp	#$FE		;wait for token
		bne	?l2
		ldy	#16
?l3		jsr	SD_READBYTE
		jsr	Hexout
		dey
		bne	?l3
		jsr	sd_readbyte	;read crc
		lda	#$ff
		jsr	SD_SENDBYTEW
		jsr	SD_DESELECT
		clc
		RTS

;send acmd
sd_send_acmd	sta	acmd_tmp
		sty	acmd_tmp+1
		lda	#<cmd55
		ldy	#>cmd55
		jsr	sd_send_cmd
		jsr	sd_readbyte
		sta	cmd55_resp
		lda	acmd_tmp
		ldy	acmd_tmp+1

;send cmd cmd
sd_send_cmd
		sta	cmd_save
		sty	cmd_save+1
		ldy	#0
?L2		lda	(cmd_save),y
		jsr	SD_SENDBYTEW
		iny
		cpy	#6
		bne	?L2
		lda	#$ff
		jsr	SD_SENDBYTEW
		rts

;
sd_wait_r1	jsr	SD_READBYTE
		cmp	#$80
		rts

;/***********************************************************************/
; Low level SPI routines
;
; These routines use the VIA shift register to shift out the data, and a 
; hardware shift register connected to port B to read the data shifted in.
;
; note that the pure VIA shift register works as SPI mode 3, which is not
; understood by many MMC/SD Cards. 
;
; By using INVCLK the SD card clock signal can be inverted (set CPOL=0).
; To achieve CPHA=0, the first (MSB) bit must be sent out manually 
; by XORing the current shift register output appropriately, which is
; done via INVDAT.
;
; note code assumes the SD_INVDAT on bit 0 of the port A - so it can be
; modified quickly by INC and DEC
;
; The code waits for the shift register to finish. You could do that with
; NOPs as well for example, as a byte only takes 16 cycles. 
; However, then you can't test it with lower clocks easily.


; init the SPI code
SD_INIT
; deselect any device,
; do invert the clock (mode 0)
		lda	SD_VIA+VIA_DRA
		ora	#SD_SEL+SD_INVCLK
		and	#255-SD_INVDAT
		sta	SD_VIA+VIA_DRA
; set I/O port to output
		lda	SD_VIA+VIA_DDRA
		ora	#SD_SEL+SD_INVDAT+SD_INVCLK
		sta	SD_VIA+VIA_DDRA
; disable shift register interrupts
		lda	#%00000100
		sta	SD_VIA+VIA_IER

		if	1
;---------------------------------
; Alternative 2 - shift out under T2
;
; this uses T2 as shift register timer,
; as it can be made slower, if you have 
; slow voltage converters for example

; set timer 2 to timed
		lda	SD_VIA+VIA_ACR
 		and	#%11011111
		sta	SD_VIA+VIA_ACR

; set timer 2 
; (half-cycle is T2+2)
; set low byte first into latch
		lda	#SD_CLK
		sta	SD_VIA+VIA_T2CL
; high byte store sets counter
		lda	#0
		sta	SD_VIA+VIA_T2CH

; set up shift register mode to output
; under T2 control
		lda	SD_VIA+VIA_ACR
		and	#%11110111
		ora	#%00010100
		sta	SD_VIA+VIA_ACR

		else

;---------------------------------
; Alternative 2 - shift out under Phi2
;
; if your hardware is fast enough, you can
; shift out under control of phi2

; set up shift register mode to output
; under phi2 control, which makes bits go out
; on half phi2.
		lda	SD_VIA+VIA_ACR
		and	#%11111011
		ora	#%00011000
		sta	SD_VIA+VIA_ACR
		endif
;---------------------------------

; write first (dummy) byte, to make sure the last
; bit is low
		lda	#$0
		sta	SD_VIA+VIA_SR
		rts

; deselect the SD card
SD_DESELECT	lda	SD_VIA+VIA_DRA
		ora	#SD_SEL
		sta	SD_VIA+VIA_DRA
		jsr	SD_READBYTE
		rts

; select the SD card
SD_SELECT	lda	SD_VIA+VIA_DRA
		and	#255-SD_SEL
		sta	SD_VIA+VIA_DRA
		rts

; send a $ff byte and keeping the data line high
; which is needed for an MMC card to switch to SPI mode
SD_SENDRESETBYTES
; invert data so first bit is already high
		inc	SD_VIA+VIA_DRA
		ldx	#10
?L1		lda	#$00
		sta	SD_VIA+VIA_SR
; wait to finish
		lda	#%00000100
?W1		bit	SD_VIA+VIA_IFR
		beq	?W1
; clear int
		sta	SD_VIA+VIA_IFR
; next resetbyte
		dex
		bne	?L1
; reset inverter
		dec	SD_VIA+VIA_DRA
		rts

; send and read a byte
SD_READBYTE	lda #$ff
; send a byte only (could be optimized, 
; but not when you have to wait to end the data inverter) 
SD_SENDBYTEW
; mode 0
; make sure last bit is 0, shifting bit 7 into carry
		asl	A
		bcs	SD_invert
; last bit was 0, nothing to do but send the byte
		sta	SD_VIA+VIA_SR
; wait to finish
		lda	#%00000100
?W1		bit	SD_VIA+VIA_IFR
		beq	?W1
		bne	SD_X001

SD_invert
; invert the current bit (which is last bit from prev. 
; data byte, which we set to zero
		inc	SD_VIA+VIA_DRA
; compensate for the inversion
		eor	#$fe
; send out the data
		sta	SD_VIA+VIA_SR
; wait to finish
		lda	#%00000100
?W1		bit	SD_VIA+VIA_IFR
		beq	?W1
; reset inverter
		dec	SD_VIA+VIA_DRA
SD_X001					; clear int
		sta	SD_VIA+VIA_IFR
; read read data
		lda	SD_VIA+VIA_DRB	; load from external shift reg
		rts

;messages and menus
ocrmsg		byte	cr,lf,"MICRO SD CARD OCR CONTENTS: ",0
cidmsg		byte	cr,lf,"MICRO SD CARD CID: ",0
mon_crmsg	byte	cr,lf,"PRESS ENTER TO CONTINUE ",0
mon_opnmsg	byte	cr,lf,"SBC2 MON V1.21",0
ioemsg		byte	cr,lf,"IO ERROR",0
cmd0_msg	byte	cr,lf,"CMD0 RESPONSE ",0
cmd1_msg	byte	cr,lf,"CMD1 RESPONSE ",0
cmd8_msg	byte	cr,lf,"CMD8 RESPONSE ",0
cmd10_msg	byte	cr,lf,"CMD10 RESPOMSE ",0
cmd17_msg	byte	cr,lf,"CMD17 RESPONSE ",0
cmd24_msg	byte	cr,lf,"CMD24 RESPONSE ",0
cmd55_msg	byte	cr,lf,"CMD55 RESPONSE ",0
cmd58_msg	byte	cr,lf,"CMD58 RESPONSE ",0
acmd41_msg	byte	cr,lf,"ACMD41 RESPONSE ",0

;basic reset etc. vectors
;		org	$fffa
;		word	nmi
;		word	mon_entry
;		word	irqbrk

		ends

