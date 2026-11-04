# 🎯 The plan: colour + brightness + G-Sync + smoothness

> Four things the owner wants at the same time. Three of them are owned by whichever
> GPU drives the panel — so the whole problem is *who owns the panel, and when*.

---

## What owns what

| Resource | Owner | Available when |
|---|---|---|
| **Brightness 0–100** | ACPI backlight on the **Intel** GPU device → EC | panel on Intel, **or** the stale Intel path still enumerated |
| **NVIDIA colour** (saturation 125) | the **scanning** GPU's display pipeline | panel on NVIDIA |
| **G-SYNC / VRR** | the **scanning** GPU | panel on NVIDIA |
| **Smooth composition** | needs exactly **one** active path | one active monitor device |

That is the entire system. Everything else is a consequence.

---

## The three configurations

| | Brightness | NVIDIA colour | G-Sync | Smooth | FPS cost |
|---|---|---|---|---|---|
| **Optimus** (current) | ✅ | ❌ (Intel 62 instead) | ❌ | ✅ | 0–5 % |
| **NVIDIA only** | ❌ (unless stale path) | ✅ | ✅ | ❌ when the stale path is present | 0 % |
| **Automatic** (DDS) | ⚠️ during games only | ✅ in games | ✅ in games | ✅ | 0–5 % |

**Automatic — Dynamic Display Switching, a.k.a. Advanced Optimus — is the only
configuration that can give all four**, because it moves the panel to whoever needs it:
NVIDIA for the game, Intel for the desktop.

---

## Does this laptop have DDS?

Four independent hints. The first is the strongest.

| Evidence | Source |
|---|---|
| **Dell KB 000210473** — *"Alienware and G-Series laptops may show inconsistent GPU status in NVIDIA Control Panel"* — lists the **G15 5530** as an affected platform and documents a display mode called **"Automatic selection"**, with the fix path *dGPU mode → Automatic selection* | official Dell article |
| Dell's spec text for the G15 5530 panel reads **"NVIDIA G-SYNC + DDS Display"** | product listing / owner reports |
| `ACPI\NVDA0820\NPCF` — *NVIDIA Platform Controllers and Framework* — present and **OK** | this machine |
| `ParadeMuxEdpLinkRateDataReloadTrigger = 1` on the Intel display adapter | this machine (the Parade eDP MUX) |

NVPCF + a Parade MUX is exactly the hardware pair Advanced Optimus is built on, and Dell
has a KB article naming this model with the third mode.

### The catch: a BIOS prerequisite

Dell's own wording gates the feature: the BIOS switch **"Hybrid Graphics / Advanced
Optimus"** (labelled *"(when available)"*) must be **Enabled** before NVIDIA Control
Panel will offer *Automatic selection*. If that switch is off, only two modes appear —
which is very likely what is happening on this machine right now.

Availability is still **per SKU**: the model manual does not promise it for every panel.
So the order of checks matters:

1. **BIOS** (F2 at boot) → Display → *Hybrid Graphics / Advanced Optimus* → **Enabled**
   → save and exit. Unplug any external monitor first.
2. **NVIDIA Control Panel** → Display → **Display Mode** → look for *Automatic*

---

## The algorithm

```mermaid
flowchart TD
    A[Open NVIDIA CP → Display Mode] --> B{Automatic present?}
    B -->|No| C[Stay on Optimus<br/>+ Intel saturation 62]
    B -->|Yes| D[Select Automatic, reboot]
    D --> E[Run the 4-number check after a game]
    E --> F{All four good?}
    F -->|Yes| G[Keep it. Done.]
    F -->|No| H[Back to Optimus,<br/>it is the safe default]

    style C fill:#e6f3ff,stroke:#0066cc,color:#000
    style G fill:#e6ffe6,stroke:#00aa00,color:#000
    style H fill:#fff4e6,stroke:#cc7700,color:#000
```

### Step 1 — check for Automatic
One look at the page above. Nothing to install, nothing to change.

### Step 2 — enable it

Enable the BIOS switch first if it is not already on:

1. Reboot, press **F2** at the Dell logo → **Display** → *Hybrid Graphics / Advanced Optimus* → **Enabled** → Apply → Exit
2. In Windows: **NVIDIA Control Panel → Display → Display Mode → Automatic** → apply
3. Reboot if it asks

### How DDS decides

It is **per application**, not per fullscreen state. NVIDIA keeps an *allow-list* of
applications; the panel moves to the dGPU when an allow-listed app starts and returns to
the iGPU when the last one closes. So expect the panel to follow the game, and to come
back to Intel when you quit.

### Step 3 — verify with four numbers
After playing a game and quitting it:

```powershell
# 1. who owns the panel right now (should be back on Intel after the game closes)
nvidia-smi --query-gpu=display_active --format=csv,noheader

# 2. one active monitor (2 = duplicate path created by the switch)
(Get-PnpDevice -Class Monitor | Where-Object Status -eq 'OK' | Measure-Object).Count

# 3. compositor idle (should be under 3%)
$p1=(Get-Process dwm).CPU; Start-Sleep 10; $p2=(Get-Process dwm).CPU
"{0}%" -f [math]::Round(($p2-$p1)/10*100,1)

# 4. brightness interface present
(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBrightness | Measure-Object).Count
```

| Result | Meaning |
|---|---|
| 1 / 1 / <3 % / 1 | **Automatic works.** Keep it. |
| 1 / **2** / **30 %+** / 1 | the duplicate path came back with the switch → back to Optimus |
| 1 / 1 / <3 % / **0** | brightness did not return after the game → back to Optimus |

### Step 4 — roll back if needed
NVIDIA CP → Display Mode → **Optimus**. No registry changes were made, nothing to undo.

---

## Known trade-offs of Automatic

- **Brightness during games.** While the panel is on the NVIDIA GPU, the ACPI backlight
  handle is gone again (the same root cause as everywhere else in this repo). Set your
  brightness *before* launching, and it stays for the session.
- **A brief black flash** each time the panel moves. That is the MUX switching, not a bug.
- **DRM / HDCP** re-handshakes on every switch. Expect a short blink in Netflix or Prime
  Video; reload the tab if playback stalls. No evidence that protected playback breaks
  permanently — the protected path is inside the GPU that is scanning out, and both GPUs
  support it.

---

## If Automatic is not available

Then Optimus + Intel saturation ≈ 62 is the best available combination: brightness,
smoothness, and a colour match to NVIDIA's 125 %. The only real loss is G-Sync — and note
that this panel's EDID advertises **no adaptive-sync block** on either display path, so
G-Sync may never have been genuinely active here. Verify in NVIDIA CP: if
*Set up G-SYNC* never offered this panel as G-SYNC Compatible, there was nothing to lose.

The 0–5 % frame-rate cost of the extra copy is real but small; the 360 Hz panel is the
far bigger factor in how games feel.

---

## Why this is the honest answer

There is no registry key, driver option or script that makes one GPU own the panel and
the other own the backlight at the same time. The panel has exactly one owner at any
moment, and brightness, colour, sync and composition all follow that owner. The only
mechanism that changes owners *per application* is DDS — which is why the whole plan
hinges on whether that one page shows three options or two.
