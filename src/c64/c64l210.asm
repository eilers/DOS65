;C64LOAD
;C64 file that is loaded and executed to start DOS/65
;Version 2.10
;released	28 march 2008
;miscellaneous definitions
CR	=	$0D	;carriage return
;C64 KERNAL entry points
SETLFS	=	$FFBA	;set LA, FA, SA
SETNAM	=	$FFBD	;set length & file name address
OPEN	=	$FFC0	;open logical file
CHKIN	=	$FFC6	;set channel in
CKOUT	=	$FFC9	;set channel out
CLRCH	=	$FFCC	;restore default channel
BASIN	=	$FFCF	;input from channel
BSOUT	=	$FFD2	;output to channel
CLALL	=	$FFE7	;close all files & channels
;start of actual load
;This is in BASIC data area so it must be loaded as a BASIC
;file at $0800 that then jumps to $080F
	*=	$80F
	SEI		;disable interrupts
;set up C64 memory by disabling BASIC ROM & Character ROM
;by writing to second 6510 I/O port
 	LDA	#%00110110
 	STA	1
;close everything - including whatever BASIC did or user did
	JSR	CLALL	;close all files & channels
;set up read from drive 8
;first open command channel
	LDA	#15	;logical file number 15
	LDX	#8	;device 8
	LDY	#15	;secondary address 15
	JSR	SETLFS	;set LA, FA, SA
	LDA	#0	;zero length file name
	JSR	SETNAM	;set length & file name address
	JSR	OPEN	;open logical file
;now set up for random access for file 2
	LDA	#2	;logical file number 2
	LDX	#8	;device 8
	LDY	#2	;secondary address 2
	JSR	SETLFS	;set LA, FA, SA
	LDA	#1	;name is one char long
	LDX	#<L8B5	;Filename "#"
	LDY	#>L8B5 
	JSR	SETNAM	;set length & file name address
	JSR	OPEN	;open logical file
;set up address and operation and set x=0
	JSR	SETUP
;first read 128 byte record containing data needed
;for rest of load process as well as first record of CCM
BLOOP	JSR	BASIN	;input from channel
	STA	START,X	;and save
	INX
	BNE	BLOOP	;loop until one sector done
;at this point we know where and how much to load
;set up address and count for remaining but
	SEC		;back up 128 bytes
	LDA	START	;set up store
	SBC	#128
	STA	MSTORE+1
	LDA	START+1
	SBC	#0
	STA	MSTORE+2
;set up pointer & counter for main read loop
;first increase records by one to reflect re-read of boot
	INC	LENGTH
;now read and store rest of CCM, PEM, & SIM
MAIN	JSR	SETUP	;setup & set x=0
MLOOP	JSR	BASIN	;input from channel
MSTORE	STA	$FFFF,X	;and save
	INX
	BEQ	ONESEC	;one sector done if x=0
;x is either 1-127 or 128-255
;see if 1-127 and if so loop
	BPL	MLOOP	;loop until >=128
;x is 128-255
	CPX	#128	;see if record done
	BNE	MLOOP	;if not loop until one record done
	DEC	LENGTH	;drop length
	BEQ	DONE	;done if zero
	BNE	MLOOP	;else loop
;now see if done from record count decrement
ONESEC	DEC	LENGTH
	BEQ	DONE
;bump sector number
ENDSEC	INC	SECTOR+1	;bump sector number
	LDA	SECTOR+1
	CMP	#'9'+1	;see if rollover
	BNE	NO10
	LDA	#'0'	;reset units
	STA	SECTOR+1
	LDA	#'1'	;set tens
	STA	SECTOR
;now check for track rollover
NO10	LDA	SECTOR+1
	CMP	#'7'
	BNE	NOTRK
	LDA	SECTOR
	CMP	#'1'
	BNE	NOTRK
;set for sector 0 of track 2
	LDA	#'0'
	STA	SECTOR+1
	LDA	#' '
	STA	SECTOR
	LDA	#'2'
	STA	TRACK
;uses self modifying code
NOTRK	INC	MSTORE+2	;bump load high byte
	BNE	MAIN	;should never be 0 so loop
;load is done - get ready to do cold boot entry
DONE	JMP	(CBOOT)	;jump to SIM cold boot entry
;set up address and operation
SETUP	LDX	#15	;set 15 as active channel out
	JSR	CKOUT	;set channel out
	LDX	#0
	LDY	#12	;name is 12 characters long
OP1	LDA	L8AA,X	;point to character in name
	JSR	BSOUT	;output to channel
	INX
	DEY
	BNE	OP1	;loop until last character sent
	JSR	CLRCH	;restore default channel
	LDX	#2	;set 2 as active channel in
	JSR	CHKIN	;set channel in
	LDX	#0
	RTS
;data area
;start reading at track 1 and sector 0
L8AA	.byte	"U1:2 0 "
TRACK	.byte	"1 "
SECTOR	.byte	" 0",CR
L8B5	.byte	"#"	;file name for random access
;128 byte data area for BOOT record
;start address
START
	*=	*+2
;number records
LENGTH
	*=	*+1
;SIM cold boot entry
CBOOT
	*=	*+2	
	.end
