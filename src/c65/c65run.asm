;C65RUN
;This contains a complete DOS/65 (ccm, pem, sim) that can be started like a progam.
;derived from c65loader.asm
;Version 1.0
;Use BSA (Bit Shifters's Assembler) to build!
;miscellaneous definitions
.CPU  45GS02 
Start_Run = $2001	; Memory location of the start program.

CR	=	$0D	;carriage return

	.INCLUDE "../constants.asm"
	.INCLUDE "kernel.asm"
	.INCLUDE "macros.asm"

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
; Add adress header for PRG load
;start of actual load
	*=	Start_Run		
	.LOAD ; Add load adress header
	;.STORE <startaddress>,<length>,"filename"
	.STORE Start_Run,End_Run-Start_Run,"c65run.prg"

;This is in BASIC data area so it must be loaded as a BASIC
;file at $2001 that then jumps into loader
; Basic header SYS $200F
	.word	basend 	        ; next BASIC line
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
; Copy OS from End_Run to its destination at Start_Sys 
; using DMA
	LDA	#$00		; DMA list exists in Bank 0
	STA	$D702
	LDA	#>dmacopy
	STA	$D701
	LDA	#<dmacopy
	STA	$D700		; Execute copy via DMS
; Switch to Bank 5, but keep $2000 - $3FFF 
	SetBank5WithInterface()
; Jump indirectly to the cold boot routine
	; First save current stack pointer
	; TODO: Check whether necessary.. 
	TSY			; Load stack pointer high
	STY	K_SPH
	TSX			; Load stack pointer low
	STX	K_SPL
	JMP	_INIT_AFTER_LOAD
; DMA List to copy code
dmacopy
	.byte	$00			; Command low byte: COPY
	.word	simlng+pemlng+ccmlng 	; How many bytes
	.word   End_Run			; From address
	.byte	$00			; Source Bank
	.word	Start_Sys 		; Destination address
	.byte   $05			; Destination Bank
	.byte	$00			; Command high byte
	.word   $0000			; Modulo (ignored for COPY)


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
	JSR CHROUT	; Print low nibble
	RTS

;============= Helper Code =================
;-------------------------
; nybble_to_ascii:
; Input: A = 0-15
; Output: A = ASCII char ('0'-'9','A'-'F')
;-------------------------
nybble_to_ascii:
	CMP #$0A
	BCC nba_num
	ADC #$06	; Add 6 to go from '9'+1 to 'A'
nba_num	CLC
	ADC #$30
	RTS

;-------------------------
text:   .text "VALUE: "
	.byte 0

value:  .byte $3A	; Value to display (change to test)	
	
;data area
INITTXT	.byte	"DOS/65 - RUNNER FOR MEGA65",CR,"PLEASE WAIT ...",CR,0
NLTXT   .byte	CR,0


;============= Interface Code =================
; Entry Point for SIM to access into the kernel
; This is called with Bank 5 pulled in. Only $2000 - $3FFF is
; from Bank 0
; TODO: Check that SP is unchanged after Kernel call!
_SETLFS
	SetKernalOnly()
	JSR	SETLFS		; IN: A, X, Y; OUT: None	
	JMP	_RETURN
_SETNAM
	SetKernalOnly()
	; SETBNK is required! Use Bank 0 here..
	PHA	; Save length
	LDA	#$00
	LDX	#$00
	JSR	SETBNK
	; Filename was stored in COPY_BUFFER. Length is in A
	PLA
	LDX	<COPY_BUFFER
	LDY	>COPY_BUFFER
	JSR	SETNAM		; IN: A, X, Y; OUT: None	
	JMP	_RETURN
_OPEN	; TODO: Ensure that C stays alive..
	SetKernalOnly()
	JSR	OPEN		; IN: -; OUT: A, C
	JMP	_RETURN
_CLOSE
	SetKernalOnly()
	JSR	CLOSE		; IN: A, C; OUT: A, C
	JMP	_RETURN
_CHKIN
	SetKernalOnly()
	JSR	CHKIN		; IN: X; OUT: A, C
	JMP	_RETURN
_CKOUT
	SetKernalOnly()
	JSR	CKOUT		; IN: X; OUT: A, C
	JMP	_RETURN
_CLRCH
	SetKernalOnly()
	JSR	CLRCH		; IN: -; OUT: -
	JMP	_RETURN
_BASIN
	SetKernalOnly()
	JSR	BASIN		; IN: -; OUT: A, C
	JMP	_RETURN
_BSOUT	; TODO: Ensure that C stays alive..
	SetKernalOnly()
	JSR	BSOUT		; IN: A; OUT: A, C	
	JMP	_RETURN
_GETIN
	SetKernalOnly()
	JSR	GETIN		; IN: -; OUT: A, C
	JMP	_RETURN
_CLALL
	SetKernalOnly()
	JSR	CLALL		; IN: -; OUT: -
	JMP	_RETURN
_RETURN
	SetBank5WithInterface()	
	RTS

K_SPH	.byte	0	; Kernel: Stack pointer high
K_SPL	.byte	0	; Kernel: Stack pointer low
COPY_BUFFER
	*= 	*+80
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
