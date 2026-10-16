; Procedural World - Windows installer (NSIS 3, Modern UI 2)
; Build:  makensis -DVERSION=0.3.6 -DSRC_DIR=..\..\build\windows -DOUT_FILE=..\..\build\ProceduralWorld-Setup.exe installer.nsi

Unicode true
SetCompressor /SOLID lzma
ManifestDPIAware true
RequestExecutionLevel admin

!include "MUI2.nsh"
!include "x64.nsh"
!include "FileFunc.nsh"
!include "LogicLib.nsh"
!include "nsDialogs.nsh"

!ifndef VERSION
  !define VERSION "0.3.6"
!endif
!ifndef SRC_DIR
  !define SRC_DIR "..\..\build\windows"
!endif
!ifndef OUT_FILE
  !define OUT_FILE "..\..\build\ProceduralWorld-${VERSION}-Setup.exe"
!endif

!define APP_NAME "Procedural World"
!define APP_EXE "ProceduralWorld.exe"
!define PUBLISHER "Procedural World contributors"
!define HOMEPAGE "https://github.com/kingrebelf/procedural-world"
!define UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\ProceduralWorld"
!define SETTINGS_KEY "Software\ProceduralWorld"

Name "${APP_NAME} ${VERSION}"
OutFile "${OUT_FILE}"
InstallDir "$PROGRAMFILES64\${APP_NAME}"
InstallDirRegKey HKLM "${SETTINGS_KEY}" "InstallDir"
BrandingText "${APP_NAME} ${VERSION}"

VIProductVersion "${VERSION}.0"
VIAddVersionKey "ProductName" "${APP_NAME}"
VIAddVersionKey "CompanyName" "${PUBLISHER}"
VIAddVersionKey "FileDescription" "${APP_NAME} installer"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "LegalCopyright" "MIT License"

; --- Interface --------------------------------------------------------------
!define MUI_ICON "icon.ico"
!define MUI_UNICON "icon.ico"
!define MUI_ABORTWARNING
!define MUI_HEADERIMAGE
!define MUI_HEADERIMAGE_BITMAP "header.bmp"
!define MUI_WELCOMEFINISHPAGE_BITMAP "wizard.bmp"
!define MUI_UNWELCOMEFINISHPAGE_BITMAP "wizard.bmp"
!define MUI_COMPONENTSPAGE_SMALLDESC
!define MUI_WELCOMEPAGE_TITLE "Welcome to ${APP_NAME}"
!define MUI_WELCOMEPAGE_TEXT "An infinite first-person world that blends medieval, fantasy and sci-fi lands as you walk. Everything you discover, mine, craft or carry is saved forever.$\r$\n$\r$\nRecommended: NVIDIA RTX 3070 or better, 8-core CPU, 32 GB RAM, Windows 10/11 64-bit, an SSD.$\r$\n$\r$\nClick Next to continue."
!define MUI_FINISHPAGE_RUN "$INSTDIR\${APP_EXE}"
!define MUI_FINISHPAGE_RUN_TEXT "Launch ${APP_NAME}"
!define MUI_FINISHPAGE_LINK "Project page and source code"
!define MUI_FINISHPAGE_LINK_LOCATION "${HOMEPAGE}"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "..\..\LICENSE"
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_WELCOME
!insertmacro MUI_UNPAGE_CONFIRM
UninstPage custom un.KeepSavesPage un.KeepSavesLeave
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH

!insertmacro MUI_LANGUAGE "English"

; --- Sections ---------------------------------------------------------------
Section "!Game files (required)" SecCore
  SectionIn RO
  SetOutPath "$INSTDIR"
  File "${SRC_DIR}\${APP_EXE}"
  File /nonfatal "${SRC_DIR}\*.dll"
  File "icon.ico"
  File "..\..\LICENSE"
  File /oname=README.txt "..\..\README.md"

  WriteUninstaller "$INSTDIR\Uninstall.exe"
  WriteRegStr HKLM "${SETTINGS_KEY}" "InstallDir" "$INSTDIR"
  WriteRegStr HKLM "${SETTINGS_KEY}" "Version" "${VERSION}"

  ; Apps & Features entry.
  WriteRegStr HKLM "${UNINST_KEY}" "DisplayName" "${APP_NAME}"
  WriteRegStr HKLM "${UNINST_KEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKLM "${UNINST_KEY}" "Publisher" "${PUBLISHER}"
  WriteRegStr HKLM "${UNINST_KEY}" "URLInfoAbout" "${HOMEPAGE}"
  WriteRegStr HKLM "${UNINST_KEY}" "DisplayIcon" "$INSTDIR\icon.ico"
  WriteRegStr HKLM "${UNINST_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "${UNINST_KEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKLM "${UNINST_KEY}" "QuietUninstallString" '"$INSTDIR\Uninstall.exe" /S'
  WriteRegDWORD HKLM "${UNINST_KEY}" "NoModify" 1
  WriteRegDWORD HKLM "${UNINST_KEY}" "NoRepair" 1
  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  IntFmt $0 "0x%08X" $0
  WriteRegDWORD HKLM "${UNINST_KEY}" "EstimatedSize" "$0"
SectionEnd

Section "Start Menu shortcuts" SecStart
  SetShellVarContext all
  CreateDirectory "$SMPROGRAMS\${APP_NAME}"
  CreateShortcut "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}" "" "$INSTDIR\icon.ico"
  CreateShortcut "$SMPROGRAMS\${APP_NAME}\Saved worlds.lnk" "$APPDATA\ProceduralWorld"
  CreateShortcut "$SMPROGRAMS\${APP_NAME}\Uninstall ${APP_NAME}.lnk" "$INSTDIR\Uninstall.exe"
SectionEnd

Section "Desktop shortcut" SecDesktop
  SetShellVarContext all
  CreateShortcut "$DESKTOP\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}" "" "$INSTDIR\icon.ico"
SectionEnd

Section /o "Launch in windowed mode by default" SecWindowed
  ; Writes a starter settings file only if the player has none yet.
  SetShellVarContext current
  IfFileExists "$APPDATA\ProceduralWorld\settings.cfg" done
  CreateDirectory "$APPDATA\ProceduralWorld"
  FileOpen $0 "$APPDATA\ProceduralWorld\settings.cfg" w
  FileWrite $0 "[settings]$\r$\n$\r$\nwindow_mode=0$\r$\nresolution=$\"1920x1080$\"$\r$\n"
  FileClose $0
  done:
SectionEnd

!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
  !insertmacro MUI_DESCRIPTION_TEXT ${SecCore} "The game itself."
  !insertmacro MUI_DESCRIPTION_TEXT ${SecStart} "Start Menu entries for the game, your saved worlds folder and the uninstaller."
  !insertmacro MUI_DESCRIPTION_TEXT ${SecDesktop} "A shortcut on the desktop."
  !insertmacro MUI_DESCRIPTION_TEXT ${SecWindowed} "Start in a 1920x1080 window instead of fullscreen. You can change this any time in Settings."
!insertmacro MUI_FUNCTION_DESCRIPTION_END

Function .onInit
  ${IfNot} ${RunningX64}
    MessageBox MB_ICONSTOP "${APP_NAME} requires 64-bit Windows 10 or 11."
    Abort
  ${EndIf}
  SetRegView 64
  ; Offer to remove an older install first.
  ReadRegStr $0 HKLM "${UNINST_KEY}" "UninstallString"
  ${If} $0 != ""
    MessageBox MB_OKCANCEL|MB_ICONINFORMATION "${APP_NAME} is already installed. It will be updated in place; your saved worlds are kept." IDOK +2
    Abort
  ${EndIf}
FunctionEnd

; --- Uninstaller ------------------------------------------------------------
Var DeleteSaves
Var DeleteSavesCheck

Function un.onInit
  SetRegView 64
  StrCpy $DeleteSaves 0
FunctionEnd

Function un.KeepSavesPage
  !insertmacro MUI_HEADER_TEXT "Saved worlds" "Choose whether to keep your worlds."
  nsDialogs::Create 1018
  Pop $0
  ${NSD_CreateLabel} 0 0 100% 36u "Your worlds, inventory and settings live in %APPDATA%\ProceduralWorld. They are kept by default so a reinstall picks up exactly where you left off."
  Pop $0
  ${NSD_CreateCheckbox} 0 44u 100% 12u "Also delete all saved worlds and settings (cannot be undone)"
  Pop $DeleteSavesCheck
  nsDialogs::Show
FunctionEnd

Function un.KeepSavesLeave
  ${NSD_GetState} $DeleteSavesCheck $DeleteSaves
FunctionEnd

Section "Uninstall"
  SetShellVarContext all
  Delete "$INSTDIR\${APP_EXE}"
  Delete "$INSTDIR\*.dll"
  Delete "$INSTDIR\icon.ico"
  Delete "$INSTDIR\LICENSE"
  Delete "$INSTDIR\README.txt"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
  Delete "$DESKTOP\${APP_NAME}.lnk"
  Delete "$SMPROGRAMS\${APP_NAME}\*.lnk"
  RMDir "$SMPROGRAMS\${APP_NAME}"
  DeleteRegKey HKLM "${UNINST_KEY}"
  DeleteRegKey HKLM "${SETTINGS_KEY}"
  ${If} $DeleteSaves == ${BST_CHECKED}
    SetShellVarContext current
    RMDir /r "$APPDATA\ProceduralWorld"
  ${EndIf}
SectionEnd
