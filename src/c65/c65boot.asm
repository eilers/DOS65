;C64BOOT
;128 byte record that is loaded by C64LOAD to pass addresses and
;record count for DOS/65 CCM, PEM, & SIM
;Version 2.11
;released	27 March 2008
;last revision:
;	6 april 2008
;		increased to 52K
;C64LOAD does not know anything about load address or
;amount to load except as provided by this record
;
;data that is used to derive other information
;CCM & PEM length are fixed for DOS/65 2.1
CCMLNG	=	2048	;length of CCM in bytes
PEMLNG	=	3072	;length of PEM in bytes
;memory size assumes kernel rom & IO space are not used
MEMSIZ	=	53248	;last useable RAM+1
;SIM length depends on code included and will
;change as features are added or changed
;for C64 maximum SIM length is 3456 bytes given
;capacity of first two tracks on 1541 diskette
;Initial release is 10 pages long.
SIMLNG	=	2560	;length of SIM in bytes
;following fields contain the data needed by C64LOAD to load DOS/65
;start address for CCM
START	.word	MEMSIZ-CCMLNG-PEMLNG-SIMLNG
;number of 128 byte records to load
LENGTH	.byte	CCMLNG+PEMLNG+SIMLNG/128
;cold boot entry point
CBOOT	.word	MEMSIZ-SIMLNG
;rest of 128 byte record is ignored
	.end
	
