; run8080: 8080 emulator as a DOS/65 transient program.
;
; PEM  Primitive Execution Module, the DOS/65 counterpart of the CP/M BDOS
; SIM  System Interface Module, the DOS/65 counterpart of the CP/M BIOS
; CCM  Console Command Module, the DOS/65 command interpreter
; TEA  Transient Execution Area, where this program is loaded ($0200)
; FCB  file control block
; TPA  transient program area, the 8080 memory a CP/M program may use
; DMA  the CP/M data address, and DMAgic, the MEGA65 block-copy engine
;
; 8080 $0000-$DFFF is bank 4 at physical $42000.  8080 $E000-$FFFF is a
; read-only stub image in Attic RAM at $8000000.  Bank 0 is never written.
; The 8080 registers live on the zero page selected by B=3, so PEM can keep
; the real zero page.  Interrupts stay off while B is not zero.

	.CPU 45GS02

pc	= 0
pc1	= 1
pc2	= 2
pc3	= 3
sp	= 4
sp1	= 5
sp2	= 6
sp3	= 7
hl	= 8
hl1	= 9
hl2	= 10
hl3	= 11
de	= 12
de1	= 13
de2	= 14
de3	= 15
bc	= 16
bc1	= 17
bc2	= 18
bc3	= 19
ra	= 20
rf	= 21
unlim	= 22
maxlo	= 23
maxhi	= 24
opcode	= 25
pclo	= 26
pchi	= 27
fetlo	= 28
fethi	= 29
val	= 30
new	= 31
olda	= 32
result	= 33
regidx	= 34
tmplo	= 35
tmphi	= 36
plo	= 37
phi	= 38
fetch	= 39
qptr	= 40
qptr1	= 41
qptr2	= 42
qptr3	= 43
alo	= 44
ahi	= 45
regslot	= 46
stopped	= 47
reason	= 48
port	= 49
dmaad	= 50
dmaad1	= 51
func	= 52
resultb	= 53
pemfn	= 54
cmpf	= 55
forcec	= 56
corr	= 57
nibh	= 58
nibl	= 59
cntlo	= 60
cnthi	= 61
ptrlo	= 62
ptrhi	= 63
destl	= 64
desth	= 65
offl	= 66
offh	= 67
dir	= 69
phys	= 70
phys1	= 71
r0	= 72
r1	= 73
r2	= 74
ins	= 76
ins1	= 77
ins2	= 78
ins3	= 79
idxb	= 80
endb	= 81
defcom	= 82
wlen	= 83
namei	= 84
tailat	= 85

; the MEGA65 ROM keeps the 80 by 50 text screen at $40800 in bank 4
scrhi	= $08

	*=	$200
	jmp	start
core_enter:
	sei
	lda	#3
	tab
	ldz	#0
	jmp	dispatch
	*=	$300
	.FILL	256 (0)

start:
	sei
	lda	#1
	sta	runmode
	lda	#3
	tab
	jsr	dma_clear_window
	jsr	dma_fill_attic
	jsr	dma_copy_stub
	jsr	dma_copy_bios
	jsr	verify_attic
	jsr	install_page0
	jsr	load_program
	jsr	clear_zp
	jsr	prime
	ldz	#0
	jmp	dispatch

dispatch:
	lda	unlim
	bne	di_go
	lda	maxlo
	ora	maxhi
	beq	di_stop
	lda	maxlo
	bne	di_lo
	dec	maxhi
di_lo:
	dec	maxlo
di_go:
	inc	ins
	bne	di_i
	inc	ins1
	bne	di_i
	inc	ins2
	bne	di_i
	inc	ins3
di_i:
	ldx	#pc
	jsr	phys_to_log
	sta	pclo
	sty	pchi
	ldz	#0
	lda	[pc],z
	sta	opcode
	inw	pc
	ldx	#pc
	jsr	fixup_inc
	lda	opcode
	asl
	tax
	bcc	di_tab
	jmp	(tabhi,x)
di_tab:
	jmp	(tablo,x)
di_stop:
	brk

; ----- pointers -----------------------------------------------------------
phys_to_log:
	lda	3,x
	cmp	#$08
	beq	pl_at
	lda	0,x
	sta	tmplo
	lda	1,x
	sec
	sbc	#$20
	tay
	lda	tmplo
	rts
pl_at:
	lda	0,x
	sta	tmplo
	lda	1,x
	clc
	adc	#$e0
	tay
	lda	tmplo
	rts

map_ea:
	sta	tmplo
	sty	tmphi
	cpy	#$e0
	bcs	me_at
	sta	0,x
	lda	tmphi
	clc
	adc	#$20
	sta	1,x
	lda	#$04
	sta	2,x
	lda	#0
	sta	3,x
	rts
me_at:
	lda	tmplo
	sta	0,x
	lda	tmphi
	sec
	sbc	#$e0
	sta	1,x
	lda	#0
	sta	2,x
	lda	#$08
	sta	3,x
	rts

fixup_inc:
	lda	3,x
	cmp	#$08
	beq	fi_at
	lda	0,x
	bne	fi_out
	lda	1,x
	bne	fi_out
	lda	#0
	sta	0,x
	sta	1,x
	sta	2,x
	lda	#$08
	sta	3,x
fi_out:
	rts
fi_at:
	lda	1,x
	cmp	#$20
	bcc	fi_out
	lda	#0
	sta	0,x
	lda	#$20
	sta	1,x
	lda	#$04
	sta	2,x
	lda	#0
	sta	3,x
	rts

fixup_dec:
	lda	3,x
	cmp	#$08
	beq	fd_at
	lda	1,x
	cmp	#$20
	bcs	fd_out
	lda	#$ff
	sta	0,x
	lda	#$1f
	sta	1,x
	lda	#0
	sta	2,x
	lda	#$08
	sta	3,x
	rts
fd_at:
	lda	1,x
	cmp	#$20
	bcc	fd_out
	lda	#$ff
	sta	0,x
	sta	1,x
	lda	#$04
	sta	2,x
	lda	#0
	sta	3,x
fd_out:
	rts

dec_ptr:
	stx	regslot
	lda	0,x
	bne	dp_low
	lda	1,x
	sec
	sbc	#1
	sta	1,x
dp_low:
	lda	0,x
	sec
	sbc	#1
	sta	0,x
	ldx	regslot
	jmp	fixup_dec

copy_x_to_q:
	lda	0,x
	sta	qptr
	lda	1,x
	sta	qptr1
	lda	2,x
	sta	qptr2
	lda	3,x
	sta	qptr3
	rts

q_sp1:
	lda	sp
	sta	qptr
	lda	sp1
	sta	qptr1
	lda	sp2
	sta	qptr2
	lda	sp3
	sta	qptr3
	inw	qptr
	ldx	#qptr
	jmp	fixup_inc

store_sp:
	lda	sp3
	cmp	#$08
	bne	ss_ok
	ldx	#sp
	jmp	stop_write
ss_ok:
	ldz	#0
	lda	val
	sta	[sp],z
	rts

store_q:
	lda	qptr3
	cmp	#$08
	bne	sq_ok
	ldx	#qptr
	jmp	stop_write
sq_ok:
	ldz	#0
	lda	val
	sta	[qptr],z
	rts

stop_write:
	jsr	phys_to_log
	sta	pclo
	sty	pchi
	lda	#5
	sta	reason
	jmp	stop

dec_sp:
	dew	sp
	ldx	#sp
	jmp	fixup_dec

inc_sp:
	inw	sp
	ldx	#sp
	jmp	fixup_inc

push_ay:
	sta	plo
	sty	phi
	jsr	dec_sp
	jsr	dec_sp
	lda	plo
	sta	val
	jsr	store_sp
	jsr	q_sp1
	lda	phi
	sta	val
	jmp	store_q

pop_ay:
	ldz	#0
	lda	[sp],z
	sta	plo
	jsr	q_sp1
	ldz	#0
	lda	[qptr],z
	sta	phi
	jsr	inc_sp
	jsr	inc_sp
	lda	plo
	ldy	phi
	rts

push_pc:
	ldx	#pc
	jsr	phys_to_log
	jmp	push_ay

fetch8:
	ldz	#0
	lda	[pc],z
	sta	fetch
	inw	pc
	ldx	#pc
	jsr	fixup_inc
	lda	fetch
	rts

fetch16:
	jsr	fetch8
	sta	fetlo
	jsr	fetch8
	sta	fethi
	rts

read_ptr:
	ldx	#qptr
	lda	ptrlo
	ldy	ptrhi
	jsr	map_ea
	ldz	#0
	lda	[qptr],z
	rts

inc_logical:
	inc	ptrlo
	bne	il_ok
	inc	ptrhi
il_ok:
	rts

write_ptr:
	sta	val
	ldx	#qptr
	lda	ptrlo
	ldy	ptrhi
	jsr	map_ea
	jmp	store_q

write_adv:
	jsr	write_ptr
	jmp	inc_logical

; ----- registers and flags ------------------------------------------------
getreg:
	sta	regidx
	cmp	#7
	bne	gr1
	lda	ra
	rts
gr1:
	cmp	#6
	bne	gr2
	ldz	#0
	lda	[hl],z
	rts
gr2:
	tay
	ldx	regzp,y
	jsr	phys_to_log
	sta	tmplo
	sty	tmphi
	ldy	regidx
	ldx	reghi,y
	beq	gr_lo
	lda	tmphi
	rts
gr_lo:
	lda	tmplo
	rts

setreg:
	sta	new
	lda	regidx
	cmp	#7
	bne	sr1
	lda	new
	sta	ra
	rts
sr1:
	cmp	#6
	bne	sr2
	ldx	#hl
	jsr	copy_x_to_q
	lda	new
	sta	val
	jmp	store_q
sr2:
	tay
	ldx	regzp,y
	stx	regslot
	jsr	phys_to_log
	sta	tmplo
	sty	tmphi
	ldy	regidx
	ldx	reghi,y
	beq	sr_lo
	lda	new
	sta	tmphi
	jmp	sr_map
sr_lo:
	lda	new
	sta	tmplo
sr_map:
	ldx	regslot
	lda	tmplo
	ldy	tmphi
	jmp	map_ea

apply_a:
	tax
	lda	szp,x
	ora	#$02
	sta	fetch
	lda	rf
	and	#$11
	ora	fetch
	sta	rf
	rts

apply_res:
	lda	result
	jmp	apply_a

setc1:
	lda	rf
	ora	#1
	sta	rf
	rts

setc0:
	lda	rf
	and	#$fe
	sta	rf
	rts

seth1:
	lda	rf
	ora	#$10
	sta	rf
	rts

seth0:
	lda	rf
	and	#$ef
	sta	rf
	rts

cond:
	tay
	lda	rf
	and	cmask,y
	cmp	cwant,y
	rts

; ----- ALU ----------------------------------------------------------------
do_add:
	lda	ra
	sta	olda
	clc
	adc	val
	sta	ra
	sta	result
	jmp	finish_add

do_adc:
	lda	ra
	sta	olda
	lda	rf
	lsr
	lda	olda
	adc	val
	sta	ra
	sta	result
finish_add:
	jsr	apply_res
	bcc	fa0
	jsr	setc1
	jmp	half_add
fa0:
	jsr	setc0
	jmp	half_add

half_add:
	lda	olda
	eor	val
	eor	result
	and	#$10
	beq	ha0
	jsr	seth1
	jmp	dispatch
ha0:
	jsr	seth0
	jmp	dispatch

do_sub:
	lda	#0
	sta	cmpf
	sec
	jmp	sub_go

do_sbb:
	lda	#0
	sta	cmpf
	lda	rf
	eor	#1
	lsr
	jmp	sub_go

do_cmp:
	lda	#1
	sta	cmpf
	sec
sub_go:
	lda	ra
	sta	olda
	sbc	val
	sta	result
	lda	cmpf
	bne	sg_keep
	lda	result
	sta	ra
sg_keep:
	jsr	apply_res
	bcc	sg_b
	jsr	setc0
	jmp	half_sub
sg_b:
	jsr	setc1
half_sub:
	lda	olda
	eor	val
	eor	result
	and	#$10
	beq	hs1
	jsr	seth0
	jmp	dispatch
hs1:
	jsr	seth1
	jmp	dispatch

do_ana:
	lda	ra
	ora	val
	and	#$08
	beq	an0
	lda	#1
	bne	an1
an0:
	lda	#0
an1:
	sta	forcec
	lda	ra
	and	val
	sta	ra
	sta	result
	jsr	apply_res
	jsr	setc0
	lda	forcec
	beq	an_h
	jsr	seth1
	jmp	dispatch
an_h:
	jsr	seth0
	jmp	dispatch

do_xra:
	lda	ra
	eor	val
	sta	ra
	sta	result
	jsr	apply_res
	jsr	setc0
	jsr	seth0
	jmp	dispatch

do_ora:
	lda	ra
	ora	val
	sta	ra
	sta	result
	jsr	apply_res
	jsr	setc0
	jsr	seth0
	jmp	dispatch

do_inr:
	clc
	adc	#1
	sta	result
	jsr	apply_res
	lda	result
	and	#$0f
	beq	inr_h
	jsr	seth0
	jmp	inr_s
inr_h:
	jsr	seth1
inr_s:
	lda	result
	jsr	setreg
	jmp	dispatch

do_dcr:
	sec
	sbc	#1
	sta	result
	jsr	apply_res
	lda	result
	and	#$0f
	cmp	#$0f
	beq	dcr_h
	jsr	seth1
	jmp	dcr_s
dcr_h:
	jsr	seth0
dcr_s:
	lda	result
	jsr	setreg
	jmp	dispatch

do_dad:
	jsr	phys_to_log
	sta	plo
	sty	phi
	ldx	#hl
	jsr	phys_to_log
	clc
	adc	plo
	sta	plo
	tya
	adc	phi
	sta	phi
	lda	#0
	rol
	sta	resultb
	ldx	#hl
	lda	plo
	ldy	phi
	jsr	map_ea
	lda	resultb
	bne	dd1
	jsr	setc0
	jmp	dispatch
dd1:
	jsr	setc1
	jmp	dispatch

do_rlc:
	lda	ra
	asl
	bcc	rlc0
	ora	#1
	sta	ra
	jsr	setc1
	jmp	dispatch
rlc0:
	sta	ra
	jsr	setc0
	jmp	dispatch

do_rrc:
	lda	ra
	lsr
	bcc	rrc0
	ora	#$80
	sta	ra
	jsr	setc1
	jmp	dispatch
rrc0:
	sta	ra
	jsr	setc0
	jmp	dispatch

do_ral:
	lda	rf
	lsr
	lda	ra
	rol
	sta	ra
	bcs	ral1
	jsr	setc0
	jmp	dispatch
ral1:
	jsr	setc1
	jmp	dispatch

do_rar:
	lda	rf
	lsr
	lda	ra
	ror
	sta	ra
	bcs	rar1
	jsr	setc0
	jmp	dispatch
rar1:
	jsr	setc1
	jmp	dispatch

do_cma:
	lda	ra
	eor	#$ff
	sta	ra
	jmp	dispatch

do_stc:
	jsr	setc1
	jmp	dispatch

do_cmc:
	lda	rf
	eor	#1
	sta	rf
	jmp	dispatch

do_daa:
	lda	ra
	and	#$0f
	sta	nibl
	lda	ra
	lsr
	lsr
	lsr
	lsr
	sta	nibh
	lda	#0
	sta	corr
	lda	nibl
	cmp	#10
	bcs	da_6
	lda	rf
	and	#$10
	beq	da_no6
da_6:
	lda	#6
	sta	corr
da_no6:
	lda	#0
	sta	forcec
	lda	nibh
	cmp	#10
	bcs	da_60
	lda	rf
	and	#1
	bne	da_60
	lda	nibh
	cmp	#9
	bcc	da_add
	lda	nibl
	cmp	#10
	bcc	da_add
da_60:
	lda	corr
	ora	#$60
	sta	corr
	lda	#1
	sta	forcec
da_add:
	lda	corr
	sta	val
	lda	ra
	sta	olda
	clc
	adc	val
	sta	ra
	sta	result
	jsr	apply_res
	lda	olda
	eor	val
	eor	result
	and	#$10
	beq	da_h0
	jsr	seth1
	jmp	da_c
da_h0:
	jsr	seth0
da_c:
	lda	forcec
	beq	da_c0
	jsr	setc1
	jmp	dispatch
da_c0:
	jsr	setc0
	jmp	dispatch

; ----- memory and flow ----------------------------------------------------
do_stax:
	jsr	copy_x_to_q
	lda	ra
	sta	val
	jsr	store_q
	jmp	dispatch

do_ldax:
	jsr	copy_x_to_q
	ldz	#0
	lda	[qptr],z
	sta	ra
	jmp	dispatch

do_sta:
	jsr	fetch16
	ldx	#qptr
	lda	fetlo
	ldy	fethi
	jsr	map_ea
	lda	ra
	sta	val
	jsr	store_q
	jmp	dispatch

do_lda:
	jsr	fetch16
	ldx	#qptr
	lda	fetlo
	ldy	fethi
	jsr	map_ea
	ldz	#0
	lda	[qptr],z
	sta	ra
	jmp	dispatch

do_shld:
	jsr	fetch16
	ldx	#hl
	jsr	phys_to_log
	sta	plo
	sty	phi
	ldx	#qptr
	lda	fetlo
	ldy	fethi
	jsr	map_ea
	lda	plo
	sta	val
	jsr	store_q
	inw	qptr
	ldx	#qptr
	jsr	fixup_inc
	lda	phi
	sta	val
	jsr	store_q
	jmp	dispatch

do_lhld:
	jsr	fetch16
	ldx	#qptr
	lda	fetlo
	ldy	fethi
	jsr	map_ea
	ldz	#0
	lda	[qptr],z
	sta	plo
	inw	qptr
	ldx	#qptr
	jsr	fixup_inc
	ldz	#0
	lda	[qptr],z
	tay
	ldx	#hl
	lda	plo
	jsr	map_ea
	jmp	dispatch

do_jmp:
	jsr	fetch16
do_take:
	ldx	#pc
	lda	fetlo
	ldy	fethi
	jsr	map_ea
	jmp	dispatch

do_call:
	jsr	fetch16
do_call_take:
	jsr	push_pc
	jmp	do_take

do_ret:
	jsr	pop_ay
	ldx	#pc
	jsr	map_ea
	jmp	dispatch

do_rst:
	sta	fetlo
	lda	#0
	sta	fethi
	jsr	push_pc
	jmp	do_take

do_push:
	jsr	phys_to_log
	jsr	push_ay
	jmp	dispatch

do_pop:
	stx	regslot
	jsr	pop_ay
	ldx	regslot
	jsr	map_ea
	jmp	dispatch

do_push_psw:
	lda	rf
	ldy	ra
	jsr	push_ay
	jmp	dispatch

do_pop_psw:
	jsr	pop_ay
	and	#$d5
	ora	#$02
	sta	rf
	tya
	sta	ra
	jmp	dispatch

do_xchg:
	ldx	#3
xg:
	lda	hl,x
	sta	val
	lda	de,x
	sta	hl,x
	lda	val
	sta	de,x
	dex
	bpl	xg
	jmp	dispatch

do_xthl:
	jsr	pop_ay
	sta	r0
	sty	r1
	ldx	#hl
	jsr	phys_to_log
	jsr	push_ay
	ldx	#hl
	lda	r0
	ldy	r1
	jsr	map_ea
	jmp	dispatch

do_pchl:
	lda	hl
	sta	pc
	lda	hl1
	sta	pc1
	lda	hl2
	sta	pc2
	lda	hl3
	sta	pc3
	jmp	dispatch

do_sphl:
	lda	hl
	sta	sp
	lda	hl1
	sta	sp1
	lda	hl2
	sta	sp2
	lda	hl3
	sta	sp3
	jmp	dispatch

do_hlt:
	lda	runmode
	beq	dh_test
	jmp	warm_exit
dh_test:
	ldx	#pc
	jsr	dec_ptr
	lda	#1
	sta	stopped
	lda	#1
	sta	reason
	brk

do_in:
	jsr	fetch8
	lda	#2
	sta	reason
	jmp	stop

do_out:
	jsr	fetch8
	sta	port
	lda	pchi
	cmp	#$e0
	bcc	out_bad
	lda	port
	beq	bdos_entry
	cmp	#1
	beq	warm_exit
	sta	func
	lda	#8
	sta	reason
	jmp	stop
out_bad:
	lda	#3
	sta	reason
	jmp	stop

stop_prefix:
	lda	#4
	sta	reason
	jmp	stop

stop:
	lda	#1
	sta	stopped
	lda	runmode
	bne	stop_go
	brk
stop_go:
	jsr	print_stop
	jmp	warm_exit

warm_exit:
	lda	#0
	tab
	jmp	$0100

; ----- BDOS ----------------------------------------------------------------
bdos_entry:
	ldx	#bc
	jsr	phys_to_log
	sta	func
	cmp	#41
	bcs	stop_fn
	asl
	tax
	jmp	(fntab,x)

stop_fn:
	lda	#6
	sta	reason
	jmp	stop

ret_a:
	ldy	#0
ret_word:
	sta	ra
	sty	phi
	lda	#5
	sta	regidx
	lda	ra
	jsr	setreg
	lda	#4
	sta	regidx
	lda	phi
	jsr	setreg
	lda	#0
	sta	regidx
	lda	phi
	jsr	setreg
	lda	ra
	jsr	apply_a
	jsr	seth0
	jsr	setc0
	jmp	dispatch

fn1:
	ldx	#1
	lda	#0
	tay
	jsr	pemcall
	jmp	ret_a

fn2:
	lda	#2
	jmp	pass_e

fn3:
	ldx	#3
	lda	#0
	tay
	jsr	pemcall
	jmp	ret_a

fn4:
	lda	#4
	jmp	pass_e

fn5:
	lda	#5
	jmp	pass_e

pass_e:
	sta	pemfn
	ldx	#de
	jsr	phys_to_log
	ldy	#0
	ldx	pemfn
	jsr	pemcall
	jmp	ret_a

fn6:
	ldx	#de
	jsr	phys_to_log
	cmp	#$ff
	beq	f6in
	cmp	#$fe
	beq	f6st
	jsr	adm_out
	lda	#0
	jmp	ret_a
f6st:
	ldx	#11
	lda	#0
	tay
	jsr	pemcall
	cmp	#0
	bne	f6nz
	jmp	ret_a
f6nz:
	lda	#$ff
	jmp	ret_a
f6in:
	ldx	#11
	lda	#0
	tay
	jsr	pemcall
	cmp	#0
	bne	f6key
	jmp	ret_a
f6key:
	ldx	#6
	lda	#0
	tay
	jsr	pemcall
	jsr	mapkey
	jmp	ret_a

mapkey:
	cmp	#$91
	bne	mk1
	lda	#$0b
	rts
mk1:
	cmp	#$11
	bne	mk2
	lda	#$0a
	rts
mk2:
	cmp	#$9d
	bne	mk3
	lda	#$08
	rts
mk3:
	cmp	#$1d
	bne	mk4
	lda	#$0c
mk4:
	rts

fn7:
	ldx	#qptr
	lda	#3
	ldy	#0
	jsr	map_ea
	ldz	#0
	lda	[qptr],z
	jmp	ret_a

fn8:
	ldx	#de
	jsr	phys_to_log
	sta	glyph
	ldx	#qptr
	lda	#3
	ldy	#0
	jsr	map_ea
	lda	glyph
	sta	val
	jsr	store_q
	lda	glyph
	jmp	ret_a

fn9:
	ldx	#de
	jsr	phys_to_log
	sta	ptrlo
	sty	ptrhi
fn9l:
	jsr	read_ptr
	cmp	#'$'
	beq	fn9d
	ldy	#0
	ldx	#2
	jsr	pemcall
	jsr	inc_logical
	jmp	fn9l
fn9d:
	lda	#0
	jmp	ret_a

fn10:
	ldx	#de
	jsr	phys_to_log
	sta	ptrlo
	sty	ptrhi
	sta	linlo
	sty	linhi
	jsr	read_ptr
	clc
	adc	#2
	cmp	#129
	bcc	fn10a
	lda	#128
fn10a:
	sta	cntlo
	sta	savedn
	lda	#0
	sta	cnthi
	lda	#<linbuf
	sta	destl
	lda	#>linbuf
	sta	desth
	lda	#1
	sta	dir
	jsr	dma_between
	lda	#<linbuf
	ldy	#>linbuf
	ldx	#10
	jsr	pemcall
	lda	linlo
	sta	ptrlo
	lda	linhi
	sta	ptrhi
	lda	savedn
	sta	cntlo
	lda	#0
	sta	cnthi
	lda	#<linbuf
	sta	destl
	lda	#>linbuf
	sta	desth
	lda	#0
	sta	dir
	jsr	dma_between
	lda	#0
	jmp	ret_a

fn11:
	ldx	#11
	lda	#0
	tay
	jsr	pemcall
	cmp	#0
	bne	f11nz
	jmp	ret_a
f11nz:
	lda	#$ff
	jmp	ret_a

fn12:
	lda	#$22
	ldy	#0
	jmp	ret_word

fn13:
	ldx	#13
	lda	#0
	tay
	jsr	pemcall
	lda	#$80
	sta	dmaad
	lda	#0
	sta	dmaad1
	jmp	ret_a

fn14:
	lda	#14
	jmp	pass_e

fn15:
	lda	#15
	jmp	fcb_simple
fn16:
	lda	#16
	jmp	fcb_simple
fn19:
	lda	#19
	jmp	fcb_simple
fn22:
	lda	#22
	jmp	fcb_simple
fn23:
	lda	#23
	jmp	fcb_simple

fcb_simple:
	sta	pemfn
	jsr	fcb_in
	lda	#<fcb65
	ldy	#>fcb65
	ldx	pemfn
	jsr	pemcall
	sta	resultb
	jsr	fcb_out
	lda	resultb
	jmp	ret_a

fn17:
	jsr	fcb_in
	jsr	use_recbuf
	lda	#<fcb65
	ldy	#>fcb65
	ldx	#17
	jsr	pemcall
	sta	resultb
	jsr	fcb_out
	lda	resultb
	beq	f17ok
	jmp	ret_a
f17ok:
	jsr	rec_to_8080
	lda	#0
	jmp	ret_a

fn18:
	jsr	use_recbuf
	ldx	#18
	lda	#0
	tay
	jsr	pemcall
	sta	resultb
	lda	resultb
	beq	f18ok
	jmp	ret_a
f18ok:
	jsr	rec_to_8080
	lda	#0
	jmp	ret_a

fn20:
	jsr	fcb_in
	jsr	use_recbuf
	lda	#<fcb65
	ldy	#>fcb65
	ldx	#20
	jsr	pemcall
	sta	resultb
	jsr	fcb_out
	lda	resultb
	beq	f20ok
	jmp	ret_a
f20ok:
	jsr	rec_to_8080
	lda	#0
	jmp	ret_a

fn21:
	jsr	dma_to_rec
	jsr	fcb_in
	jsr	use_recbuf
	lda	#<fcb65
	ldy	#>fcb65
	ldx	#21
	jsr	pemcall
	sta	resultb
	jsr	fcb_out
	lda	resultb
	jmp	ret_a

fn24:
	ldx	#24
	lda	#0
	tay
	jsr	pemcall
	ldy	#0
	jmp	ret_word

fn25:
	ldx	#25
	lda	#0
	tay
	jsr	pemcall
	jmp	ret_a

fn26:
	ldx	#de
	jsr	phys_to_log
	sta	dmaad
	sty	dmaad1
	lda	#0
	jmp	ret_a

fn27:
	ldx	#27
	lda	#0
	tay
	jsr	pemcall
	jmp	ret_word

fn28:
	ldx	#28
	lda	#0
	tay
	jsr	pemcall
	jmp	ret_a

fn29:
	ldx	#29
	lda	#0
	tay
	jsr	pemcall
	jmp	ret_word

fn31:
	ldx	#34
	lda	#0
	tay
	jsr	pemcall
	sta	destl
	sty	desth
	ldy	#13
fn31c:
	lda	(destl),y
	sta	dcbcopy,y
	dey
	bpl	fn31c
	jsr	build_dpb
	lda	#0
	sta	ptrlo
	lda	#$f0
	sta	ptrhi
	lda	#<dpbtmp
	sta	destl
	lda	#>dpbtmp
	sta	desth
	lda	#15
	sta	cntlo
	lda	#0
	sta	cnthi
	sta	dir
	jsr	dma_between
	lda	#0
	ldy	#$f0
	jmp	ret_word

fn32:
	ldx	#de
	jsr	phys_to_log
	cmp	#$ff
	beq	fn32g
	cmp	#0
	bne	fn32b
	lda	#0
	jmp	ret_a
fn32g:
	lda	#0
	jmp	ret_a
fn32b:
	lda	#7
	sta	reason
	jmp	stop

fn33:
	jsr	fcb_in
	jsr	load_rr
	lda	r2
	beq	fn33ok
	lda	#6
	jmp	ret_a
fn33ok:
	jsr	apply_rr
	jsr	use_recbuf
	lda	#<fcb65
	ldy	#>fcb65
	ldx	#20
	jsr	pemcall
	sta	resultb
	jsr	apply_rr
	jsr	fcb_out
	lda	resultb
	beq	f33ok
	jmp	ret_a
f33ok:
	jsr	rec_to_8080
	lda	#0
	jmp	ret_a

fn34:
	jsr	fcb_in
	jsr	load_rr
	lda	r2
	beq	fn34ok
	lda	#6
	jmp	ret_a
fn34ok:
	jsr	dma_to_rec
	jsr	apply_rr
	jsr	use_recbuf
	lda	#<fcb65
	ldy	#>fcb65
	ldx	#21
	jsr	pemcall
	sta	resultb
	jsr	apply_rr
	jsr	fcb_out
	lda	resultb
	jmp	ret_a

fn35:
	jsr	fcb_in
	lda	#0
	sta	r0
	sta	r1
	sta	r2
	lda	#<fcb65
	ldy	#>fcb65
	ldx	#15
	jsr	pemcall
	cmp	#$ff
	beq	fn35z
fn35l:
	jsr	use_recbuf
	lda	#<fcb65
	ldy	#>fcb65
	ldx	#20
	jsr	pemcall
	cmp	#0
	bne	fn35z
	inc	r0
	bne	fn35l
	inc	r1
	bne	fn35l
	inc	r2
	jmp	fn35l
fn35z:
	jsr	store_random
	lda	#0
	jmp	ret_a

fn36:
	lda	#12
	jsr	read_off
	and	#$1f
	sta	r0
	lda	#14
	jsr	read_off
	and	#$3f
	sta	r1
	lda	#32
	jsr	read_off
	sta	r2
	lda	r1
	and	#7
	asl
	asl
	asl
	asl
	asl
	sta	tmplo
	lda	r0
	and	#$1f
	ora	tmplo
	sta	tmphi
	lda	r1
	lsr
	lsr
	lsr
	sta	alo
	lda	r2
	and	#$7f
	sta	r0
	lda	tmphi
	and	#1
	beq	f36a
	lda	r0
	ora	#$80
	sta	r0
f36a:
	lda	tmphi
	lsr
	sta	r1
	lda	alo
	and	#1
	beq	f36b
	lda	r1
	ora	#$80
	sta	r1
f36b:
	lda	alo
	lsr
	sta	r2
	jsr	store_random
	lda	#0
	jmp	ret_a

fn37:
	lda	#0
	jmp	ret_a

load_rr:
	ldx	#de
	jsr	phys_to_log
	clc
	adc	#33
	sta	ptrlo
	tya
	adc	#0
	sta	ptrhi
	jsr	read_ptr
	sta	r0
	jsr	inc_logical
	jsr	read_ptr
	sta	r1
	jsr	inc_logical
	jsr	read_ptr
	sta	r2
	rts

apply_rr:
	lda	r0
	and	#$7f
	sta	fcb65+32
	lda	r0
	asl
	lda	#0
	adc	#0
	sta	tmplo
	lda	r1
	asl
	ora	tmplo
	and	#$1f
	sta	fcb65+12
	lda	r1
	lsr
	lsr
	lsr
	lsr
	sta	fcb65+14
	rts

read_off:
	sta	val
	ldx	#de
	jsr	phys_to_log
	clc
	adc	val
	sta	ptrlo
	tya
	adc	#0
	sta	ptrhi
	jmp	read_ptr

store_random:
	ldx	#de
	jsr	phys_to_log
	clc
	adc	#33
	sta	ptrlo
	tya
	adc	#0
	sta	ptrhi
	lda	r0
	jsr	write_adv
	lda	r1
	jsr	write_adv
	lda	r2
	jmp	write_ptr

fcb_in:
	ldx	#de
	jsr	phys_to_log
	sta	ptrlo
	sty	ptrhi
	lda	#<fcb65
	sta	destl
	lda	#>fcb65
	sta	desth
	lda	#33
	sta	cntlo
	lda	#0
	sta	cnthi
	lda	#1
	sta	dir
	jmp	dma_between

fcb_out:
	ldx	#de
	jsr	phys_to_log
	sta	ptrlo
	sty	ptrhi
	lda	#<fcb65
	sta	destl
	lda	#>fcb65
	sta	desth
	lda	#33
	sta	cntlo
	lda	#0
	sta	cnthi
	lda	#0
	sta	dir
	jmp	dma_between

use_recbuf:
	lda	#<recbuf
	ldy	#>recbuf
	ldx	#26
	jmp	pemcall

rec_to_8080:
	lda	dmaad
	sta	ptrlo
	lda	dmaad1
	sta	ptrhi
	lda	#<recbuf
	sta	destl
	lda	#>recbuf
	sta	desth
	lda	#128
	sta	cntlo
	lda	#0
	sta	cnthi
	sta	dir
	jmp	dma_between

dma_to_rec:
	lda	dmaad
	sta	ptrlo
	lda	dmaad1
	sta	ptrhi
	lda	#<recbuf
	sta	destl
	lda	#>recbuf
	sta	desth
	lda	#128
	sta	cntlo
	lda	#0
	sta	cnthi
	lda	#1
	sta	dir
	jmp	dma_between

; ----- ADM-3A on the top 24 rows of the 80 by 50 screen -------------------
adm_out:
	sta	glyph
	lda	admst
	beq	ad_norm
	cmp	#1
	beq	ad_esc
	cmp	#2
	beq	ad_srow
	jmp	ad_scol
ad_norm:
	lda	glyph
	cmp	#$1a
	bne	ad_ncls
	jmp	do_cls
ad_ncls:
	cmp	#$1b
	beq	ad_set1
	cmp	#$0d
	bne	ad_ncr
	jmp	do_cr
ad_ncr:
	cmp	#$0a
	bne	ad_nlf
	jmp	do_lf
ad_nlf:
	cmp	#$20
	bcc	ad_ign
	jsr	putcell
	jmp	advance
ad_ign:
	rts
ad_set1:
	lda	#1
	sta	admst
	rts
ad_esc:
	lda	glyph
	cmp	#'='
	bne	ad_res
	lda	#2
	sta	admst
	rts
ad_res:
	lda	#0
	sta	admst
	rts
ad_srow:
	lda	glyph
	jsr	clamp24
	sta	admsrow
	lda	#3
	sta	admst
	rts
ad_scol:
	lda	glyph
	jsr	clamp80
	sta	scol
	lda	admsrow
	sta	srow
	lda	#0
	sta	admst
	rts

clamp24:
	sec
	sbc	#32
	bcs	c24
	lda	#0
c24:
	cmp	#24
	bcc	c24ok
	lda	#23
c24ok:
	rts

clamp80:
	sec
	sbc	#32
	bcs	c80
	lda	#0
c80:
	cmp	#80
	bcc	c80ok
	lda	#79
c80ok:
	rts

do_cr:
	lda	#0
	sta	scol
	rts

do_lf:
	inc	srow
	lda	srow
	cmp	#24
	bcc	lf_ok
	jsr	scroll
	lda	#23
	sta	srow
lf_ok:
	rts

advance:
	inc	scol
	lda	scol
	cmp	#80
	bcc	adv_ok
	lda	#0
	sta	scol
	jmp	do_lf
adv_ok:
	rts

do_cls:
	jsr	screen_clear
	lda	#0
	sta	srow
	sta	scol
	sta	admst
	rts

putcell:
	lda	srow
	sta	offl
	lda	#0
	sta	offh
	ldx	#6
sh6:
	asl	offl
	rol	offh
	dex
	bne	sh6
	lda	srow
	sta	alo
	lda	#0
	sta	ahi
	ldx	#4
sh4:
	asl	alo
	rol	ahi
	dex
	bne	sh4
	lda	offl
	clc
	adc	alo
	sta	offl
	lda	offh
	adc	ahi
	sta	offh
	lda	scol
	clc
	adc	offl
	sta	qptr
	lda	offh
	adc	#scrhi
	sta	qptr1
	lda	#4
	sta	qptr2
	lda	#0
	sta	qptr3
	ldz	#0
	lda	glyph
	sta	[qptr],z
	rts

; ----- loader -------------------------------------------------------------
load_program:
	lda	$0128
	sta	endb
	bne	ld_tail
	jmp	ld_fcb
ld_tail:
	lda	#1
	sta	idxb
	jsr	skip_sp
	jsr	read_word
	lda	wlen
	bne	ld_name
	jmp	ld_fcb
ld_name:
	lda	#1
	sta	defcom
	jsr	word_to
	jsr	open_word
	jsr	read_records
	jmp	build_args

ld_fcb:
	jsr	blank_fcb
	ldy	#0
lf_c:
	lda	$0108,y
	sta	fcbt+1,y
	iny
	cpy	#11
	bne	lf_c
	lda	fcbt+1
	cmp	#' '
	bne	lf_ext
	lda	#10
	sta	reason
	jmp	stop
lf_ext:
	lda	fcbt+9
	cmp	#' '
	bne	lf_open
	lda	#'C'
	sta	fcbt+9
	lda	#'O'
	sta	fcbt+10
	lda	#'M'
	sta	fcbt+11
lf_open:
	jsr	open_word
	jsr	read_records
	lda	#0
	sta	tailat
	sta	endb
	jsr	blank_fcb
	jsr	dma_fcb
	jsr	blank_fcb
	lda	#$6c
	sta	ptrlo
	jsr	dma_fcb_at
	jmp	empty_tail

skip_sp:
	lda	idxb
	cmp	endb
	beq	sk_one
	bcs	sk_done
sk_one:
	ldy	idxb
	lda	$0128,y
	cmp	#' '
	bne	sk_done
	inc	idxb
	bne	skip_sp
sk_done:
	rts

read_word:
	lda	#0
	sta	wlen
rw:
	lda	idxb
	cmp	endb
	beq	rw_one
	bcs	rw_done
rw_one:
	ldy	idxb
	lda	$0128,y
	cmp	#' '
	beq	rw_done
	jsr	upcase
	ldy	wlen
	cpy	#16
	bcs	rw_sk
	sta	wordbuf,y
	inc	wlen
rw_sk:
	inc	idxb
	bne	rw
rw_done:
	rts

upcase:
	cmp	#'a'
	bcc	up_no
	cmp	#'z'+1
	bcs	up_no
	and	#$5f
up_no:
	rts

blank_fcb:
	ldy	#35
	lda	#0
bl:
	sta	fcbt,y
	dey
	bpl	bl
	ldy	#10
	lda	#' '
bn:
	sta	fcbt+1,y
	dey
	bpl	bn
	rts

word_to:
	jsr	blank_fcb
	ldx	#0
	lda	wlen
	cmp	#3
	bcc	wt_s
	lda	wordbuf+1
	cmp	#':'
	bne	wt_s
	lda	wordbuf
	sec
	sbc	#'A'
	clc
	adc	#1
	sta	fcbt
	ldx	#2
wt_s:
	lda	#1
	sta	namei
wt:
	cpx	wlen
	bcs	wt_ext
	lda	wordbuf,x
	inx
	cmp	#'.'
	beq	wt_dot
	ldy	namei
	cpy	#12
	bcs	wt
	sta	fcbt,y
	inc	namei
	jmp	wt
wt_dot:
	lda	#9
	sta	namei
	jmp	wt
wt_ext:
	lda	defcom
	beq	wt_done
	lda	fcbt+9
	cmp	#' '
	bne	wt_done
	lda	#'C'
	sta	fcbt+9
	lda	#'O'
	sta	fcbt+10
	lda	#'M'
	sta	fcbt+11
wt_done:
	rts

open_word:
	ldy	#0
ow:
	lda	fcbt,y
	sta	fcb65,y
	iny
	cpy	#33
	bne	ow
	lda	#<fcb65
	ldy	#>fcb65
	ldx	#15
	jsr	pemcall
	cmp	#$ff
	bne	ow_ok
	lda	#10
	sta	reason
	jmp	stop
ow_ok:
	rts

read_records:
	lda	#0
	sta	ptrlo
	lda	#1
	sta	ptrhi
rr:
	lda	ptrhi
	cmp	#$df
	bcc	rr_ok
	cmp	#$e0
	bcs	rr_big
	lda	ptrlo
	cmp	#$80
	bcc	rr_ok
rr_big:
	lda	#11
	sta	reason
	jmp	stop
rr_ok:
	jsr	use_recbuf
	lda	#<fcb65
	ldy	#>fcb65
	ldx	#20
	jsr	pemcall
	cmp	#0
	bne	rr_done
	lda	#<recbuf
	sta	destl
	lda	#>recbuf
	sta	desth
	lda	#128
	sta	cntlo
	lda	#0
	sta	cnthi
	sta	dir
	jsr	dma_between
	lda	ptrlo
	clc
	adc	#128
	sta	ptrlo
	bcc	rr
	inc	ptrhi
	jmp	rr
rr_done:
	rts

build_args:
	lda	idxb
	sta	tailat
	jsr	skip_sp
	lda	#0
	sta	defcom
	jsr	read_word
	jsr	word_to
	lda	#$5c
	sta	ptrlo
	lda	#0
	sta	ptrhi
	jsr	dma_fcb_at
	jsr	skip_sp
	jsr	read_word
	jsr	word_to
	lda	#$6c
	sta	ptrlo
	jsr	dma_fcb_at
	jmp	make_tail

dma_fcb:
	lda	#$5c
	sta	ptrlo
	lda	#0
	sta	ptrhi
dma_fcb_at:
	lda	#<fcbt
	sta	destl
	lda	#>fcbt
	sta	desth
	lda	#36
	sta	cntlo
	lda	#0
	sta	cnthi
	sta	dir
	jmp	dma_between

make_tail:
	ldy	#127
	lda	#0
mt_z:
	sta	tailtmp,y
	dey
	bpl	mt_z
	lda	tailat
	sta	idxb
	lda	#1
	sta	namei
mt_l:
	lda	idxb
	cmp	endb
	beq	mt_one
	bcs	mt_fin
mt_one:
	lda	namei
	cmp	#128
	bcs	mt_fin
	ldy	idxb
	lda	$0128,y
	ldy	namei
	sta	tailtmp,y
	inc	namei
	inc	idxb
	bne	mt_l
mt_fin:
	lda	namei
	sec
	sbc	#1
	sta	tailtmp
empty_tail:
	lda	#$80
	sta	ptrlo
	lda	#0
	sta	ptrhi
	lda	#<tailtmp
	sta	destl
	lda	#>tailtmp
	sta	desth
	lda	#128
	sta	cntlo
	lda	#0
	sta	cnthi
	sta	dir
	jmp	dma_between

install_page0:
	lda	#0
	sta	ptrlo
	sta	ptrhi
	lda	#<pageimg
	sta	destl
	lda	#>pageimg
	sta	desth
	lda	#8
	sta	cntlo
	lda	#0
	sta	cnthi
	sta	dir
	jmp	dma_between

clear_zp:
	ldx	#0
	txa
cz:
	sta	0,x
	inx
	bne	cz
	rts

prime:
	ldx	#bc
	lda	#0
	tay
	jsr	map_ea
	ldx	#de
	lda	#0
	tay
	jsr	map_ea
	ldx	#hl
	lda	#0
	tay
	jsr	map_ea
	ldx	#sp
	lda	#0
	ldy	#$e0
	jsr	map_ea
	lda	#0
	tay
	jsr	push_ay
	ldx	#pc
	lda	#0
	ldy	#1
	jsr	map_ea
	lda	#$02
	sta	rf
	lda	#0
	sta	ra
	lda	#$80
	sta	dmaad
	lda	#0
	sta	dmaad1
	lda	#$ff
	sta	unlim
	lda	#0
	sta	stopped
	sta	reason
	rts

verify_attic:
	ldx	#qptr
	lda	#0
	ldy	#$e0
	jsr	map_ea
	ldz	#0
	lda	[qptr],z
	cmp	#$d3
	beq	ver_ok
	lda	#9
	sta	reason
	jmp	stop
ver_ok:
	rts

; ----- disk parameter block from the DOS/65 disk control block ------------
build_dpb:
	lda	dcbcopy+2
	sta	dpbtmp
	lda	dcbcopy+3
	sta	dpbtmp+1
	lda	dcbcopy+6
	clc
	adc	#3
	sta	bshv
	sta	dpbtmp+2
	lda	#1
	ldx	bshv
bd_bl:
	asl
	dex
	bne	bd_bl
	sec
	sbc	#1
	sta	dpbtmp+3
	lda	bshv
	sec
	sbc	#3
	tax
	lda	#1
	cpx	#0
	beq	bd_ex0
bd_ex:
	asl
	dex
	bne	bd_ex
bd_ex0:
	sec
	sbc	#1
	ldx	dcbcopy+1
	beq	bd_exs
	lsr
bd_exs:
	sta	dpbtmp+4
	lda	dcbcopy
	sta	dpbtmp+5
	lda	dcbcopy+1
	sta	dpbtmp+6
	lda	dcbcopy+7
	sta	dpbtmp+7
	lda	dcbcopy+8
	sta	dpbtmp+8
	lda	dcbcopy+4
	sta	dpbtmp+13
	lda	dcbcopy+5
	sta	dpbtmp+14
	lda	dcbcopy+7
	clc
	adc	#1
	sta	dlo
	lda	dcbcopy+8
	adc	#0
	sta	dhi
	ldx	#5
bd_sh:
	asl	dlo
	rol	dhi
	dex
	bne	bd_sh
	lda	#$80
	sta	blo
	lda	#0
	sta	bhi
	ldx	bshv
	beq	bd_bk
bd_bs:
	asl	blo
	rol	bhi
	dex
	bne	bd_bs
bd_bk:
	lda	#0
	sta	nblocks
bd_sub:
	lda	dlo
	ora	dhi
	beq	bd_al
	sec
	lda	dlo
	sbc	blo
	sta	dlo
	lda	dhi
	sbc	bhi
	sta	dhi
	inc	nblocks
	bcs	bd_sub
bd_al:
	lda	#0
	sta	al0v
	sta	al1v
	lda	#$80
	sta	bith
	lda	#0
	sta	bitl
	ldx	nblocks
	beq	bd_ck
bd_bit:
	lda	al0v
	ora	bith
	sta	al0v
	lda	al1v
	ora	bitl
	sta	al1v
	lsr	bith
	ror	bitl
	dex
	bne	bd_bit
bd_ck:
	lda	al0v
	sta	dpbtmp+9
	lda	al1v
	sta	dpbtmp+10
	lda	dcbcopy+11
	bne	bd_cks0
	lda	dcbcopy+7
	clc
	adc	#1
	sta	dlo
	lda	dcbcopy+8
	adc	#0
	sta	dhi
	lsr	dhi
	ror	dlo
	lsr	dhi
	ror	dlo
	lda	dlo
	sta	dpbtmp+11
	lda	dhi
	sta	dpbtmp+12
	rts
bd_cks0:
	lda	#0
	sta	dpbtmp+11
	sta	dpbtmp+12
	rts

; ----- DMAgic -------------------------------------------------------------
dma_between:
	lda	ptrhi
	cmp	#$e0
	bcs	dma_at
	lda	ptrlo
	sta	phys
	lda	ptrhi
	clc
	adc	#$20
	sta	phys1
	lda	#0
	sta	dmalist
	lda	cntlo
	sta	dmalist+1
	lda	cnthi
	sta	dmalist+2
	lda	dir
	bne	dma_f80
	lda	destl
	sta	dmalist+3
	lda	desth
	sta	dmalist+4
	lda	#5
	sta	dmalist+5
	lda	phys
	sta	dmalist+6
	lda	phys1
	sta	dmalist+7
	lda	#4
	sta	dmalist+8
	jmp	dma_end
dma_f80:
	lda	phys
	sta	dmalist+3
	lda	phys1
	sta	dmalist+4
	lda	#4
	sta	dmalist+5
	lda	destl
	sta	dmalist+6
	lda	desth
	sta	dmalist+7
	lda	#5
	sta	dmalist+8
dma_end:
	lda	#0
	sta	dmalist+9
	sta	dmalist+10
	sta	dmalist+11
	jmp	fire700
dma_at:
	lda	ptrlo
	sta	phys
	lda	ptrhi
	sec
	sbc	#$e0
	sta	phys1
	lda	dir
	bne	at_s
	lda	#$81
	bne	at_o
at_s:
	lda	#$80
at_o:
	sta	dmalist
	lda	#$80	; megabyte number: bits 20-27 of Attic address $8000000
	sta	dmalist+1
	lda	#0
	sta	dmalist+2
	sta	dmalist+3
	lda	cntlo
	sta	dmalist+4
	lda	cnthi
	sta	dmalist+5
	lda	dir
	bne	at_f80
	lda	destl
	sta	dmalist+6
	lda	desth
	sta	dmalist+7
	lda	#5
	sta	dmalist+8
	lda	phys
	sta	dmalist+9
	lda	phys1
	sta	dmalist+10
	lda	#0
	sta	dmalist+11
	jmp	at_end
at_f80:
	lda	phys
	sta	dmalist+6
	lda	phys1
	sta	dmalist+7
	lda	#0
	sta	dmalist+8
	lda	destl
	sta	dmalist+9
	lda	desth
	sta	dmalist+10
	lda	#5
	sta	dmalist+11
at_end:
	lda	#0
	sta	dmalist+12
	sta	dmalist+13
	jmp	fire705

dma_clear_window:
	lda	#3
	sta	dmalist
	lda	#0
	sta	dmalist+1
	lda	#$e0
	sta	dmalist+2
	lda	#0
	sta	dmalist+3
	sta	dmalist+4
	sta	dmalist+5
	sta	dmalist+6
	lda	#$20
	sta	dmalist+7
	lda	#4
	sta	dmalist+8
	lda	#0
	sta	dmalist+9
	sta	dmalist+10
	sta	dmalist+11
	jmp	fire700

dma_fill_attic:
	lda	#$81
	sta	dmalist
	lda	#$80	; megabyte number: bits 20-27 of Attic address $8000000
	sta	dmalist+1
	lda	#0
	sta	dmalist+2
	lda	#3
	sta	dmalist+3
	lda	#0
	sta	dmalist+4
	lda	#$20
	sta	dmalist+5
	lda	#$76
	sta	dmalist+6
	lda	#0
	sta	dmalist+7
	sta	dmalist+8
	sta	dmalist+9
	sta	dmalist+10
	sta	dmalist+11
	sta	dmalist+12
	sta	dmalist+13
	jmp	fire705

dma_copy_stub:
	lda	#$81
	sta	dmalist
	lda	#$80	; megabyte number: bits 20-27 of Attic address $8000000
	sta	dmalist+1
	lda	#0
	sta	dmalist+2
	sta	dmalist+3
	lda	#6
	sta	dmalist+4
	lda	#0
	sta	dmalist+5
	lda	#<stubimg
	sta	dmalist+6
	lda	#>stubimg
	sta	dmalist+7
	lda	#5
	sta	dmalist+8
	lda	#0
	sta	dmalist+9
	sta	dmalist+10
	sta	dmalist+11
	sta	dmalist+12
	sta	dmalist+13
	jmp	fire705

dma_copy_bios:
	lda	#$81
	sta	dmalist
	lda	#$80	; megabyte number: bits 20-27 of Attic address $8000000
	sta	dmalist+1
	lda	#0
	sta	dmalist+2
	sta	dmalist+3
	lda	#51
	sta	dmalist+4
	lda	#0
	sta	dmalist+5
	lda	#<biosimg
	sta	dmalist+6
	lda	#>biosimg
	sta	dmalist+7
	lda	#5
	sta	dmalist+8
	lda	#0
	sta	dmalist+9
	lda	#$12
	sta	dmalist+10
	lda	#0
	sta	dmalist+11
	sta	dmalist+12
	sta	dmalist+13
	jmp	fire705

screen_clear:
	lda	#3
	sta	dmalist
	lda	#$80
	sta	dmalist+1
	lda	#$07
	sta	dmalist+2
	lda	#$20
	sta	dmalist+3
	lda	#0
	sta	dmalist+4
	sta	dmalist+5
	sta	dmalist+6
	lda	#scrhi
	sta	dmalist+7
	lda	#4
	sta	dmalist+8
	lda	#0
	sta	dmalist+9
	sta	dmalist+10
	sta	dmalist+11
	jmp	fire700

scroll:
	lda	#0
	sta	dmalist
	lda	#$30
	sta	dmalist+1
	lda	#$07
	sta	dmalist+2
	lda	#80
	sta	dmalist+3
	lda	#scrhi
	sta	dmalist+4
	lda	#4
	sta	dmalist+5
	lda	#0
	sta	dmalist+6
	lda	#scrhi
	sta	dmalist+7
	lda	#4
	sta	dmalist+8
	lda	#0
	sta	dmalist+9
	sta	dmalist+10
	sta	dmalist+11
	jsr	fire700
	lda	#3
	sta	dmalist
	lda	#80
	sta	dmalist+1
	lda	#0
	sta	dmalist+2
	lda	#$20
	sta	dmalist+3
	lda	#0
	sta	dmalist+4
	sta	dmalist+5
	lda	#$30
	sta	dmalist+6
	lda	#$07+scrhi
	sta	dmalist+7
	lda	#4
	sta	dmalist+8
	lda	#0
	sta	dmalist+9
	sta	dmalist+10
	sta	dmalist+11
	jmp	fire700

fire700:
	jsr	map_dma
	lda	#5
	sta	$d702
	lda	#>dmalist
	sta	$d701
	lda	#<dmalist
	sta	$d700
	jmp	map_dos

fire705:
	jsr	map_dma
	lda	#5
	sta	$d702
	lda	#>dmalist
	sta	$d701
	lda	#0
	sta	$d704
	lda	#<dmalist
	sta	$d705
map_dos:
	lda	#0
	ldx	#$f5
	ldy	#0
	ldz	#$f5
	map
	rts

map_dma:
	lda	#0
	ldx	#$d5
	ldy	#0
	ldz	#$b5
	map
	rts

; ----- PEM and messages ---------------------------------------------------
pemcall:
	sta	absa
	sty	absy
	stx	absx
	tba
	sta	absb
	jsr	map_dos
	lda	#0
	tab
	cli
	lda	absa
	ldy	absy
	ldx	absx
	jsr	$0103
	sei
	sta	absa
	sty	absy
	lda	absb
	tab
	ldz	#0
	lda	absa
	ldy	absy
	ldx	absx
	rts

print_stop:
	ldx	#0
ps:
	lda	stopmsg,x
	beq	ps2
	jsr	pemch
	inx
	bne	ps
ps2:
	lda	pchi
	jsr	prhex
	lda	pclo
	jsr	prhex
	lda	#' '
	jsr	pemch
	lda	opcode
	jsr	prhex
	lda	#' '
	jsr	pemch
	lda	func
	jsr	prhex
	lda	#' '
	jsr	pemch
	lda	reason
	jmp	prhex

prhex:
	stx	savex
	sta	abshex
	lsr
	lsr
	lsr
	lsr
	jsr	prnib
	lda	abshex
	and	#$0f
	jsr	prnib
	ldx	savex
	rts
prnib:
	tax
	lda	hextab,x
	jmp	pemch
pemch:
	stx	pstx
	ldx	#2
	ldy	#0
	jsr	pemcall
	ldx	pstx
	rts

; ----- tables and images --------------------------------------------------
regzp:
	.byte	16,16,12,12,8,8
reghi:
	.byte	1,0,1,0,1,0
cmask:
	.byte	$40,$40,$01,$01,$04,$04,$80,$80
cwant:
	.byte	$00,$40,$00,$01,$00,$04,$00,$80
hextab:
	.byte	"0123456789ABCDEF"
stopmsg:
	.byte	"STOP ",0
pageimg:
	.byte	$c3,$03,$e0,$00,$00,$c3,$00,$e0
stubimg:
	.byte	$d3,$00,$c9,$d3,$01,$c9
biosimg:
	.byte	$d3,$02,$c9,$d3,$03,$c9,$d3,$04,$c9,$d3,$05,$c9
	.byte	$d3,$06,$c9,$d3,$07,$c9,$d3,$08,$c9,$d3,$09,$c9
	.byte	$d3,$0a,$c9,$d3,$0b,$c9,$d3,$0c,$c9,$d3,$0d,$c9
	.byte	$d3,$0e,$c9,$d3,$0f,$c9,$d3,$10,$c9,$d3,$11,$c9
	.byte	$d3,$12,$c9
fntab:
	.word	warm_exit,fn1,fn2,fn3,fn4,fn5,fn6,fn7
	.word	fn8,fn9,fn10,fn11,fn12,fn13,fn14,fn15
	.word	fn16,fn17,fn18,fn19,fn20,fn21,fn22,fn23
	.word	fn24,fn25,fn26,fn27,fn28,fn29,stop_fn,fn31
	.word	fn32,fn33,fn34,fn35,fn36,fn37,stop_fn,stop_fn
	.word	fn34

runmode	.byte	0
srow	.byte	0
scol	.byte	0
admst	.byte	0
admsrow	.byte	0
glyph	.byte	0
savedn	.byte	0
linlo	.byte	0
linhi	.byte	0
absa	.byte	0
absy	.byte	0
absx	.byte	0
absb	.byte	0
abshex	.byte	0
pstx	.byte	0
savex	.byte	0
bshv	.byte	0
nblocks	.byte	0
al0v	.byte	0
al1v	.byte	0
dlo	.byte	0
dhi	.byte	0
blo	.byte	0
bhi	.byte	0
bitl	.byte	0
bith	.byte	0
recbuf	.FILL	128 (0)
fcb65	.FILL	36 (0)
fcbt	.FILL	36 (0)
linbuf	.FILL	256 (0)
tailtmp	.FILL	128 (0)
wordbuf	.FILL	16 (0)
dmalist	.FILL	16 (0)
dcbcopy	.FILL	14 (0)
dpbtmp	.FILL	16 (0)

	.INCLUDE "handlers.asm"
image_end
	.STORE $200,image_end-$200,"RUN8080.COM"
