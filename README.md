# DOS/65
This is __DOS/65, a CP/M clone__ by Richard A. Leary for the 6502 CPU.

This repository contains the port of DOS/65 for the [Mega65](https://mega65.org). The Mega65 is the modern recreation of the Commodore C65, that was never released. 

You will find details about this port on the [project page](https://wiki.eilers-online.net/dos65).

# License
(c) 1982 - 2017 by Richard A. Leary

"DOS/65 software and documentation are provided as shareware for non-profit, educational, or private use. Any other use is prohibited without approval of Richard A. Leary."

# What is DOS/65?
DOS/65 is a CP/M clone for the 6502 CPU.

"What I (Richard A. Leary) have done is attack the software side of the problem in order to make any 6502 system a truly workable disk based system. In addition a degree of compatibility is now possible not only between 6502 systems but with large parts of the world of CP/M systems. The result of my efforts is a system of software which I have named DOS/65."

## Concept
DOS/65 is structured in a modular way. The module that provides the direct human machine interface is called the Console Command Module (CCM). It is the module that accepts user commands, loads programs, execute programs, and in version 3 processes batch commands. The module that is the core of the system is the Primitive Execution Module (PEM). It is this module that manages the disk system, handles console input and output, and provides for other core functions in the system. These first two modules are the same for a given TEA except for a single byte in CCM that can be used to change the directory display width.

The module that must be customized for a given users configuration is the System Interface Module (SIM). This module is also sometimes coupled with ROM resident firmware on some systems called the MONITOR but as far as the rest of the system is concerned the interfaces are all in the hands of SIM.

## This Distribution
[This Disk](https://files.mega65.org?id=0ce4be40-9fdd-4115-9d61-faf09510b161) includes Version V2.19 which resembles to CP/M 2. Version 3 (which resembles to CP/M 3) needs a port of the SIM, which might be realized in the future.
It was tested with 
* MEGA65 ROM : V920417 and V920420
* MEGA65 CORE: 0.97 aaf4542   

The command control module (CCM) knowns the following commands:
* DIR
* REN \<ufn\> \<ufn\>
* SAVE \<length\> \<drive:\>ufn (\<address\>)
* ERA \<afn\>
* TYPE d:ufn
* LOAD \<ufn\> (\<address\>)
* GO (\<address\>)

This distribution comes as a hybrid D64 image that contains the following software:
* Assembler for 6502: 
    * ASM
* BASIC-E (Naval Postgraduate School Basic) Compiler and Runtime:
    * COMPILE
    * RUN
* Microsoft 9 Digit Basic
    * BASIC (Not working for now. Pull requests are welcome!)
* Editor:
    * EDIT
* Other:
    * MORE
    * SYSSTAT (compile with `COMPILE SYST212S`  and execute with `RUN SYST21S` )
    * FILESTAT (compile with `COMPILE FLST217S` and execute with `RUN FLST217S`)
    * ALLOC
    * COMPARE
    * DISKCOPY
    * DUMP
    * PAGE
* Not yet included (Not working for now. Pull requests are welcome!)
    * DEBUG 

Please note that SysGen is not supported and therefore not included in this package. Please read [here](https://wiki.eilers-online.net/dos65) why this is the case.

# How to build
1. Please checkout this project with `--recurse-submodules` in order to checkout the required tool chain. 
2. Jump into the folder `src/c65` and enter `make distribution`
3. You (hopefully) find the distribution in the folder `/src/c65/disk` like this: `dos65_V<VERSION>.D64`. Please ensure that you do _not_ use the other D64 images that you find in this folder! 

This disk is a hybrid disk that is compatible to the 1541 and can be mounted as that. You will find the other DOS/65 programs after booting.

# How to boot
Mount the D64 and just enter `boot`. That's it.

You might update your core for the Mega65 if the 1541 emulation is missing.

# Documentation
You find the original documenation in the [docs](./docs) folder. 

# Other DOS/65 Repositories
https://github.com/floobydust/DOS-65-Version-3.21/tree/main/DOS65V321

https://github.com/osiweb/DOS65/tree/master/DOS65_v2.1
