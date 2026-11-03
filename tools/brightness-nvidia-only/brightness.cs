using System;
using System.IO;
using System.Runtime.InteropServices;

// Software brightness for laptops whose MUX is set to "NVIDIA GPU only".
//
// In that mode Windows exposes NO brightness interface at all: the ACPI
// backlight path lives on the integrated GPU, and the panel is not on it any
// more. The Fn brightness keys and the Settings slider have nothing to talk to.
//
// This tool dims the panel by writing a gamma ramp to the display driver. It is
// not the backlight, but it is the only control available in that mode.
//
// Usage:
//   brightness.exe up        +10%
//   brightness.exe down      -10%
//   brightness.exe set 40    set to 40%
//   brightness.exe apply     re-apply the saved level (used at logon)
//   brightness.exe show      print the saved level

class Program
{
    [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr hWnd);
    [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);
    [DllImport("gdi32.dll")] static extern bool SetDeviceGammaRamp(IntPtr hdc, ushort[] ramp);

    const int MinLevel = 15;
    const int MaxLevel = 100;
    const int Step = 10;

    // State must live somewhere the normal user can write. ProgramData is owned
    // by admin after an elevated install, so use LocalAppData instead.
    static string StateDir { get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "MuxSwitchFix"); } }
    static string StateFile { get { return Path.Combine(StateDir, "brightness.txt"); } }

    static int Load()
    {
        try
        {
            if (File.Exists(StateFile))
            {
                int v;
                if (int.TryParse(File.ReadAllText(StateFile).Trim(), out v))
                {
                    if (v < MinLevel) v = MinLevel;
                    if (v > MaxLevel) v = MaxLevel;
                    return v;
                }
            }
        }
        catch { }
        return 100;
    }

    static void Save(int level)
    {
        try
        {
            if (!Directory.Exists(StateDir)) Directory.CreateDirectory(StateDir);
            File.WriteAllText(StateFile, level.ToString());
        }
        catch { }
    }

    static bool Apply(int level)
    {
        // A linearly scaled ramp (white pulled down) is REJECTED by this driver -
        // verified: SetDeviceGammaRamp returns false unless the top of the ramp
        // stays at 65535. So dim with a gamma curve instead: white is preserved,
        // mid-tones come down, which is what the eye reads as "dimmer".
        double gamma = 1.0 + ((100 - level) / 100.0) * 3.0;

        ushort[] ramp = new ushort[768];
        for (int i = 0; i < 256; i++)
        {
            double v = Math.Pow(i / 255.0, gamma);
            if (v > 1.0) v = 1.0;
            ushort x = (ushort)Math.Round(v * 65535.0);
            ramp[i] = x;
            ramp[256 + i] = x;
            ramp[512 + i] = x;
        }
        ramp[255] = 65535;
        ramp[256 + 255] = 65535;
        ramp[512 + 255] = 65535;

        IntPtr dc = GetDC(IntPtr.Zero);
        bool ok = false;
        try { ok = SetDeviceGammaRamp(dc, ramp); }
        finally { ReleaseDC(IntPtr.Zero, dc); }
        return ok;
    }

    static int Main(string[] args)
    {
        string cmd = args.Length > 0 ? args[0].ToLowerInvariant() : "apply";
        int level = Load();

        switch (cmd)
        {
            case "up":   level += Step; break;
            case "down": level -= Step; break;
            case "set":
                if (args.Length > 1)
                {
                    int v;
                    if (int.TryParse(args[1], out v)) level = v;
                }
                break;
            case "show":
                Console.WriteLine(level);
                return 0;
            case "apply":
            case "restore":
                break;
            default:
                Console.WriteLine("usage: brightness.exe up | down | set <15-100> | apply | show");
                return 1;
        }

        if (level < MinLevel) level = MinLevel;
        if (level > MaxLevel) level = MaxLevel;

        Save(level);
        bool ok = Apply(level);

        Console.WriteLine("brightness {0}%  ({1})", level, ok ? "applied" : "FAILED");
        return ok ? 0 : 2;
    }
}
