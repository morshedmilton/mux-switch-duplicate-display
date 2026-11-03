# 📓 Known limitations of "NVIDIA GPU only" mode

> Measured on a Dell G15 5530 (i7-13650HX, RTX 4060 Laptop, Intel UHD, AUO AA9F
> 1920×1080 360 Hz). Other MUX laptops may behave better — or worse. Test yours.

Switching the MUX to **NVIDIA GPU only** (discrete) is not a free upgrade on this
model. Two things measurably break, and one of them cannot be worked around.

---

## 1. Brightness control disappears entirely ⛔

### Symptom

- `Fn` + brightness keys do nothing
- the brightness slider in Settings does nothing, or is missing
- the screen sits at a fixed level

### Evidence

```powershell
Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBrightness
# -> no output, no instances
```

Every brightness class exists as a **definition** but has **zero instances**:

| WMI class | instances in discrete mode | instances in Optimus mode |
|---|---|---|
| `WmiMonitorBrightness` | **0** | 1 |
| `WmiMonitorBrightnessMethods` | **0** | 1 |
| `NvWmiBrightness` | **0** | — |
| `WmiMonitorBrightnessEvent` | **0** | — |

Windows still sees the panel:

```powershell
Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBasicDisplayParams
# InstanceName : DISPLAY\AUOAA9F\5&39808dae&2&UID4353_0
# Active       : True
```

…and the panel is genuinely on the dGPU:

```powershell
nvidia-smi --query-gpu=display_active --format=csv
# Enabled
```

But nothing exposes a backlight interface, so **there is no target for the key press
or the slider**. Nothing to fix at the Windows level: the control channel does not exist.

### Why

The ACPI backlight path (`_BCM` / `_BQC`) on this platform hangs off the **integrated
GPU's ACPI device**, and the embedded controller that physically drives the panel's
backlight PWM is addressed through it. When the MUX moves the panel to the RTX 4060,
Windows loses that handle.

The NVIDIA miniport on this model does **not** publish its own brightness interface to
compensate — `NvWmiBrightness` also has zero instances. NVIDIA's driver does store a
per-display value (`_User_SUB0_DFP1_VAL_Brightness` in its registry key), but it is not
wired to the OS.

This is not a driver fault you can reinstall away, and there is no registry switch for
it. It is how the firmware and the two drivers are arranged.

### Workaround

None that is safe. Options:

| Option | Result |
|---|---|
| Switch back to **Optimus** | brightness returns immediately, no reboot needed |
| Third-party EC brightness tools | not verified on this model, can write EC directly — not recommended |
| External monitor with its own brightness | works, but not the internal panel |

---

## 2. Duplicate display path and `dwm` CPU burn ⚠️

Covered in full in the [main README](../README.md).

In short: after the switch, Windows keeps the old monitor instance alive, `dwm`
composites on both adapters, and 35–46 % of a CPU core disappears while the desktop is
idle. Unlike brightness, this one **can** be repaired in 40 seconds.

---

## So what is "NVIDIA GPU only" actually good for?

| | Optimus | NVIDIA GPU only |
|---|---|---|
| Brightness control | ✅ | ❌ gone |
| Desktop compositor load | ✅ normal | ⚠️ can double |
| Battery life | ✅ | ❌ much worse |
| Game FPS | baseline | +3–8 % in esports, less elsewhere |
| Panel scanout latency | one extra copy | ✅ direct |

**Recommendation for this model: stay in Optimus.** Games still render on the RTX 4060;
only the present step uses the iGPU. You lose a few percent in high-frame-rate esports
titles and keep working brightness, a quiet desktop and usable battery.

Switch to discrete mode only for a session where you specifically need the last few
percent — and know that brightness control goes with it.

---

## Quick self-check

```powershell
# 1. which GPU owns the panel?
nvidia-smi --query-gpu=display_active --format=csv

# 2. is there any brightness control at all?
(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBrightness | Measure-Object).Count
# 0 = no control (discrete mode), 1 = control present (Optimus)

# 3. is the duplicate display path present too?
(Get-PnpDevice -Class Monitor | Where-Object Status -eq 'OK' | Measure-Object).Count
# 2 = yes, run tools/fix-display-after-mux-switch.ps1
```
