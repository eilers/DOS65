;C65LOAD
;C65 file that is loaded and executed to start DOS/65
;derived from C64L210.ASM
;Version 1.0
;Use BSA (Bit Shifters's Assembler) to build!
;miscellaneous definitions
Start = $2001
.CPU  45GS02 

CR	=	$0D	;carriage return

;C64 KERNAL entry points
	.INCLUDE "kernel.asm"

; ZP Adresses
LTXTSTRT	=	$FB
HTXTSTRT	=	$FC

; Macros
MACRO PrintTxt(ADR)
	LDA	#<ADR
	STA	LTXTSTRT
	LDA	#>ADR
	STA	HTXTSTRT
	JSR	PrintText
ENDMAC

MACRO PrintHex(ADR, INCREMENT)
	LDA	ADR + INCREMENT
	JSR	PrintHexByte	
ENDMAC

MACRO break()
	JSR CLRCH
	BRK
ENDMAC

	.INCLUDE "macros.asm"


;start of actual load
	*=	Start		
	.LOAD			; Add load address
	;.STORE <startaddress>,<length>,"filename"
	.STORE Start,Ende-Start,"c65loader.prg"

;This is in BASIC data area so it must be loaded as a BASIC
;file at $2001 that then jumps into loader
; Basic header SYS $200F
	.word basend 	        ; next BASIC line
	.word $000A 	        ; line #
	.byte $fE,$02,$30	; BANK 0
	.byte $3A,$9E		; :SYS
	.byte "$2012"; address as string
	.byte 0 		; end of line
basend:	.byte 0,0 	; end of basic
	SEI		;disable interrupts
;set up C65 memory by disabling BASIC ROM & Character ROM
	EnableInterfaceRom()
	SetKernalOnly()
;Print init text
	PrintTxt(INITTXT)
;close everything - including whatever BASIC did or user did
	JSR	CLALL	;close all files & channels
;set up read from drive 8
	JSR	INITDSK
;set up address and operation and set x=0
	JSR	SETUP
;first read 128 byte record containing data needed
;for rest of load process as well as first record of CCM
BLOOP	JSR	BASIN	;input from channel
	STA	START,X	;and save
	INX
	BNE	BLOOP	;loop until one sector done
;at this point we know where and how much to load
; Print data from boot record
; 1. Start Address
	PrintTxt(STRTTXT)
	PrintHex(START, 1)
	PrintHex(START, 0)
	PrintTxt(NLTXT)
; 2. Length
	PrintTxt(LGTHTXT)
	PrintHex(LENGTH, 0)	
	PrintTxt(NLTXT)
; 3. CBOOT-> Cold Boot Start Address
	PrintTxt(BOOTTXT)
	PrintHex(CBOOT, 1)
	PrintHex(CBOOT, 0)
	PrintTxt(NLTXT)
	PrintTxt(LOOSTXT)
; Reinit disk access
	JSR	INITDSK
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
DONE	DisableInterfaceRom()
	JMP	(CBOOT)	;jump to SIM cold boot entry
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

INITDSK
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
	RTS

; Write Text to screen. 
; LTXTSTRT: < Start address of text
; HTXTSTRT: > Start address of text
PrintText:
	JSR CLRCH
	LDY #0			; Index into string
PrtLoop	LDA (LTXTSTRT),Y	; Load character from text (zp indirect)
	BEQ PrintEx		; If 0, end of string
	JSR CHROUT		; Print character via CHROUT
	INY
	BNE PrtLoop		; Repeat
PrintEx	RTS

; Print byte as Text to screen.
; LTXTSTRT: < Address of Byte
; LTXTSTRT: < Address of Byte

;-------------------------
; print_hex_byte:
; Input: A = byte to print as hex (2 chars)
;-------------------------
PrintHexByte:
	PHA                ; Save A
	JSR CLRCH
	PLA
	PHA
	LSR A              ; Shift right 4 bits (get high nibble)
	LSR A
	LSR A
	LSR A
	JSR nybble_to_ascii
	JSR CHROUT          ; Print high nibble

	PLA                ; Restore A
	AND #$0F           ; Mask low nibble
	JSR nybble_to_ascii
	JSR CHROUT          ; Print low nibble
	RTS

;-------------------------
; nybble_to_ascii:
; Input: A = 0-15
; Output: A = ASCII char ('0'-'9','A'-'F')
;-------------------------
nybble_to_ascii:
	CMP #$0A
	BCC num
	ADC #$06           ; Add 6 to go from '9'+1 to 'A'
num     CLC
	ADC #$30
	RTS

;-------------------------
text:   .text "VALUE: "
	.byte 0

value:  .byte $3A          ; Value to display (change to test)	
	
;data area
;start reading at track 1 and sector 0
L8AA	.byte	"U1:2 0 "
TRACK	.byte	"1 "
SECTOR	.byte	" 0",CR
L8B5	.byte	"#"	;file name for random access
INITTXT	.byte	"DOS/65 - BOOTLOADER FOR MEGA65",CR,"LOAD MBR ...",CR,0
STRTTXT	.byte	"START ADR: $",0
LGTHTXT	.byte	"LENGTH   : $",0
BOOTTXT	.byte	"BOOT ADR : $",0
LOOSTXT .byet	CR,"Load OS..", 0
NLTXT   .byte	CR,0

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
; End label for BSA Assembler
Ende 	
