# 📗 Evidence — what was actually measured

> Everything on this page was read off one machine, before and after the repair.
> Nothing here is inferred from a forum post.

---

## Test machine

| | |
|---|---|
| Laptop | Dell G15 5530 |
| GPU | NVIDIA RTX 4060 Laptop · driver 32.0.16.2101 (621.01) |
| iGPU | Intel UHD Graphics · driver 32.0.101.7088 |
| Panel | AUO AA9F · 1920 × 1080 · 360 Hz · internal eDP |
| OS | Windows 11 Pro · build 26300 |
| Trigger | graphics mode switched **Optimus → NVIDIA GPU only**, then reboot at 20:30 |

---

## 1. The panel moved to the dGPU — confirmed

```powershell
nvidia-smi --query-gpu=display_active --format=csv
```

```
display_active
Enabled
```

Combined with `Win32_VideoController`, only the NVIDIA adapter reported an active mode:

```
Name                               CurrentHorizontalResolution  CurrentRefreshRate
NVIDIA GeForce RTX 4060 Laptop GPU 1920                          360
Intel(R) UHD Graphics              (blank)                       (blank)
```

---

## 2. Two monitor devices, both `OK`, one panel

```powershell
Get-PnpDevice -Class Monitor
```

```
Status   FriendlyName        InstanceId
OK       Integrated Monitor  DISPLAY\AUOAA9F\4&3A9F8B26&8&UID8388688
OK       Generic Monitor     DISPLAY\AUOAA9F\5&39808DAE&2&UID4353
Unknown  Generic Monitor     DISPLAY\AUOAA9F\1&8713BCA&0&UID0
Unknown  Integrated Monitor  DISPLAY\AUOAA9F\4&3A9F8B26&8&UID0
Unknown  Generic Monitor     DISPLAY\DEFAULT_MONITOR\1&8713BCA&0&UID0
```

Four device instances exist for the same EDID (`AUOAA9F`), each bound to a different
monitor-class registry slot:

```
instance 1&8713bca&0&UID0        -> Driver ...\{4d36e96e-...}\0000   Capabilities 228
instance 4&3a9f8b26&8&UID0       -> Driver ...\{4d36e96e-...}\0001   Capabilities 224
instance 4&3a9f8b26&8&UID8388688 -> Driver ...\{4d36e96e-...}\0003   Capabilities 224   <- old path
instance 5&39808dae&2&UID4353    -> Driver ...\{4d36e96e-...}\0004   Capabilities 228   <- new path
```

Note the `Capabilities` difference: the two `OK` entries differ (224 vs 228), meaning
Windows created a **new device node with new capabilities** instead of reusing the old
one — and then left the old one enabled.

---

## 3. The topology database — one panel, two adapters

```powershell
Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Connectivity'
```

The key that matters:

```
SetId    : AUOAA9F0_01_07E6_5E_10DE_28E0_00000001_00000000_1101
         ^ AUOAA9F0_01_07E6_5E_8086_A78B_00000000_00020000_800050

Recent   : AUOAA9F0_01_07E6_5E_10DE_28E0_00000001_00000000_1101
Internal : AUOAA9F0_01_07E6_5E_8086_A78B_00000000_00020000_800050
External : AUOAA9F0_01_07E6_5E_10DE_28E0_00000001_00000000_1101
```

- `10DE` = NVIDIA PCI vendor id
- `8086` = Intel PCI vendor id
- the same panel identity `AUOAA9F0_01_07E6_5E` appears in **both**

Windows' connectivity database has stored the panel as a *set* containing two
adapter paths, and it labels the Intel path `Internal` and the NVIDIA path `External`.
That single fact explains everything downstream: the compositor is told there are two
targets.

---

## 4. Both adapters were rendering 3D work

```powershell
Get-Counter '\GPU Engine(*)\Utilization Percentage' -SampleInterval 1 -MaxSamples 10
```

```
LUID 0x00012e5e  engine 3d    avg 17.97%   max 30.1%
LUID 0x00013258  engine 3d    avg  6.98%   max 14.2%
LUID 0x00013258  engine copy  avg  0.04%   max  0.1%
```

Two different adapters (two LUIDs) doing 3D work while nothing but the desktop was
running. Per-process attribution:

```
pid 16008  AutoClaw2   luid 0x00012e5e   28.4%
pid 2304   dwm         luid 0x00012e5e   28.1%
pid 2304   dwm         luid 0x00013258   14.1%
```

`dwm` appears **twice**, once per adapter. That is the double composition.

---

## 5. dwm before and after

Measured with `(Get-Process dwm).CPU` deltas over a quiet interval, mouse untouched.

| Moment | dwm CPU (% of one core) |
|---|---|
| during initial triage | 45.8 |
| 10 s sample | 28.1 + 14.1 (two LUIDs) |
| clean 25 s sample | 35.1 |
| **immediately after re-enumeration** | **0.1** |
| + 5 min | 0.2 |
| + 10 min | 0.3 |
| + 20 min | 1.1 |

Same machine, same desktop, same applications. The only change was disabling and
re-enabling the Intel display adapter for six seconds.

---

## 6. It was not a general system stall

A 1 ms tick loop with a 40 ms stall threshold ran for 40 s before any repair:

```
total ticks : 40 s
stalls >40ms: 0
```

The system was **not** freezing. CPU total was 8 %, disk queue 0, processor queue 0,
DPC 0.33 %, interrupt 0.49 %. Everything was healthy except the compositor.

That is the signature of this bug: **latency, not starvation.**

---

## 7. Monitors are not installed through SetupAPI

```powershell
Select-String -Path C:\Windows\INF\setupapi.dev.log -Pattern 'AUOAA9F'
# 0 hits
```

The setup log records driver installs; it has nothing for this panel. Monitor devices
are enumerated **at runtime by the display stack**, not installed by PnP. This matters
for the attribution: the duplicate is a runtime topology decision, not a driver
installation event.

---

## What this evidence proves

- Windows had one physical panel bound to two adapter paths simultaneously
- both monitor device nodes were reported healthy
- both adapters were executing 3D work, with `dwm` present on each
- the compositor consumed 35–46 % of a CPU core while idle
- re-enumerating the iGPU collapsed it to one path, and dwm to ~0.2 %

## What it does **not** prove

- **why** Windows failed to retire the old path — that requires source-level knowledge
  of the display stack, which is not public
- whether every laptop with a MUX behaves this way (only one model was tested)
- whether a specific Windows build introduced it (no older build was available to compare)

Those open questions are exactly what the vendor report in [docs/04](04-report-to-vendor.md)
asks about.

---

**Next:** [permanent fix →](03-permanent-fix.md)
