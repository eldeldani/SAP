@echo off
setlocal enabledelayedexpansion
SET var1=%1
SET var2=%2 %3 %4
SET RUNBOOK_RESOLVER="empty"
SET /a num=%random% %%10000
SET TMP_FILE=%var1%%num%.txt
sqlcmd.exe -S EVW1901181 -U runbook -P HH,V=s9Hr?$AQ'50 -h-1 -Q "SET NOCOUNT ON; SELECT LINK_RUNBOOK FROM NTTHOST.dbo.RUNBOOKS where RTM_CHECK_NAME='%var1%' AND SAP_SID='%var2%'" -h -1 > %TMP_FILE%
set /P RUNBOOK_RESOLVER=<%TMP_FILE%

IF "!RUNBOOK_RESOLVER!" == ""empty"" (
    sqlcmd.exe -S EVW6000642 -U runbook -P HH,V=s9Hr?$AQ'50 -h-1 -Q "SET NOCOUNT ON; SELECT LINK_RUNBOOK FROM NTTHOST.dbo.RUNBOOKS where RTM_CHECK_NAME='%var1%' AND NULLIF(SAP_SID,'') IS NULL" -h -1 > %TMP_FILE%
    set /p RUNBOOK_RESOLVER=<%TMP_FILE%
	IF "!RUNBOOK_RESOLVER!" == ""empty"" (
		echo RUNBOOK_RESOLVER=https://confluence.nttltd.global.ntt/display/public/OT/ALERT+-+Xandria+Monitoring+General+Runbook
		del %TMP_FILE%
	) ELSE (
	echo RUNBOOK_RESOLVER=!RUNBOOK_RESOLVER!
	del %TMP_FILE%
	)
) ELSE (
	echo RUNBOOK_RESOLVER=!RUNBOOK_RESOLVER!
	del %TMP_FILE%
)