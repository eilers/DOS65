;
;Version 1.0
;Program to copy files from a Commodore drive to the destination drive.
;Written by Stefan Eilers (Based on COPY203.ASM)
;Syntax is
;	CBMFILEGET FROMFN TOFN
; FROMFN: Filename on CMB Drive 9 (max 8 chars)
; TOFN	: Filename of the file to store on CPM Drive.
pzstrt	=	$2		;start of free page zero RAM
cr	=	$d		;return
lf	=	$a		;linefeed
DFLFCB	=	$107		;default fcb
PEM	=	$103		;pem entry
BOOT	=	$100		;warm boot
TEA	=	$200		;execution org
ccmlng	=	2048		;CCM length

;CBM-Kernal
load 	=	$ffd5           ; Load
setbnk  = 	$ff6b 		; Note: Not in C64'er Kernal
setlfs 	= 	$ffba		; Set logical File
setnam 	= 	$ffbd 		; Set Name

;page zero variables
	*=	pzstrt
NAMED				;"to" file named if <128
	*=	*+1
TOIND				;"to" file index
	*=	*+2
FRMIND				;"from" file index
	*=	*+2
EOFFLG				;eof flag if >127
	*=	*+1
BUFLNG				;buffer length
	*=	*+2
;main program
	*=	TEA
;send opening banner
	lda	#<opnmsg
	ldy	#>opnmsg
	jsr	msgout
;now start processing
	SEC			;calculate
	LDA	PEM+1		;amount
	SBC	#<BUFFER	;of free memory
	AND	#$80		;in mod 128
	STA	BUFLNG		;and
	LDA	PEM+2		;save
	SBC	#>BUFFER	;for
	STA	BUFLNG+1	;read/write
	sec			;now back up before sim
	lda	BUFLNG
	sbc	#ccmlng*256/256
	sta	BUFLNG
	lda	BUFLNG+1
	sbc	#ccmlng/256
	sta	BUFLNG+1
	CLC			;now
	LDA	BUFLNG		;add
	ADC	#<BUFFER	;start
	STA	BUFLNG		;back
	LDA	BUFLNG+1	;to
	ADC	#>BUFFER	;get
	STA	BUFLNG+1	;max index
;check for ambiguous names
	LDA	#'?'		;get a ?
	LDX	#11		;set index
TSTAMB	CMP	DFLFCB,X	;test to
	BNE	*+5		;ok if not
	JMP	BADFIL		;else error
	CMP	DFLFCB+16,X	;now try ffrom
	BNE	*+5		;also ok if not
	JMP	BADFIL		;else error
	DEX			;drop index
	BNE	TSTAMB		;loop if more
;now make sure source is named
	LDA	#' '		;get a space
	CMP	DFLFCB+1	;try name
	BNE	NOTZIP		;ok if different
	CMP	DFLFCB+9	;now try type
	BNE	NOTZIP		;also ok if diff
	JMP	BADFIL		;else error
;now see if destination not named
NOTZIP	STX	NAMED		;say named for now
	CMP	DFLFCB+17	;try name
	BNE	ISNAMD		;ok if diff
	CMP	DFLFCB+25	;now try type
	BNE	ISNAMD		;also ok if diff
	DEC	NAMED		;else make neg
;set up fcbs
ISNAMD	LDX	#11		;set index
MOVNME	LDA	DFLFCB,X	;get from
	STA	FRMFCB,X	;and set
	BIT	NAMED		;test flag
	BMI	NMESME		;branch if no name
	LDA	DFLFCB+16,X	;else get to
NMESME	STA	TOFCB,X		;save "to" name
	STA	ENDFCB,X	;and in end
	DEX			;drop count
	BNE	MOVNME		;loop if more
;make sure drives are right
	LDA	DFLFCB+16	;get to
	STA	TOFCB		;and set
	STA	ENDFCB		;both to and end
	LDA	DFLFCB		;and same
	STA	FRMFCB		;for from
;clear rest of fcbs
	TXA			;clear a
	LDX	#32		;set index
CLRFCB	STA	TOFCB,X		;clear
	STA	ENDFCB,X	;all
	STA	FRMFCB,X	;fcbs
	DEX			;drop count
	CPX	#11		;see if at name
	BNE	CLRFCB		;loop if more
;make "to" a temp
	LDX	#3		;set index
	LDA	#'$'		;get byte
TMPLPE	STA	TOFCB+8,X	;insert
	DEX			;drop count
	BNE	TMPLPE		;loop if more
;try to open source
	JSR	SFMFCB		;point to fcb
	JSR	OPNFIL		;open it
	BPL	*+5		;ok
	JMP	BADFIL		;else error
;setup destination
	JSR	STOFCB		;point to "to"
	JSR	DLTFIL		;delete it
	JSR	STOFCB		;point again
	JSR	CRTFIL		;make it
	BPL	*+5		;ok
	JMP	BADFIL		;else error
	JSR	STOFCB		;one more time
	JSR	OPNFIL		;and open
	BPL	*+5		;ok
	JMP	BADFIL		;else error
;do the move
	LDA	#0		;clear eof
	STA	EOFFLG		;flag
DOMOVE	JSR	RDECBM		;read buffer
	JSR	WRTBUF		;now write it
	BIT	EOFFLG		;test flag
	BPL	DOMOVE		;loop if not
	JSR	STOFCB		;point to "to"
	JSR	CLSFIL		;close it
	BPL	*+5		;ok
	JMP	BADFIL		;else error
;delete old "end" and rename "to"
	JSR	SENFCB		;point to it
	JSR	DLTFIL		;delete it
	LDX	#11		;now move
RNMLPE	LDA	ENDFCB,X	;"end"
	STA	TOFCB+16,X	;to
	DEX			;"to"
	BNE	RNMLPE		;fcb
	JSR	STOFCB		;point to it
	JSR	RNMFIL		;and rename
	rts			;done
;subroutines
;open file
OPNFIL	LDX	#15
	JMP	PEM
;close file
CLSFIL	LDX	#16
	JMP	PEM
;delete file
DLTFIL	LDX	#19
	JMP	PEM
;read record
RDERCR	LDX	#20
	JMP	PEM
;write record
WRTRCR	LDX	#21
	JMP	PEM
;create file
CRTFIL	LDX	#22
	JMP	PEM
;rename file
RNMFIL	LDX	#23
	JMP	PEM
;set buffer
SETBUF	LDX	#26
	JMP	PEM
;set dest fcb
STOFCB	LDA	#<TOFCB
	LDY	#>TOFCB
	RTS
;set source fcb
SFMFCB	LDA	#<FRMFCB
	LDY	#>FRMFCB
	RTS
;set end fcb
SENFCB	LDA	#<ENDFCB
	LDY	#>ENDFCB
	RTS
;disk error exit
BADFIL	LDA	#<ERRMSG
	LDY	#>ERRMSG
	jsr	msgout
	JMP	BOOT
;send message to console
msgout	LDX	#9
	jmp	PEM
;write buffer
WRTBUF	LDA	#<BUFFER	;set
	LDY	#>BUFFER	;index
	STA	TOIND		;to
	STY	TOIND+1		;start
WRTLPE	LDA	TOIND		;get current
	LDY	TOIND+1		;index
	JSR	SETBUF		;and set
	LDA	TOIND		;compare index
	CMP	FRMIND		;to read
	BNE	DOWRT		;ok if diff
	LDA	TOIND+1		;do same
	CMP	FRMIND+1	;for high
	BNE	DOWRT		;index
	RTS			;else done
DOWRT	JSR	STOFCB		;point to fcb
	JSR	WRTRCR		;write record
	BEQ	*+5		;ok
	JMP	BADFIL		;else error
	CLC			;now
	LDA	TOIND		;add
	ADC	#128		;128
	STA	TOIND		;to index
	BCC	WRTLPE		;with
	INC	TOIND+1		;carry
	BNE	WRTLPE		;and loop
; Read from CBM-Drive into Buffer
RDECBM	LDA	#$00		; Not used by load
	LDX	#$09		; We expect CBM drive on 9
	LDY	#$00		; load
	JSR	setlfs
	LDA	#$08		; File name length (without ext)
	LDX	#<FRMFCB + 1    ; First byte of file name 
	LDY	#>FRMFCB + 1	; First byte of file name
	JSR 	setnam
	LDA	#$40		; LOAD + "RAW"-Mode
	LDX	#<BUFFER
	LDY	#>BUFFER		
	CLC
	JSR	load
	BCS	RDERR
	; X - Ending Address low
	; Y - Ending Address high
	STX	FRMIND		; Save end of file
	STY	FRMIND+1	; position into index 
	DEC	EOFFLG		; Mark EOF
	RTS
RDERR	JMP	BADFIL
;messages
ERRMSG	.BYTE	"ERROR - BAD FILE NAME - ABORTING$"
;opening message
opnmsg	.byte	"DOS/65 CBM FILE GET V1"
	.byte	cr,lf
	.byte	'$'
;source fcb
FRMFCB
	*=	*+33
;destination fcb
TOFCB
	*=	*+33
;end fcb
ENDFCB
	*=	*+33
;buffer
BUFFER
	.END
