# DOS/65
This is DOS/65, a CP/M clone by Richard A. Leary for the 6502 CPU.

# Concept
DOS/65 is structured in a modular way. The module that provides the direct human machine interface is called the Console Command Module (CCM). It is the module that accepts user commands, loads programs, execute programs, and in version 3 processes batch commands. The module that is the core of the system is the Primitive Execution Module (PEM). It is this module that manages the disk system, handles console input and output, and provides for other core functions in the system. These first two modules are the same for a given TEA except for a single byte in CCM that can be used to change the directory display width.

The module that must be customized for a given users configuration is the System Interface Module (SIM). This module is also sometimes coupled with ROM resident firmware on some systems called the MONITOR but as far as the rest of the system is concerned the interfaces are all in the hands of SIM.

DOS/65 V3.0 is backward-compatible with V2.1. Said another way, V3.0 will execute the V2.1 transients exactly the same as they would be executed under V2.1. The two known exceptions to this rule are the BASIC-E file status program that will not execute correctly under V3.0 and the SD program that must be configured for either V3.0 or V2.1 before it is assembled.

As a consequence the V3.0 releases do not repeat all of the various transients that are released as part of the 2.1. Those transients can all be loaded into a V3.0 system and will run as expected.

One approach to bringing up a new system under V3.0 is to actually bring it up as a V2.1 system and then run SYSGEN for V3.0 on top of V2.1.
