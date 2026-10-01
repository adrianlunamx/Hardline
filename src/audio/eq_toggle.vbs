' Hardline - lanza eq_toggle.ps1 sin ventana.
' Una ventana de consola, aunque sea un instante, puede quitar el foco al juego
' en pantalla completa exclusiva. WScript.Shell.Run con estilo 0 no crea ninguna.
Set fso = CreateObject("Scripting.FileSystemObject")
here = fso.GetParentFolderName(WScript.ScriptFullName)
root = fso.GetParentFolderName(fso.GetParentFolderName(here))
cmd = "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & here & "\eq_toggle.ps1"" -Root """ & root & """"
CreateObject("WScript.Shell").Run cmd, 0, False
