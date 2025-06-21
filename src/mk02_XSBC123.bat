REM DOS/65 XMODEM Interface for the SBC2
REM 07/28/2017

del *.bin
del *.obj
del *.lst

c:\wdc\tools\bin\WDC02AS.exe -g -l -DUSING_02 XSBC123.asm
c:\wdc\tools\bin\WDCLN.exe -g -sz -t -HI XSBC123
pause
