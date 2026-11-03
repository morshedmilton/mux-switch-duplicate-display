# 📘 Diagnosis — is this your problem?

> Three checks. Takes two minutes. If all three match, you have the bug.

---

## Check 1 — does the panel belong to the dGPU right now?

```powershell
& 'C:\Windows\System32\nvidia-smi.exe' --query-gpu=display_active --format=csv
```

| Output | Meaning |
|---|---|
| `Enabled` | the internal panel is physically driven by the NVIDIA GPU — you are in **discrete mode** |
| `Disabled` | the panel is on the integrated GPU — you are in **Optimus mode** |

The bug appears **after switching into discrete mode**. It can also appear when
switching back, in the other direction.

---

## Check 2 — are there two active monitors for one panel?

```powershell
Get-PnpDevice -Class Monitor | Select-Object Status, FriendlyName, InstanceId
```

Healthy:

```
OK        Integrated Monitor    DISPLAY\AUOAA9F\4&3A9F8B26&8&UID8388688
Unknown   Generic Monitor       DISPLAY\AUOAA9F\1&8713BCA&0&UID0          <- phantom, fine
```

**Two entries with status `OK`** for the same physical panel is the interesting case:

```
OK        Integrated Monitor    DISPLAY\AUOAA9F\4&3A9F8B26&8&UID8388688   <- Intel path
OK        Generic Monitor       DISPLAY\AUOAA9F\5&39808DAE&2&UID4353      <- NVIDIA path
```

What it means depends on the mode you are in:

| Mode | Two `OK` monitors means |
|---|---|
| **Optimus** | something is wrong — one panel should have one path |
| **NVIDIA GPU only** | **normal here, and this is what gives you brightness.** The Intel path supplies the ACPI backlight interface. Removing it removes brightness control. |

`Unknown` means *phantom* — normal and harmless. Only `OK` counts.

---

## Check 3 — is the compositor doing double work?

```powershell
$p1 = (Get-Process dwm).CPU
Start-Sleep -Seconds 10
$p2 = (Get-Process dwm).CPU
"{0}% of one core" -f [math]::Round(($p2 - $p1) / 10 * 100, 1)
```

Leave the mouse alone while it runs.

| Result | Meaning |
|---|---|
| under **3 %** | healthy |
| **5 – 15 %** | suspicious — something is re-compositing |
| **20 – 50 %** | **this bug**. dwm is compositing for two adapters |

For reference: a healthy desktop sits at **0.1 – 1 %**.

---

## Bonus check — the Windows topology database

This is the actual proof. It shows Windows binding one panel to two adapters:

```powershell
Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Connectivity' |
  ForEach-Object {
    $k = Get-ItemProperty $_.PSPath
    [pscustomobject]@{ Key = $_.PSChildName; Internal = $k.Internal; External = $k.External; Recent = $k.Recent }
  } | Format-List
```

Look for a key whose name contains **both** `10DE` (NVIDIA) and `8086` (Intel), with:

```
Internal : ..._8086_A78B_...     <- panel mapped to Intel
External : ..._10DE_28E0_...     <- same panel mapped to NVIDIA
```

That is one panel with two owners. Windows will happily composite for both.

---

## One command instead of four

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\fix-display-after-mux-switch.ps1 -MeasureOnly
```

Or just double-click **`tools\RUN-FIX.cmd`** and read the window it opens.

Exit codes: `0` healthy · `1` duplicate detected · `3` no Intel adapter to toggle.

---

## If the checks do **not** match

Then you have a different problem. Rule these out in order:

| Symptom | Likely cause | Where to look |
|---|---|---|
| Everything stutters, GPU at 95 %+ | GPU-bound | your game/app settings |
| One CPU core pegged, GPU idle | CPU-bound | background process, single-threaded app |
| Typing lags but only in one app | that app's renderer | restart it; disable its hardware acceleration |
| Lag right after wake from sleep | power state | reboot once; check for a driver stuck in a low power state |
| dwm high **and** 2 active monitors | **this bug** | run the fix |

---

**Next:** [evidence →](02-evidence.md)
