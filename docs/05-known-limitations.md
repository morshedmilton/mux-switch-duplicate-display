# 📓 The three-way trade-off (and how to win all three)

> **This page corrects an earlier version of this repo.** It used to claim that
> brightness control is simply *impossible* in "NVIDIA GPU only" mode. That was wrong,
> and the owner of the laptop caught it: brightness **did** work in that mode. Here is
> the measured truth.

Everything below was measured on a Dell G15 5530 — i7-13650HX, RTX 4060 Laptop
(32.0.16.2101), Intel UHD (32.0.101.7088), AUO AA9F 1920×1080 360 Hz, Windows 11 26300.

---

## The short version

In **NVIDIA GPU only** mode you can have any **two** of these three, never all three:

| | Colour grading (NVIDIA) | Brightness 0–100 | Smooth typing |
|---|---|---|---|
| **NVIDIA-only, stale Intel path alive** | ✅ | ✅ | ❌ `dwm` 35–43 % |
| **NVIDIA-only, stale path removed** | ✅ | ❌ | ✅ `dwm` 1–2 % |
| **Optimus + Intel colour** | ✅ (looks the same) | ✅ | ✅ `dwm` 1–2 % |

The only configuration that gives all three is the last one — and the reason people
resist it (colour) turns out to be a single number you can copy across.

---

## Why brightness only works with the stale path

`WmiMonitorBrightness` is the only brightness interface Windows exposes on this machine.
When it exists, its instance name tells you exactly which display path is providing it:

```
DISPLAY\AUOAA9F\4&3a9f8b26&8&UID8388688_0
```

That UID belongs to the monitor device called **Integrated Monitor** — the leftover
Intel path, not the NVIDIA one. So:

| State | active monitors | brightness instances | works? |
|---|---|---|---|
| NVIDIA-only, stale path alive | **2** | **1** | ✅ |
| NVIDIA-only, stale path removed | 1 | **0** | ❌ |
| Optimus | 1 | **1** | ✅ |

The ACPI backlight (`_BCM` / `_BQC`) hangs off the **integrated GPU's** device, and the
EC that physically drives the backlight PWM is reached through it. NVIDIA's own
`NvWmiBrightness` has **zero instances** on this model, so it cannot substitute.

So the "duplicate display" that this repo treats as a bug is, in NVIDIA-only mode, the
**only** source of brightness control.

---

## Why that same path causes the typing lag

With the stale path alive, `Desktop Window Manager` composites every frame for **both**
adapters:

```
PID 2304   dwm   LUID 0x00012f34   avg 28.8 %   <- NVIDIA adapter
PID 2304   dwm   LUID 0x00013329   avg  7.1 %   <- Intel adapter
```

Measured `dwm.exe` CPU on an idle desktop at 360 Hz:

| State | `dwm` CPU (% of one core) |
|---|---|
| stale path alive | **34.9 / 38.5 / 42.7** |
| stale path removed | 1.0 / 1.8 |
| Optimus | 1.0 / 1.8 |

At 360 Hz that is 360 composites per second, twice, plus a cross-adapter copy. That is
the "typed word appears a second later" feeling: the keystroke is handled instantly, the
frame carrying it is not.

---

## The mistake this repo made

The repair script originally triggered on **monitor count alone**:

```powershell
if ($activeMonitors -gt 1) { $broken = $true }   # WRONG in NVIDIA-only mode
```

and a logon watchdog ran it on every boot. The log shows it firing twice in one day
while the desktop was already idle:

```
11-03 02:14:40  active monitors=2
11-03 02:14:56  repairing ...   dwm=0%    monitors 2 -> 1
11-03 10:17:40  active monitors=2
11-03 10:17:56  repairing ...   dwm=2.1%  monitors 2 -> 1
```

`dwm` was already 0 % and 2 % — there was no lag to fix. The script was removing the
brightness path for nothing.

**Fixed in `1712c77`:** the trigger is now `dwm >= 15 %` only. A second monitor device is
reported, never repaired on its own.

---

## The colour problem, solved with one number

The reason people stay in NVIDIA-only mode is usually colour. On this machine that
preference was one registry value:

```
HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-...}\0000
  _User_SUB0_DFP1_VAL_Saturation  = 125     <- +25 %, everything else default
  _User_SUB0_DFP1_VAL_Contrast    = 100     default
  _User_SUB0_DFP1_VAL_Hue         = 0       default
  _User_SUB0_DFP1_VAL_Brightness  = 0       default
  _User_SUB0_DFP1_VAL_RGB_Gamma_R = 100     default
```

**The entire "NVIDIA look" was saturation 125 %.** Nothing else.

Intel Graphics Software has the same control. Set:

```
Intel Graphics Software -> Display -> Color -> Saturation:  50 (default)  ->  ~62
```

62 on Intel's 0–100 scale (50 = neutral) is the same +25 %. Nudge one step either way to
taste.

---

## Result after switching to Optimus

Measured immediately after the switch and the Intel saturation change:

```
panel owner     : Intel iGPU (Optimus)
active monitors : 1
brightness i/f  : 1          ✅
brightness      : 20 %
refresh         : 360 Hz
dwm CPU         : 1.8 % / 1.0 %
```

Games still run on the RTX 4060 — every title on the machine already carries
`GpuPreference=2` (High performance) in
`HKCU\Software\Microsoft\Windows\CurrentVersion\...\UserGpuPreferences`
(`Client-Win64-Shipping.exe`, `GTA5.exe`, `SnowRunner.exe`, `Wuthering Waves.exe`).

Cost: roughly **0–5 %** frame rate versus discrete mode, because the frame is presented
through the iGPU. At 120–200 fps it is not noticeable; at 300+ fps in esports it is.

---

## What to do with the repair script now

| Situation | Action |
|---|---|
| You stay in **Optimus** | You don't need the script at all. Single path, nothing to repair. |
| You need **NVIDIA-only for a session** | Expect to lose brightness. The script will still fix genuine lag (`dwm >= 15 %`), but it also removes brightness — that is unavoidable. |
| You want all three | Optimus + Intel saturation ≈ 62. |

The logon watchdog has been uninstalled on the machine this was diagnosed on, because it
was silently trading brightness for a lag that was not there.

---

## Self-check

```powershell
# who owns the panel
nvidia-smi --query-gpu=display_active --format=csv

# is brightness available, and through which path
Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBrightness |
    Select-Object InstanceName, CurrentBrightness

# is the compositor doing double work
$p1=(Get-Process dwm).CPU; Start-Sleep 10; $p2=(Get-Process dwm).CPU
"{0}% of one core" -f [math]::Round(($p2-$p1)/10*100,1)
```
