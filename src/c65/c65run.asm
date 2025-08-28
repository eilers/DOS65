;C65RUN
;This contains a complete DOS/65 (ccm, pem, sim) that can be started like a progam.
;derived from c65loader.asm
;Version 1.0
;Use BSA (Bit Shifters's Assembler) to build!
;miscellaneous definitions
.CPU  45GS02 
Start_Run = $2001	; Memory location of the start program.

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
CHROUT	=	$FFD2	;Char Out

	.INCLUDE "../constants.asm"
simlng	=	pages*256	;sim length in bytes

; ZP Adresses for Print
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

MACRO EnableInterfaceRom()
;	Use $D030 to map-in interface rom 
;	by writing into $D030 
 	LDA	#%00100000
 	STA	$D030
ENDMAC

MACRO DisableInterfaceRom()
;	Use $D030 to map-out all roms 
;	by writing into $D030 
 	LDA	#%00000000
 	STA	$D030
ENDMAC

MACRO SetKernalOnly()
	; Use MAP command to map in kernel only ($E000-EFFF)
		LDA #%00000000
		LDX #%00000000
		LDY #%00000000
		LDZ #%10000011
		MAP
		NOP
ENDMAC


;start of actual load
	*=	Start_Run		
	.LOAD			; Add load address
	;.STORE <startaddress>,<length>,"filename"
	.STORE Start_Run,End_Run-Start_Run,"c65run.prg"

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
; Enable 80x50 Screen by sending ESC + 5 to the screen
	LDA	#27		; ESC
	JSR	BSOUT
	LDA	#53		; 5
	JSR	BSOUT
; 


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
	BCC nba_num
	ADC #$06           ; Add 6 to go from '9'+1 to 'A'
nba_num	CLC
	ADC #$30
	RTS

;-------------------------
text:   .text "VALUE: "
	.byte 0

value:  .byte $3A          ; Value to display (change to test)	
	
;data area
INITTXT	.byte	"DOS/65 - RUNNER FOR MEGA65",CR,"PLEASE WAIT ...",CR,0
NLTXT   .byte	CR,0

End_Run 	

;-------------------------
; Dos/65 System
;-------------------------
	Start_Sys = memlng-simlng-pemlng-ccmlng#
	*= Start_Sys
	.STORE Start_Sys,End_Sys-Start_Sys,"dos65.bin"

;-------------------------------
; Include ccm + pem 
;-------------------------------
	.INCLUDE "../ccm.asm"
	.INCLUDE "../pem.asm"
;--------------------------------
;dos/65 system interface module (sim)
;--------------------------------
	*=	pem+pemlng
	; .INCLUDE "c65sim.asm"
sim
	*=	*+55
sysdef

End_Sys
