# Adds "Deadlines" to the Start menu, running the app from this folder with .venv's Python.
# Run again after moving the folder:  powershell -ExecutionPolicy Bypass -File make_shortcut.ps1
$Project = $PSScriptRoot
$lnk = Join-Path ([Environment]::GetFolderPath("Programs")) "Deadlines.lnk"

$shell = New-Object -ComObject WScript.Shell
$s = $shell.CreateShortcut($lnk)
$s.TargetPath = Join-Path $Project ".venv\Scripts\pythonw.exe"
$s.Arguments = '"' + (Join-Path $Project "main.py") + '"'
$s.WorkingDirectory = $Project
$s.IconLocation = (Join-Path $Project "icon.ico") + ",0"
$s.Description = "Deadlines: assignments, steps and Canvas deadlines"
$s.Save()

# Give the shortcut the same AppUserModelID the app sets for itself, so the running window
# groups under this shortcut on the taskbar.
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;

public static class Aumid {
    [StructLayout(LayoutKind.Sequential)] struct PropertyKey { public Guid fmtid; public uint pid; }
    [StructLayout(LayoutKind.Explicit, Size = 24)] struct PropVariant { [FieldOffset(0)] public ushort vt; [FieldOffset(8)] public IntPtr p; }

    [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IPropertyStore {
        void GetCount(out uint count);
        void GetAt(uint index, out PropertyKey key);
        void GetValue(ref PropertyKey key, out PropVariant value);
        void SetValue(ref PropertyKey key, ref PropVariant value);
        void Commit();
    }

    public static void Set(string lnkPath, string id) {
        var link = Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("00021401-0000-0000-C000-000000000046")));
        ((IPersistFile)link).Load(lnkPath, 2);
        var key = new PropertyKey { fmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), pid = 5 };
        var value = new PropVariant { vt = 31, p = Marshal.StringToCoTaskMemUni(id) };  // VT_LPWSTR
        try {
            var store = (IPropertyStore)link;
            store.SetValue(ref key, ref value);
            store.Commit();
            ((IPersistFile)link).Save(lnkPath, true);
        } finally {
            Marshal.FreeCoTaskMem(value.p);
            Marshal.ReleaseComObject(link);
        }
    }
}
"@
[Aumid]::Set($lnk, "Deadlines.App")
$lnk

