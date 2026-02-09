@echo off
setlocal enabledelayedexpansion

net session >nul 2>&1
if %errorLevel% neq 0 (
    echo �����Թ���ԱȨ����������...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

set "INSTALL_DIR=C:\EasyTier"
set "EASYTIER_ZIP_URL=https://raw.githubusercontent.com/benben-cc/easytier-install/refs/heads/main/easytier.zip"
set "TEMP_DIR=%TEMP%\EasyTier_Temp"
set "ZIP_FILE=%TEMP_DIR%\easytier.zip"
set "NSSM_EXE=%INSTALL_DIR%\nssm.exe"
set "LOGS_DIR=%INSTALL_DIR%\logs"
set "LOG_FILE=%LOGS_DIR%\easytier_install.log"

set "PROG1_EXE=easytier-core.exe"
set "PROG1_SERVICE=easytier-core.exe"
set "PROG2_EXE=easytier-cli.exe"
set "PROG2_SERVICE=easytier-cli.exe"
set "PROG3_EXE=easytier-web.exe"
set "PROG3_SERVICE=easytier-web.exe"
set "PROG4_EXE=easytier-web-embed.exe"
set "PROG4_SERVICE=easytier-web-embed.exe"

if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
if not exist "%TEMP_DIR%" mkdir "%TEMP_DIR%"
if not exist "%LOGS_DIR%" mkdir "%LOGS_DIR%"

set "EASYTIER_INSTALLED=0"
for %%F in (%PROG1_EXE% %PROG2_EXE% %PROG3_EXE% %PROG4_EXE%) do (
    if exist "%INSTALL_DIR%\%%F" set "EASYTIER_INSTALLED=1"
)

if "%EASYTIER_INSTALLED%"=="0" (
    goto InstallMenu
) else (
    goto MainMenu
)

::================ ��װ�˵� =================
:InstallMenu
cls
echo ===========================================
echo         EasyTier δ��װ --- ���Ǻ�
echo ===========================================
echo ��װĿ¼��%INSTALL_DIR%
echo ===========================================
echo 1. ��װ EasyTier
echo 2. �˳�
echo ===========================================
set /p choice=��ѡ���������ţ���
if "%choice%"=="1" call :DownloadAndExtract
if "%choice%"=="2" exit
goto InstallMenu

::================ ���˵� =================
:MainMenu
cls
echo ===========================================
echo         EasyTier ������� --- ���Ǻ�
echo ===========================================
echo ��װĿ¼��%INSTALL_DIR%
echo ===========================================
echo 1. ��װ ϵͳ����
echo 2. ɾ�� ϵͳ����
echo 3. �� ��־Ŀ¼
echo 4. ж�� EasyTier
echo ===========================================
call :UpdateServiceStatus

set "RUNNING_COUNT=0"
for /l %%i in (1,1,4) do (
    if "!PROG%%i_STATUS!"=="������" (
        echo !PROG%%i_EXE!  ״̬��������
        set /a RUNNING_COUNT+=1
    )
)
if !RUNNING_COUNT! equ 0 echo ��ǰû�������еķ���
echo ===========================================
set /p choice=��ѡ���������ţ���

if "%choice%"=="1" call :StartSubMenu
if "%choice%"=="2" call :StopSubMenu
if "%choice%"=="3" goto OpenLogDir
if "%choice%"=="4" call :UninstallEasyTier
goto MainMenu

::================ �ӳ��� =================
:UpdateServiceStatus
for /l %%i in (1,1,4) do (
    set "SERVICE_NAME=!PROG%%i_SERVICE!"
    sc query "!SERVICE_NAME!" >nul 2>&1
    if errorlevel 1 (
        set "PROG%%i_STATUS=δע��"
    ) else (
        for /f "tokens=3 delims=: " %%S in ('sc query "!SERVICE_NAME!" ^| findstr "STATE"') do (
            if "%%S"=="RUNNING" (
                set "PROG%%i_STATUS=������"
            ) else (
                set "PROG%%i_STATUS=��ע��"
            )
        )
    )
)
goto :eof

:DownloadAndExtract
echo �������� EasyTier ZIP �ļ�...
powershell -Command "Invoke-WebRequest -Uri '%EASYTIER_ZIP_URL%' -OutFile '%ZIP_FILE%'" >>"%LOG_FILE%" 2>&1
if not exist "%ZIP_FILE%" (
    echo ����ʧ�ܣ���������� URL
    pause
    goto InstallMenu
)
echo ���ڽ�ѹ�� %INSTALL_DIR% ...
powershell -Command "Expand-Archive -Path '%ZIP_FILE%' -DestinationPath '%INSTALL_DIR%' -Force" >>"%LOG_FILE%" 2>&1
echo EasyTier ��װ��ɣ���ϸ��־��д�� %LOG_FILE%
pause
goto MainMenu

:StartSubMenu
cls
echo ========== ��װϵͳ���� ==========
set "START_COUNT=0"
for /l %%i in (1,1,4) do (
    if "!PROG%%i_STATUS!"=="δע��" (
        set /a START_COUNT+=1
        set "START_OPTION[!START_COUNT!]=PROG%%i"
        echo !START_COUNT!. !PROG%%i_EXE!
    )
)
if !START_COUNT! equ 0 (
    echo ����δע�����ɰ�װ
    pause
    goto MainMenu
)
set /a BACK_OPT=START_COUNT+1
echo !BACK_OPT!. �������˵�
echo.
set /p sub_choice=��ѡ�����
if "%sub_choice%"=="!BACK_OPT!" goto MainMenu
for /l %%i in (1,1,!START_COUNT!) do (
    if "%sub_choice%"=="%%i" (
        set "TARGET_PROG=!START_OPTION[%%i]!"
        call :InstallService !TARGET_PROG!
    )
)
goto StartSubMenu

:InstallService
set "PROG_PREFIX=%~1"
set "TARGET_EXE=!%PROG_PREFIX%_EXE!"
set "TARGET_SERVICE=!%PROG_PREFIX%_SERVICE!"
set "TARGET_EXE_PATH=%INSTALL_DIR%\%TARGET_EXE%"

if not exist "%TARGET_EXE_PATH%" echo ����%TARGET_EXE%������ & pause & goto MainMenu
if not exist "%NSSM_EXE%" echo ����NSSM������ & pause & goto MainMenu

set /p EXEC_PARAMS=�������������������գ���
for /f "tokens=* delims= " %%A in ("!EXEC_PARAMS!") do set "EXEC_PARAMS=%%A"

"%NSSM_EXE%" install "%TARGET_SERVICE%" "%TARGET_EXE_PATH%" >>"%LOG_FILE%" 2>&1

:: �����û��������ʱ�Ŵ��� AppParameters
if not "!EXEC_PARAMS!"=="" (
    "%NSSM_EXE%" set "%TARGET_SERVICE%" AppParameters "!EXEC_PARAMS!" >>"%LOG_FILE%" 2>&1
)

"%NSSM_EXE%" set "%TARGET_SERVICE%" AppDirectory "%INSTALL_DIR%" >>"%LOG_FILE%" 2>&1
"%NSSM_EXE%" set "%TARGET_SERVICE%" AppStdout "%LOGS_DIR%\%TARGET_EXE%.log" >>"%LOG_FILE%" 2>&1
"%NSSM_EXE%" set "%TARGET_SERVICE%" AppStderr "%LOGS_DIR%\%TARGET_EXE%-err.log" >>"%LOG_FILE%" 2>&1

sc start "%TARGET_SERVICE%" >>"%LOG_FILE%" 2>&1
echo ���� %TARGET_SERVICE% ��װ��������ɣ���ϸ��־��д�� %LOG_FILE%
pause
call :UpdateServiceStatus
goto MainMenu

:StopSubMenu
cls
echo ========== ɾ��ϵͳ���� ==========
set "STOP_COUNT=0"
for /l %%i in (1,1,4) do (
    if not "!PROG%%i_STATUS!"=="δע��" (
        set /a STOP_COUNT+=1
        set "STOP_OPTION[!STOP_COUNT!]=PROG%%i"
        echo !STOP_COUNT!. !PROG%%i_EXE!
    )
)
if !STOP_COUNT! equ 0 (
    echo ������ע������ɾ��
    pause
    goto MainMenu
)
set /a BACK_OPT=STOP_COUNT+1
echo !BACK_OPT!. �������˵�
echo.
set /p sub_choice=��ѡ�����
if "%sub_choice%"=="!BACK_OPT!" goto MainMenu
for /l %%i in (1,1,!STOP_COUNT!) do (
    if "%sub_choice%"=="%%i" (
        set "TARGET_PROG=!STOP_OPTION[%%i]!"
        call :UninstallService !TARGET_PROG!
    )
)
goto StopSubMenu

:UninstallService
set "PROG_PREFIX=%~1"
set "TARGET_SERVICE=!%PROG_PREFIX%_SERVICE!"

:: ֹͣ��ɾ������
sc stop "%TARGET_SERVICE%" >>"%LOG_FILE%" 2>&1
"%NSSM_EXE%" remove "%TARGET_SERVICE%" confirm >>"%LOG_FILE%" 2>&1

echo ���� %TARGET_SERVICE% ɾ����ɣ���ϸ��־��д�� %LOG_FILE%
pause
call :UpdateServiceStatus
goto MainMenu

:UninstallEasyTier
cls
echo ����ж�� EasyTier��ֹͣ���з���...

for /l %%i in (1,1,4) do (
    set "TARGET_SERVICE=!PROG%%i_SERVICE!"
    echo ����ֹͣ���� !TARGET_SERVICE! ...
    sc stop "!TARGET_SERVICE!" >>"%LOG_FILE%" 2>&1
    "%NSSM_EXE%" remove "!TARGET_SERVICE!" confirm >>"%LOG_FILE%" 2>&1
)

if exist "%NSSM_EXE%" (
    takeown /f "%NSSM_EXE%" >nul 2>&1
    icacls "%NSSM_EXE%" /grant %USERNAME%:F >nul 2>&1
    del /f /q "%NSSM_EXE%" >>"%LOG_FILE%" 2>&1
)

rmdir /s /q "%INSTALL_DIR%"
echo EasyTier ��ж����ɣ�
pause
exit


:OpenLogDir
if exist "%LOGS_DIR%" start "" "%LOGS_DIR%"
goto MainMenu
