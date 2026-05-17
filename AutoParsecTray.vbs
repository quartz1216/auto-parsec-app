Option Explicit

Dim shell
Dim fileSystem
Dim scriptDirectory
Dim powershellPath
Dim trayScriptPath
Dim command

Set shell = CreateObject("WScript.Shell")
Set fileSystem = CreateObject("Scripting.FileSystemObject")

scriptDirectory = fileSystem.GetParentFolderName(WScript.ScriptFullName)
powershellPath = shell.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"
trayScriptPath = scriptDirectory & "\AutoParsecTray.ps1"

command = """" & powershellPath & """ -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File """ & trayScriptPath & """"
shell.Run command, 0, False
