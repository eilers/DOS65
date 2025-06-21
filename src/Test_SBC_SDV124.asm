		case	off
		pw 132
		pl 44
		chip	65c02
		globals	on
		inclist	on
		condlist	on
;
;For an MMC or SDSC card connected to VIA-SD adapter like VIASPI-1.1
;or SBC2 SD I/F V1.00.
;
;This code initializes the system, 
;reads the OCR (Operations condition register), then the 
;CID (Card identification register), then enters a menu system
;providing multiple functions.
;
;This is heavily dependent on Andre Fachat's VIASPI 1.1 and hence is
;distributed under the terms of the GNU General Public License version 2.
;
;Richard Leary's plan for this is to grow it to be a tool that can
;	read block from specified location
;	write block to specified location
;	specify block using LBA approach or DOS/65 track and record
;	fill block buffer with specified byte (default $E5)
;	print block buffer contents to console
;	format drive by writing E5 to directory blocks
;	other TBD actions
;
;
;For details see for example here
;http://www.retroleum.co.uk/electronics-articles/basic-mmc-card-access/
;http://www.samsung.com/global/business/semiconductor/products/flash/
;    downloads/applicationnote/MMC_HOST_Algorithm_Guide.pdf
;http://en.wikipedia.org/wiki/MultiMediaCard
;http://en.wikipedia.org/wiki/Secure_Digital_card
;http://elm-chan.org/docs/mmc/mmc_e.html
;
;An expected screen output would look like:
;OCR:
;80 ff 80 00
;  ^^^^^^^- allowed voltage range bits from 3.5 to 1.6V
;CID:
;06 00 01 31 36 4d 20 20 20 01 1d 1d cb 41 69 77
;        ^^^^^^^^^^^^^^^^^- 3-8: Manufacturer name in ASCII
;                            ^^^^^^^^^^^- A-D: serial number (32bit)
;

;last revision:
;		5/14/2017 v1.10
;			converted Fachat 1.1 to WDC
;		6/3/2017 v1.20
;			imple4mented menu system
;			enabled write block
;			added many test and prep functions
;		6/8/2017 v1.21
;			fixed some R2 status reporting
;			simplified buffer dump
;			added command echo
;		6/22/2017 v1.22
;			corrected error near sendact2
;		7/20/2017 v1.22SBC2
;			baseline release
;		7/28/2017 v1.23SBC2
;			corrected menu GETC
;			changed exit
;		8/25/2017 V1.24SBC2
;			corrected minor errors
;			added DOS/65 return value
;			added VIA initialization
;			added SEI at startup
;			changed init clock to low T2
;			added menu item 8
;			improved normal and error code

;define debug behavior
debug		equ	1

;define ascii characters
cr		equ	13
lf		equ	10
esc		equ	27

;define via address and related addresses
		include	sbc_via6522.asm

		page0
		org	0
stdio_d1	defs	2		;gp pointer in stdio.asm
cmd_cnt		defs	2		;counter in sd_cmd?
wblk_ptr	defs	2		;pointer in write_blk
rblk_ptr	defs	2		;pointer in read_blk
acmd_tmp	defs	2		;ltemp iind send acmd
cmd_save	defs	2		;save cmd in send_cmd
buf_pnt		defs	2		;buffer pointer
buf_pos		defs	1		;byte in line
;command responses
cmd0_resp	defs	1		;resetl
cmd1_resp	defs	1		;v1 init
cmd8_resp	defs	1		;if conditions
cmd10_resp	defs	1		;read cid
cmd17_resp	defs	1		;read block
cmd24_resp	defs	1		;write block
cmd55_resp	defs	1		;acmd preface
cmd58_resp	defs	1		;read ocr
acmd41_resp	defs	1		;v2 init
		ends

		code

		org	$200

;/***************************************************************************/

main		lda	#<opnmsg	;send opening banner
		ldy	#>opnmsg
		jsr	txtout
		jsr	crlfout
		jsr	sd_reset
		jsr	Crlfout
		LDA	#<ocrmsg	;print OCR message
		ldy	#>OCRMSG
		JSR	txtout
		jsr	sd_cmd58	;read OCR (Operations Condition Register)
		jsr	Crlfout
		lda	#<cidmsg	;print cidmessage
		ldy	#>cidmsg
		jsr	txtout
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

;menu
menu		LDA	#<m0msg		;show choices
		ldy	#>m0msg
		jsr	txtout
		lda	#<m1msg
		ldy	#>m1msg
		jsr	txtout
		lda	#<m2msg
		ldy	#>m2msg
		jsr	txtout
		jsr	show_blk
		lda	#<mnumsg	;ask for input
		ldy	#>mnumsg
		jsr	txtout
?L2		jsr	waitc		;get response
		cmp	#'0'		;see if less than 0
		bcc	?L2		;try again
		cmp	#'8'+1
		bcs	?L2		;try again
		pha			;save
		jsr	putc		;echo
		pla			;get back
		and	#15		;look at 0 to 8
		asl	a		;make index
		tax
		lda	menu_vec,x	;get address
		sta	vector
		inx
		lda	menu_vec,x
		sta	vector+1
		lda	#>vecret-1
		pha
		lda	#<vecret-1
		pha
		jmp	(vector)
vecret		jmp	menu

;vector tabke
menu_vec	word	menu0
		word	menu1
		word	menu2
		word	menu3
		word	menu4
		word	menu5
		word	menu6
		word	menu7
		word	menu8

;menu 0 EXIT
menu0		pla
		pla
		rts

;menu 1 SET BLOCK NUMBER
menu1		LDA	#<NUMMSG	;send directions
		ldy	#>nummsg
		jsr	txtout
		jsr	hex_byte
		sta	block3
		jsr	hex_byte
		sta	block2
		jsr	hex_byte
		sta	block1
		jsr	hex_byte
		sta	block0
		rts
;menu 2 DISPLAY BUFFER
menu2		jsr	crlfout
		lda	#<buf		;set pointer
		ldy	#>buf
		sta	buf_pnt
		sty	buf_pnt+1
		lda	#32		;setup position count
		sta	buf_pos
		ldy	#0		;clear index
?L2		lda	(buf_pnt),y	;get byte
		jsr	hexout		;send to console
		iny			;bump index
		beq	?Z2		;if zero handle second half
		dec	buf_pos		;see if eol
		bne	?L2		;loop if not
		lda	#32		;reset counter
		sta	buf_pos
		jsr	crlfout		;start new line
		bra	?L2
?Z2		jsr	crlfout
		inc	buf_pnt+1
		lda	#32		;setup position count
		sta	buf_pos
		ldy	#0		;clear index
?L3		lda	(buf_pnt),y	;get byte
		jsr	hexout		;send to console
		iny			;bump index
		beq	?Z3		;if zero handle second half
		dec	buf_pos		;see if eol
		bne	?L3		;loop if not
		lda	#32		;reset counter
		sta	buf_pos
		jsr	crlfout		;start new line
		bra	?L3
?Z3		rts

;menu 3 SET FILL BYTE
;Show current fill byte to operator, allow exit without
;change, accept two valid hex characters, report new value.
menu3		lda	#<filmsg	;display current value
		ldy	#>filmsg
		jsr	txtout
		lda	fill_byte
		jsr	hexout
		lda	#<escmsg	;send esc invitation
		ldy	#>escmsg
		jsr	txtout
?l2		jsr	chkc		;see if input
		beq	?L2		;loop if not
		jsr	getc7		;get character
		cmp	#esc		;see if esc
		beq	?x2		;exit if ESC
		cmp	#cr
		bne	?L2
;operator has decided to change fill byte
		jsr	hex_byte	;enter byte
		sta	tmp_byte	;save it
		lda	#<hex1msg	;ask if OK
		ldy	#>hex1msg
		jsr	txtout
		LDA	tmp_byte	;type it
		jsr	hexout
		lda	#<hex2msg	;finish message
		ldy	#>hex2msg
		jsr	txtout
?l3		jsr	chkc		;see if input
		beq	?L3		;loop if not
		jsr	getc7		;get character
		cmp	#esc		;see if esc
		beq	?x2		;exit if ESC
		cmp	#cr		;bne ?L3
		lda	tmp_byte	;get temp
		sta	fill_byte	;replace old
?X2		rts

;menu 4 FILL BUFFER
menu4		lda	#<buf
		ldy	#>buf
		sta	buf_pnt
		sty	buf_pnt+1
		lda	Fill_byte
		ldy	#0
?L2		sta	(buf_pnt),y	;save char
		iny
		bne	?L2
		inc	buf_pnt+1
?L3		sta	(buf_pnt),y	;save char
		iny
		bne	?L3
		rts

;menu 5 READ BLOCK
menu5		lda	block3		;fll in block in command
		sta	cmd17+1
		lda	block2
		sta	cmd17+2
		lda	block1
		sta	cmd17+3
		lda	block0
		sta	cmd17+4
		jmp	sd_read_blk

;MENU 6 WRITE BLOCK
menu6		lda	block3		;fill in write
		sta	cmd24+1
		lda	block2
		sta	cmd24+2
		lda	block1
		sta	cmd24+3
		lda	block0
		sta	cmd24+4
		lda	#<cmd24
		ldy	#>cmd24
		jmp	sd_write_blk

;MENU 7 CLEAR DIRECTORY
;starting block number and fill_byte must be set first
menu7		lda	#0		;clear counter
		sta	dir_blk
?L2		jsr	menu6		;write block
		dec	dir_blk		;drop counter
		beq	?X2		;done if zero
;adjust block mumber
		clc
		lda	block0
		adc	#0
		sta	block0
		lda	block1
		adc	#$2
		sta	block1
		lda	block2
		adc	#0
		sta	block2
		lda	block3
		adc	#0
		sta	block3
		bra	?L2
?X2		rts
;
;menu 8 - increase block number by 1
menu8		clc
		lda	block0
		adc	#0
		sta	block0
		lda	block1
		adc	#$2
		sta	block1
		lda	block2
		adc	#0
		sta	block2
		lda	block3
		adc	#0
		sta	block3
		rts
;
;menu system code and messages

;wait for CR to be entered to proceed
wait_cr		lda	#<crmsg		;send message
		ldy	#>crmsg
		jsr	txtout
?L2		jsr	chkc		;see if character
		beq	?L2		;loop if none
		jsr	getc7		;get character
		cmp	#cr		;see if cr
		bne	?L2		;loop if not
		rts

;show block number
show_blk	lda	#<blkmsg	;point to message
		ldy	#>blkmsg
		jsr	txtout		;send it
		lda	block3		;start with MSB
		jsr	hexout
		lda	block2
		jsr	hexout
		lda	block1
		jsr	hexout
		lda	block0
		jmp	hexout
;data for main loop or global need
cmd0		byte	$40,0,0,0,0,$95
cmd1		byte	$41,0,0,0,0,$ff
cmd8		byte	$48,0,0,1,$aa,$87
cmd10		byte	$4A,0,0,0,0,$ff
cmd17		byte	$51,0,0,2,0,$ff
cmd24		byte	$58,0,0,2,0,$ff
cmd55		byte	$77,0,0,0,0,$ff
cmd58		byte	$7a,0,0,0,0,$ff
ac41		byte	$69,0,0,0,0,$ff

;messages and menus
opnmsg		byte	cr,lf,"VIA CENTRIC SPI/SD TEST TOOLS V1.24 FOR SBC2",0
rdymsg		byte	cr,lf,"TYPE <ENTER> WHEN READY TO CONTINUE",0
ocrmsg		byte	cr,lf,"OCR CONTENTS: ",0
cidmsg		byte	cr,lf,"CID: ",0
crmsg		byte	cr,lf,"PRESS ENTER TO CONTINUE ",0
mnumsg		byte	cr,lf,"PRESS KEY FOR MENU SELECTION ",0
m0msg		byte	cr,lf,cr,lf,"0 = EXIT  1 = SET BLOCK NUMBER  2 = "
		byte	"DISPLAY BUFFER",0
m1msg		byte	cr,lf,"3 = SET FILL BYTE  4 = FILL BUFFER   5 = "
		byte	"READ BLOCK",0
M2MSG		byte	cr,lf,"6 = WRITE BLOCK   7 = CLEAR "
		byte	"DIRECTORY   8 - UP 1 BLOCK",0
blkmsg		byte	cr,lf,"BLOCK: ",0
filmsg		byte	cr,lf,"CURRENT FILL BYTE IS: ",0
escmsg		byte	cr,lf,"ENTER ESC TO ABORT OR CR TO CONTINUE ",0
hex1msg		byte	cr,lf,"VALUE ENTERED WAS ",0
HEX2MSG		BYTE	" ENTER ESC TO ABORT OR CR TO ACCEPT ",0
nummsg		byte	cr,lf,"ENTER BYTES STARTING WITH MSB",0
cmd0_msg	byte	cr,lf,"CMD0 RESPONSE ",0
cmd1_msg	byte	cr,lf,"CMD1 RESPONSE ",0
cmd8_msg	byte	cr,lf,"CMD8 RESPONSE ",0
cmd10_msg	byte	cr,lf,"CMD10 RESPOMSE ",0
cmd17_msg	byte	cr,lf,"CMD17 RESPONSE ",0
cmd24_msg	byte	cr,lf,"CMD24 RESPONSE ",0
cmd55_msg	byte	cr,lf,"CMD55 RESPONSE ",0
cmd58_msg	byte	cr,lf,"CMD58 RESPONSE ",0
acmd41_msg	byte	cr,lf,"ACMD41 RESPONSE ",0



;see http://www.retroleum.co.uk/electronics-articles/basic-mmc-card-access/

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
		jsr	txtout
		lda	cmd0_resp
		jsr	Hexout
		pla
		pla
		jmp	menu
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
;		lda	#<cmd8_msg
;		ldy	#>cmd8_msg
;		jsr	txtout
;		lda	cmd8_resp
;		jsr	Hexout
;		pla
;		pla
;		jmp	menu

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
		jsr	txtout
		lda	cmd1_resp	;get response again
		jsr	Hexout
		lda	#$ff
		jsr	SD_SENDBYTEW
		jsr	SD_DESELECT
		pla
		pla
		jmp	menu
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
		lda	#<buf
		ldy	#>buf
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
		jsr	txtout
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
		lda	#<buf
		ldy	#>buf
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
		jsr	txtout
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

		include	sbc_viaspi.asm

		include	sbc_bind.asm

;storage
vector		word	0
Block0		byte	0		;block number
Block1		byte	0
Block2		byte	0
Block3		byte	0
Fill_Byte	byte	$E5
tmp_nbl
tmp_byte	byte	0
dir_blk		byte	0
BUF		defs	512
		byte	$65

		ends

		end