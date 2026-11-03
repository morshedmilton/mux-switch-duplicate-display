# 🔅 Brightness for "NVIDIA GPU only" mode

> In discrete mode this laptop exposes **no** brightness interface at all.
> The `Fn` keys cannot work. This is the next best thing: a 6 KB tool that dims
> the panel through the display driver's gamma ramp.

---

## The problem in one paragraph

The ACPI backlight (`_BCM` / `_BQC`) on this platform lives on the **integrated GPU's**
device, and the EC that drives the panel's backlight PWM is reached through it. When the
MUX moves the panel to the RTX 4060, Windows loses that handle. `WmiMonitorBrightness`,
`WmiMonitorBrightnessMethods` and even NVIDIA's own `NvWmiBrightness` all report
**zero instances**. There is no target for the key press and no slider to move.

Verified:

```powershell
(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBrightness | Measure-Object).Count
# 0  in NVIDIA-only mode
# 1  in Optimus mode
```

No registry key, driver reinstall or Windows setting changes this. It is how the
firmware and the two drivers are arranged.

---

## What this tool does

It writes a **gamma ramp** to the display driver. White stays white; mid-tones come
down. Your eye reads that as a dimmer screen.

| | Real backlight | This tool |
|---|---|---|
| Panel physically dimmer | ✅ | ❌ |
| Battery saving | ✅ | ❌ |
| Works in NVIDIA-only mode | ❌ | ✅ |
| Works with the `Fn` keys | ❌ (no target) | ❌ (needs a click) |
| Contrast | unchanged | slightly reduced when dimmed |

**It is not a backlight replacement.** It is the only control that exists in this mode.

---

## Install

The build is already on this machine:

```
C:\ProgramData\MuxSwitchFix\brightness.exe     (console, for testing)
C:\ProgramData\MuxSwitchFix\brightnessw.exe    (no console window, for shortcuts)
```

Two desktop shortcuts and one startup entry are created:

| Shortcut | Action |
|---|---|
| `Brightness Down` | −10 % |
| `Brightness Up` | +10 % |
| `Brightness Restore` (Startup folder) | re-applies the saved level at every logon |

Pin both desktop shortcuts to the taskbar for one-click access.

---

## Command line

```cmd
brightness.exe up            +10 %
brightness.exe down          -10 %
brightness.exe set 40        set to 40 %
brightness.exe apply         re-apply the saved level
brightness.exe show          print the saved level
```

Range is clamped to 15 – 100 %. The level is stored in
`%LOCALAPPDATA%\MuxSwitchFix\brightness.txt` so it survives reboots.

---

## Build it yourself

Requires Windows PowerShell 5.1 only — no SDK, no compiler install.

```powershell
Add-Type -Path .\brightness.cs -OutputAssembly .\brightness.exe `
         -OutputType ConsoleApplication -ReferencedAssemblies System.dll

Add-Type -Path .\brightness.cs -OutputAssembly .\brightnessw.exe `
         -OutputType WindowsApplication -ReferencedAssemblies System.dll
```

---

## One thing that does **not** work, and why

The obvious implementation — scale the whole ramp down by the brightness factor — is
**rejected by this driver**:

```csharp
// REJECTED: SetDeviceGammaRamp returns false
v = (i / 255.0) * (level / 100.0);     // white lands at level% of 65535
```

Measured on the RTX 4060 with driver 32.0.16.2101:

```
linear scale 0.45 : FAILED      (SetDeviceGammaRamp returned false)
gamma curve  1.6  : OK  mid-tone=21754  white=65535
gamma curve  2.6  : OK  mid-tone=10920  white=65535
```

The driver accepts a ramp only if the top stays at `65535`. So the tool uses a gamma
curve and forces the last entry to full white. That is why the source sets
`ramp[255] = 65535` explicitly.

---

## Undo

```cmd
brightness.exe set 100
```

Or delete the three shortcuts and the folder. Nothing is installed as a service; no
registry keys are written outside `%LOCALAPPDATA%\MuxSwitchFix`.

---

## Honest recommendation

If you want the `Fn` brightness keys and real backlight control back, the only route is
**Optimus mode**. See [docs/05](../../docs/05-known-limitations.md) for the full
trade-off table.
