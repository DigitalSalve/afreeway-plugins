@echo off
rem afreeway headersHelper on Windows. Claude Code runs the helper through a windowless
rem command prompt, not Git Bash, and finds this file through PATHEXT. Opening the sh
rem script directly would use the .sh file association: a visible window, with stdout
rem lost. The bash on PATH can be WSL's. So find Git for Windows' own bash, and run the
rem script with it. Nothing here opens a window. Uses %~dp0: the plugin's environment
rem variables are not set for the helper. With no bash: {} and a reason in the log.
setlocal
set "AF_BASH="

if defined CLAUDE_CODE_GIT_BASH_PATH if exist "%CLAUDE_CODE_GIT_BASH_PATH%" (
  set "AF_BASH=%CLAUDE_CODE_GIT_BASH_PATH%"
  goto found
)

for /f "delims=" %%G in ('where git 2^>nul') do (
  if exist "%%~dpG..\bin\bash.exe" (
    set "AF_BASH=%%~dpG..\bin\bash.exe"
    goto found
  )
)

for /f "tokens=2,*" %%A in ('reg query "HKLM\SOFTWARE\GitForWindows" /v InstallPath 2^>nul ^| "%SystemRoot%\System32\find.exe" "InstallPath"') do (
  if exist "%%B\bin\bash.exe" (
    set "AF_BASH=%%B\bin\bash.exe"
    goto found
  )
)

if exist "%ProgramFiles%\Git\bin\bash.exe" (
  set "AF_BASH=%ProgramFiles%\Git\bin\bash.exe"
  goto found
)

if defined LocalAppData if exist "%LocalAppData%\Programs\Git\bin\bash.exe" (
  set "AF_BASH=%LocalAppData%\Programs\Git\bin\bash.exe"
  goto found
)

set "AF_LOG=%USERPROFILE%\.local\state\afreeway"
if defined XDG_STATE_HOME set "AF_LOG=%XDG_STATE_HOME%\afreeway"
if defined AFREEWAY_STATE_DIR set "AF_LOG=%AFREEWAY_STATE_DIR%"
if not exist "%AF_LOG%" mkdir "%AF_LOG%" >nul 2>&1
>>"%AF_LOG%\plugin.log" echo %DATE% %TIME% headers: no session header: Git for Windows' bash not found: set CLAUDE_CODE_GIT_BASH_PATH
echo {}
exit /b 0

:found
set "AF_SCRIPT=%~dp0headers"
set "AF_SCRIPT=%AF_SCRIPT:\=/%"
rem call: if AF_BASH is a command file, control would otherwise never come back here.
call "%AF_BASH%" --noprofile --norc "%AF_SCRIPT%"
if not "%errorlevel%"=="0" echo {}
exit /b 0
