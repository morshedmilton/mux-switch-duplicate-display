# 📕 Report it to the vendor

> The repair in this repo is a workaround. The defect belongs to Windows' display
> stack, triggered by the OEM MUX implementation. Here is exactly what to send,
> to whom, and what to ask for.

---

## Who to tell

| Channel | What to send | Likely outcome |
|---|---|---|
| **Microsoft Feedback Hub** (`Win + F`) | the report below, category *Devices and Drivers → Display* | low response rate, but it is the only official funnel for the actual defect |
| **Dell support** (chat or community forum) | the report, framed as *"duplicate display device after switching to NVIDIA GPU only"* | they can log it to engineering; may ask you to update BIOS |
| **NVIDIA** (driver feedback form) | the report, framed as *Advanced Optimus display-mode switch* | they own the mode switch, not the topology |

Send to **Dell first** — they have the most to lose from a bad MUX experience, and they
can reproduce it on their own hardware.

---

## Copy-paste report

> **Title:** Duplicate monitor device and 35–46 % idle `dwm.exe` CPU after switching to NVIDIA GPU only (MUX / Advanced Optimus)
>
> **Summary**
> After switching the graphics mode from Optimus to *NVIDIA GPU only* and rebooting,
> Windows enumerates the internal panel twice. Both monitor devices report status OK
> for a single physical panel, Desktop Window Manager composites every frame for both
> adapters, and `dwm.exe` consumes 35–46 % of one CPU core while the desktop is idle.
> The user-visible effect is input and rendering latency: typed characters appear late,
> scrolling and window animations are uneven, but the system never freezes.
>
> **Hardware / software**
> - Dell G15 5530, BIOS 1.36.0
> - NVIDIA GeForce RTX 4060 Laptop, driver 32.0.16.2101 (621.01)
> - Intel UHD Graphics, driver 32.0.101.7088
> - Internal panel: AUO AA9F, 1920×1080, 360 Hz, eDP
> - Windows 11 Pro, build 26300
>
> **Steps to reproduce**
> 1. Set graphics mode to Optimus, reboot.
> 2. Switch graphics mode to *NVIDIA GPU only* (screen blanks), reboot.
> 3. Open Device Manager → Monitors. Two entries are active (status OK) for one panel.
> 4. Leave the desktop idle and observe `dwm.exe` in Task Manager: 30–50 % of one core.
>
> **Evidence**
> Two monitor devices with status OK for one physical panel:
> ```
> OK  Integrated Monitor  DISPLAY\AUOAA9F\4&3A9F8B26&8&UID8388688
> OK  Generic Monitor     DISPLAY\AUOAA9F\5&39808DAE&2&UID4353
> ```
>
> The display topology key binds the same panel to both adapters:
> ```
> HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Connectivity
> SetId    : AUOAA9F0_01_07E6_5E_10DE_28E0_...  ^  AUOAA9F0_01_07E6_5E_8086_A78B_...
> Internal : AUOAA9F0_01_07E6_5E_8086_A78B_...   (Intel path)
> External : AUOAA9F0_01_07E6_5E_10DE_28E0_...   (NVIDIA path)
> ```
>
> Both adapters execute 3D work simultaneously, with `dwm` present on each LUID
> (`\GPU Engine(*)\Utilization Percentage`).
>
> **Workaround that works**
> Disabling and re-enabling the Intel display adapter (forcing re-enumeration) makes the
> stale monitor device phantom and drops `dwm.exe` from 35–46 % to 0.2 % of one core.
> No reboot required. This proves the defect is the stale display path, not the driver.
>
> **What I am asking for**
> 1. On a graphics-mode switch, Windows should retire the previous display path instead
>    of keeping both monitor devices active.
> 2. Until then: could the mode-switch routine force a display topology reset, so the
>    stale path never survives the reboot?
> 3. Confirmation whether this is a known Microsoft display-stack issue, and whether a
>    Windows update or BIOS release addresses it.

---

## Attachments that make it actionable

Run these and attach the output files:

```powershell
# 1. current state, machine readable
powershell -ExecutionPolicy Bypass -File .\tools\fix-display-after-mux-switch.ps1 -MeasureOnly *> measure.txt

# 2. the topology database
reg export "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Connectivity" connectivity.reg /y

# 3. the monitor devices
Get-PnpDevice -Class Monitor | Select-Object Status,Class,FriendlyName,InstanceId,Problem |
    Export-Csv monitors.csv -NoTypeInformation

# 4. standard system report
dxdiag /t dxdiag.txt
```

Attach `measure.txt`, `connectivity.reg`, `monitors.csv`, `dxdiag.txt`.

> `connectivity.reg` contains no personal data — display identifiers only.

---

## What to expect (be realistic)

- **Microsoft:** the Feedback Hub is a black hole for most reports. Volume helps. If
  others file the same thing with the same wording, it gets triaged faster.
- **Dell:** a support agent will likely ask you to update the BIOS and reinstall the
  GPU driver. Reply with the evidence above and state clearly that a driver reinstall
  does not change the behaviour, because the defect is reproducible immediately after
  a mode switch on a clean install.
- **NVIDIA:** they will point at Microsoft for the topology and at Dell for the MUX.

None of this is fast. That is precisely why the workaround exists — it makes the bug
irrelevant to your daily use while the vendors argue.

---

## Help other users find it

The single most useful thing you can do besides reporting: publish your case with the
measurements. Search results are how the next person with the same symptom finds the
fix instead of reinstalling Windows.

If you open an issue on this repo, include:

1. `-MeasureOnly` output
2. your `Connectivity` key
3. laptop model, BIOS, GPU driver versions
4. whether the repair worked (before/after dwm numbers)
