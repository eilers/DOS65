REM Test SD interfacw for the SBC2-2.5
REM 08/30/2017

del *.hex
del *.obj
del *.lst

c:\wdc\tools\bin\WDC02AS.exe -g -l -DUSING_02 c:\wdc\w65c02sxb\Test_SBC_sdV124\asm\test_sbc_SDv124.asm
c:\wdc\tools\bin\WDCLN.exe -g -sz -t -Hi c:\wdc\w65c02sxb\Test_SBC_sdV124\asm\Test_sbc_SDV124.obj
pause
 