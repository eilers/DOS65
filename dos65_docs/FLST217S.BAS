rem	basic-e/65 file status routine for dos/65
rem	Version 2.17
rem	Yes, I know it is slow but it sure is easier to write
rem	released:
rem		13 August 1981 (V1.0)
rem	last revision:
rem		5 October 1981 (v1.2)
rem			mod for Version 1.2
rem		17 October 1982 (v2.0)
rem			mod for Version 2.0
rem		28 december 1985 (v2.01)
rem			eliminated redo path
rem		22 may 1996 (v2.14)
rem			modified for DOS/65 2.14
rem			corrected major logic errors
rem		4 april 2008 (v2.15)
rem			modified for c64 screen
rem		6 april 2008 (v2.16)
rem			modified to handle empty dir
rem		8 april 2008 (v2.17)
rem			added opening banner
rem			added remark about setting tea

rem	constant definitions
rem	tea must be set to correct address for system
	tea=512
rem	following five lines calculate and save special
rem	i/o linksin RUN.COM
	pem=tea+9
	sim=tea+12
	a.reg=tea+15
	y.reg=tea+16
	x.reg=tea+17
rem	these two parameters are the same for all versions
	dfl.buf=296
	e5=229

rem	set up block size array
	dim blk.size$(5)
	blk.size$(0)="1KB "
	blk.size$(1)="2KB "
	blk.size$(2)="4KB "
	blk.size$(3)="8KB "
	blk.size$(4)="16KB "

rem	set up extent mask table
	dim exm(5)
	exm(0)=0
	exm(1)=1
	exm(2)=3
	exm(3)=7
	exm(4)=15

	print "DOS/65 File Status - V2.17-S"
	a=dfl.buf
	gosub 9030		rem set buffer to default
	poke x.reg,25		rem get default
	dfl.drv=call(pem) and 255
	input "What drive";a$
	gosub 9060		rem convert to uppercase
	if (a$<"A") or (a$>"H") \
	  then \
	    print "Illegal drive": \
	    stop
	a=asc(a$)-65
	poke x.reg,13		rem reset system
	dummy=call(pem)
	gosub 9000		rem set drive to a
	track=peek(dcb.addr+4)+peek(dcb.addr+5)*256	rem find number \
						    system tracks
	sector=0
	n=0
	max.dir=peek(dcb.addr+7)+peek(dcb.addr+8)*256	rem find dir \
							    length
	num.dir=max.dir+1
	dim name.ext$(num.dir),extent(num.dir),records(num.dir)
	blk.code=peek(dcb.addr+6)
	exm.index=blk.code
	if peek(dcb.addr+1) <> 0 then exm.index=exm.index-1
	num.sec=peek(dcb.addr+2)+peek(dcb.addr+3)*256
rem	first read directory into arrays
	for i=0 to int(max.dir/4)
	  gosub 9010		rem set track
	  high=int(sector/256)
	  poke a.reg,sector-high*256
	  poke y.reg,high
	  poke x.reg,51
	  dummy=call(sim)	rem translate sector
	  gosub 9020		rem then set it
	  gosub 9040		rem read sector
	  for j=0 to 3
	    dir.start=dfl.buf+(j*32)
	    if peek(dir.start)<>e5 \
	      then \
		n=n+1: \
		gosub 8000	rem build array entry
	  next j
	  sector=sector+1
	  if sector=num.sec then \
	    sector=0 : \
	    track=track+1
	next i

	print "There are ";n;"entries in the directory"
	n.files=n
rem	if directory empty then make sure first name is null
	if n=0 \
	  then name.ext$(1)=""
rem	if only zero or one entry then skip combining
	if n<=1 \
	  then goto 3000
rem	combine entries
	for i=1 to n-1
	  if name.ext$(i)="" \
	    then goto 2000
	  for j=i+1 to n
	    if name.ext$(i)=name.ext$(j) \
	      then \
		name.ext$(j)="": \
		n.files=n.files-1: \
		extent(i)=extent(i)+extent(j): \
		records(i)=records(i)+records(j)
	  next j
2000	next i

3000	print "consisting of ";n.files;"files"
	print
	heading$="NAME         EX RECORDS"
	print heading$
	print
	for i=1 to n
	  name$=name.ext$(i)
	  if name$<>"" \
	    then \
	      print tab(1);name$;tab(14);extent(i);tab(17);\
		records(i)
	next i
	print
	poke x.reg,27
	map.addr=call(pem)	rem allocation map address
	total=0
	num.alloc.byt=int((peek(dcb.addr)+peek(dcb.addr+1)*256)/8)
	for i=0 to num.alloc.byt
	  byte=peek(map.addr+i)
	  for j=1 to 8
	    byte=byte*2
	    if byte>255 \
	      then \
		total=total+1: \
		byte=byte-256
	  next j
	next i
	print total;blk.size$(blk.code);"blocks allocated of ";
	num.blocks=peek(dcb.addr)+peek(dcb.addr+1)*256
	print num.blocks+1
	gosub 9050		rem restore default
	stop

rem	subroutines

8000	rem extract directory entry and stuff in array
	name$=""
	for k=1 to 8
	  char$=chr$(peek(dir.start+k))
	  if char$<>" " \
	    then name$=name$+char$
	next k
	name$=name$+"."
	for k=9 to 11
	  char$=chr$(peek(dir.start+k))
	  if char$<>" " \
	    then name$=name$+char$
	next k
	name.ext$(n)=name$
	extents=(peek(dir.start+12) and exm(exm.index)) + 1
	extent(n)=extents
	records(n)=0
	for l=1 to extents
	  if l < extents \
	    then records(n)=records(n)+128
	  if l = extents \
	    then records(n)=records(n)+peek(dir.start+15)
	next l
	return

9000	rem set drive to value in a
	poke a.reg,a
	poke x.reg,14
	dummy=call(pem)
	poke x.reg,34
	dcb.addr=call(pem)
	return

9010	rem set track to value in track
	high=int(track/256)
	poke a.reg,track-high*256
	poke x.reg,30
	poke y.reg,high
	dummy=call(sim)
	return

9020	rem set sector to value in registers
	poke x.reg,33
	dummy=call(sim)
	return

9030	rem set buffer to value in a
	high=int(a/256)
	if high>255 \
	  then \
	    print "Illegal buffer address": \
	    gosub 9050: \
	    stop
	poke y.reg,high
	poke a.reg,a-high*256
	poke x.reg,36
	dummy=call(sim)
	return

9040	rem read sector into buffer
	poke x.reg,39
	if call(sim) and 255 \
	  then \
	    print "Directory read error!": \
	    gosub 9050: \
	    stop
	return

9050	rem restore default drive
	a=dfl.drv
	gosub 9000
	return

9060	rem get left digit and make uppercase
	a$=left$(a$,1)
	if (a$>="a") and (a$<="z") \
	  then a$=chr$(asc(a$)-32)
	return

end
