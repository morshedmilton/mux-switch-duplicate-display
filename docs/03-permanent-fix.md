# 📙 Permanent fix — what is actually possible

> Short version: you cannot stop Windows from creating the duplicate, but you can make
> it impossible for the duplicate to survive a logon. That is a real permanent fix from
> the user's side.

---

## Why there is no setting for this

People ask for the obvious things. None of them exist:

| What you'd hope for | Reality |
|---|---|
| A registry key to disable dual composition | Does not exist. `dwm` composites whatever topology Windows reports. |
| A "reset display topology" checkbox in the NVIDIA driver | Does not exist. `Advanced Optimus` controls the *MUX*, not Windows' topology database. |
| A BIOS option | The BIOS performs the switch; it does not manage Windows' monitor enumeration. |
| A Dell utility | No such utility exists for this. Dell's graphics tool only changes the mode. |

The duplicate is created by the **Windows display stack** at the moment the panel
changes owner. Nothing on the OEM side writes to
`HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Connectivity` to clean it up.

So: no prevention. Only repair. The good news is that repair is fast, safe and
automatable.

---

## Option A — repair on demand (40 s)

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\fix-display-after-mux-switch.ps1
```

Put a shortcut on the desktop. Run it whenever the desktop stops feeling smooth after
a graphics-mode change.

**Good for:** people who switch modes rarely.
**Cost:** you have to notice the problem first.

---

## Option B — logon watchdog (recommended) ✅

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\install-logon-watchdog.ps1
```

Registers a scheduled task `MuxSwitchDisplayWatchdog`:

| property | value |
|---|---|
| trigger | at logon, delayed **2 minutes** |
| privileges | highest (no UAC prompt) |
| action | `fix-display-after-mux-switch.ps1 -Quiet` |
| behaviour when healthy | exits in seconds, changes nothing |
| behaviour when broken | repairs, logs the before/after numbers |
| log | `C:\ProgramData\MuxSwitchFix\fix.log` |

### Why "at logon" is the right trigger

A MUX switch **always requires a reboot**. The broken state therefore always appears
after a logon — never spontaneously in the middle of a session. One check per logon
covers every case, and costs nothing the rest of the time.

### What the watchdog checks

```
broken := (dwm CPU >= 15% on an idle desktop)
```

Two independent signals, so a stray phantom monitor will not trigger a repair on its
own, and a busy desktop will not either. The dwm figure is the **lower of two samples**
taken 8 seconds apart, because a single window animation can push it up briefly; the
real defect sits at 30 % and stays there.

> ⚠️ **Monitor count is deliberately *not* a trigger.** In "NVIDIA GPU only" mode the
> second (stale) monitor device is the only source of brightness control on this model.
> An earlier version of this script repaired on monitor count alone and silently killed
> brightness while the compositor was idle. See [docs/05](05-known-limitations.md).

### Verify it works

```powershell
Start-ScheduledTask -TaskName MuxSwitchDisplayWatchdog
Start-Sleep 60
Get-Content C:\ProgramData\MuxSwitchFix\fix.log -Tail 5
```

### Remove it

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\uninstall-logon-watchdog.ps1
```

---

## Option C — stop switching modes

Stay in **Optimus** permanently.

- games still render on the RTX 4060 — only the panel scanout uses the iGPU
- you give up roughly 3–8 % in esports titles at very high frame rates
- you never trigger the bug

If you never *need* discrete mode, this is genuinely the cleanest answer, because the
bug requires a mode change to appear.

---

## Things that do **not** work (tested or reasoned)

| Attempt | Why it fails |
|---|---|
| Deleting the duplicate monitor in Device Manager | Windows re-creates it from the topology database on the next enumeration |
| `Win + Ctrl + Shift + B` (restart display driver) | Resets the driver, not the topology. The stale path survives. |
| Reinstalling the GPU driver / DDU | The bug is not in the driver; a clean driver still enumerates two paths |
| `Win + P` cycling | Changes presentation mode, does not retire a stale adapter path |
| Disabling the iGPU **permanently** | Works, but you lose Optimus entirely — the laptop can no longer switch back, and on some models the MUX tool breaks. Only do this if you will never use Optimus again. |
| Reinstalling Windows | Comes back the first time you switch modes |

---

## Cost comparison

| | Manual fix | Watchdog | Stay in Optimus |
|---|---|---|---|
| Effort per mode switch | 40 s, you must notice | **0 s** | 0 s |
| Risk | none | none (self-limits to 1 repair per logon) | none |
| Loses discrete-mode performance | no | no | a little, in esports |
| Survives Windows updates | yes | yes (task is independent) | yes |
| Survives a full reinstall | needs re-setup | needs re-setup | needs re-setup |

**Recommendation:** install the watchdog once. After a Windows reinstall, install it
again — it is one command, and it is in this repo for exactly that reason.

---

## Is the repair safe to run repeatedly?

Yes.

- `Disable-PnpDevice` / `Enable-PnpDevice` on a display adapter is the same operation
  Device Manager performs when you right-click → Disable device → Enable device.
- The adapter's driver is untouched.
- The panel is driven by the other GPU, so the screen only blinks.
- Worst case (adapter fails to come back): reboot. It returns enabled.

The script refuses to run when the state is already healthy, so it cannot loop.

---

**Next:** [report to vendor →](04-report-to-vendor.md)
