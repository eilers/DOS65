MACRO EnableInterfaceRom()
;	Use $D030 to map-in interface rom 
;	by writing into $D030 
 	LDA	#%10100000
 	TSB	$D030
	LDA     #%00011000      ; Disable ROME, ROMA, ROM8
	TRB     $D030
ENDMAC

MACRO DisableInterfaceRom()
;	Use $D030 to map-out all roms 
;	by writing into $D030 
 	LDA	#%00100000
 	TRB	$D030
ENDMAC

; Used to Access the Kernel functions
; This preserces A, X, Y and the cpu flags without
; using the stack.
MACRO SetKernalOnly(QADDR, PADDR)
; 	Preserve A, X, Y, cpu flags
	PHP
	STQ	QADDR
	PLA
	STA	PADDR
;	End preserve
	; Use MAP command to map in kernel only ($3.E000 - $3.FFFF -> $E000-EFFF)
	LDA #%00000000
	LDX #%00000000
	LDY #%00000000
	LDZ #%10000011
	MAP
	EOM
; 	Recover A, X, Y, cpu flags
	LDA	PADDR
	PHA
	LDQ	QADDR
	PLP
;	End Recover
ENDMAC

; Used to Access the Kernel functions
; This preserces A, X, Y and the cpu flags without
; using the stack.
; But don't use NOP after MAP (not release Interrupt latch)
MACRO SetKernalOnlyIRQ(QADDR, PADDR)
; 	Preserve A, X, Y, cpu flags
	PHP
	STQ	QADDR
	PLA
	STA	PADDR
;	End preserve
	; Use MAP command to map in kernel only ($3.E000 - $3.FFFF -> $E000-EFFF)
	LDA #%00000000
	LDX #%00000000
	LDY #%00000000
	LDZ #%10000011
	MAP
; 	Recover A, X, Y, cpu flags
	LDA	PADDR
	PHA
	LDQ	QADDR
	PLP
;	End Recover
ENDMAC

; Use Bank 5 complete (64k)
MACRO SetBank5Only(QADDR, PADDR)
; 	Preserve A, X, Y, cpu flags
	PHP
	STQ	QADDR
	PLA
	STA	PADDR
;	End preserve
	LDA #%00000000
	LDX #%11110101
	LDY #%00000000
	LDZ #%11110101
	MAP
	EOM
; 	Recover A, X, Y, cpu flags
	LDA	PADDR
	PHA
	LDQ	QADDR
	PLP
;	End Recover
ENDMAC

; Use Bank 5 complete (64k)
MACRO SetBank5WithInterface(QADDR, PADDR)
; 	Preserve A, X, Y, cpu flags
	PHP
	STQ	QADDR
	PLA
	STA	PADDR
;	End preserve
	LDA #%00000000
	LDX #%11010101  ; Access $2000 - $3FFF
	LDY #%00000000
	LDZ #%11110101
	MAP
	EOM
; 	Recover A, X, Y, cpu flags
	LDA	PADDR
	PHA
	LDQ	QADDR
	PLP
;	End Recover
ENDMAC

; Use Bank 5 complete (64k)
; But don't user NOP after MAP (not release Interrupt latch)
MACRO SetBank5WithInterfaceIRQ(QADDR, PADDR)
; 	Preserve A, X, Y, cpu flags
	PHP
	STQ	QADDR
	PLA
	STA	PADDR
;	End preserve
	LDA #%00000000
	LDX #%11010101  ; Access $2000 - $3FFF
	LDY #%00000000
	LDZ #%11110101
	MAP
; 	Recover A, X, Y, cpu flags
	LDA	PADDR
	PHA
	LDQ	QADDR
	PLP
;	End Recover
ENDMAC

; Use Bank 5 complete (64k)
; But don't user NOP after MAP (not release Interrupt latch)
MACRO SetBank5OnlyIRQ(QADDR, PADDR)
; 	Preserve A, X, Y, cpu flags
	PHP
	STQ	QADDR
	PLA
	STA	PADDR
;	End preserve
	LDA #%00000000
	LDX #%11110101
	LDY #%00000000
	LDZ #%11110101
	MAP
; 	Recover A, X, Y, cpu flags
	LDA	PADDR
	PHA
	LDQ	QADDR
	PLP
;	End Recover
ENDMAC
