# Kiosk dashboard iteration workflow

**Status:** WIP — proven loop, needs refinement to reduce PR count per iteration.

Pinned reference for iterating on `dashboards/kiosk.yaml`. Built from one
debugging session (PRs #289 → #302) that landed eight kiosk changes via
the same loop and surfaced its pain points.

---

## The loop (as run today)

For each visual change to the kiosk dashboard:

1. **Edit** `dashboards/kiosk.yaml` on a feature branch off latest `origin/main`.
2. **Commit + push + PR** with auto-merge armed:
   ```bash
   git checkout -b kiosk-<change>
   # edit YAML
   git add dashboards/kiosk.yaml && git commit -m "..."
   git push -u origin kiosk-<change>
   gh pr create --title "..." --body "..."
   gh pr merge <PR#> --auto --squash --delete-branch
   ```
3. **Wait for required status checks** to pass (`YAML Lint`, `check-config`, `Dashboard Entities`, `ShellCheck`, `Bats`, `ESPHome Config`). Typical ≈ 1–2 min.
4. **Trigger the gitops sync manually** (don't wait for the 5-min poll):
   ```python
   ha_call_service('shell_command', 'gitops_sync', return_response=True)
   ```
   Look for `[INFO] Routing: dashboards → lovelace.reload_resources` on success.
5. **Restart the kiosk Chromium on pve2** to force it to re-fetch the YAML:
   ```bash
   ssh root@pve2 'systemctl restart dashboard-kiosk.service'
   ```
   `lovelace.reload_resources` does *not* refresh an already-rendered kiosk page; the service restart re-launches Chromium clean. ~5 s.
6. **Capture native 2560×1440 PNG** via `scrot` on pve2's X11:
   ```bash
   ssh root@pve2 'rm -f /tmp/kiosk.png && DISPLAY=:0 scrot /tmp/kiosk.png'
   scp root@pve2:/tmp/kiosk.png ~/repos/homeassistant-config/kiosk-current.png
   ```
   `rm -f` first: `scrot` declines to overwrite an existing file, defaulting to `/tmp/kiosk_NNN.png` which `scp` then misses.
7. **Read the PNG**, analyze, plan the next edit. Crop with PIL when you need to focus on one cell:
   ```python
   from PIL import Image
   img = Image.open('kiosk-current.png')
   img.crop((1163, 8, 1860, 320)).save('/tmp/alarm-crop.png')
   ```

Wall time per iteration: **≈ 2–4 min** (CI gate dominates).

---

## What's working well

- **scrot via pve2** is the right capture surface. Playwright MCP can't run from the alacritty snap (Chrome SIGSEGVs on DBus portal denial); the kiosk's own Chromium has the live state with all HACS resources loaded and is more authoritative than a fresh headless browser.
- **`scrot root@pve2` (no jump host)** — pve2 is on the workstation LAN at `192.168.139.7`. The CLAUDE.md "via `ssh root@pve.local ssh pve2`" notation documents the in-cluster path; from the workstation, direct SSH works.
- **Manual `shell_command.gitops_sync` trigger** turns the deploy step from up-to-5-min wait into ~1 s.
- **`systemctl restart dashboard-kiosk.service`** is the reliable refresh — `lovelace.reload_resources` (which the sync script calls automatically) reloads JS/CSS module resources but not an already-rendered dashboard config in a running Chromium.

---

## Pain points (what to refine)

### 1. Too many tiny PRs

One change per PR meant 8 PRs in one session, each a separate CI cycle and several with rebase-onto-main steps as prior PRs squash-merged. The `git rebase --onto origin/main <pre-squash-sha>` dance is fiddly and easy to get wrong.

**Direction:** Bundle related visual edits into fewer PRs. Plan 3–5 tweaks up front; commit them all on one branch; one PR.

### 2. Squash-merge breaks chained branches

If branch `B` was based on `main + commit A` and `A` gets squash-merged as `A'`, then `B` no longer has a clean ancestor on main. Rebase fails with conflicts on `A`'s content. Fix: `git rebase --onto origin/main <commit-A-sha>` to drop `A` and replay only the new commits on top of fresh main.

**Direction:** Don't chain branches. Wait for one PR to land (or open them all only when independent).

### 3. Lots of layout debugging via roundtrips

Discovering that HA Lovelace `vertical-stack` needs explicit-pixel-height `custom:mod-card` wrappers (not just `flex: 1 1 auto`) took 4 iterations of build → deploy → scrot. Each iteration burned ~3 min.

**Direction:** Document the layout patterns we discovered (below) so they're cookbook-ready next time.

### 4. The PR-gate adds latency

Required status checks (`YAML Lint`, `check-config`, etc.) are right for `main` but slow exploratory work. SSH access to HAOS is currently sandbox-denied, so the fast-iterate path (`scp` directly to `/config/dashboards/kiosk.yaml` and skip the PR until the design is finalized) isn't available.

**Direction:** Either authorize SSH to HAOS for exploratory rounds, or accept the ~2 min per cycle as the floor and batch more changes per PR.

### 5. `scrot` overwrite quirk + monitor timeout

- Always `rm -f /tmp/kiosk.png` before `scrot` or it falls back to `/tmp/kiosk_000.png`.
- The `Monitor` poll-for-merge tool defaults to 300 s; PRs commonly take longer (CI + arm + merge + delete-branch). Use `timeout_ms: 600000`.

---

## Layout patterns learned (cookbook)

For each top-row cell of the kiosk grid (300 px tall, variable width):

```
mod-card (outer cell, view_layout: { grid-area: NAME })
├── card_mod ha-card { height: 100%; display: flex; flex-direction: column; gap: Npx; padding: 0; }
└── vertical-stack
    ├── mod-card  ← child 1, EXPLICIT height: NNpx !important
    │   ├── card_mod ha-card { height: NNpx !important; }
    │   └── (actual card, e.g. button-card / clock-weather-card)
    └── mod-card  ← child 2, EXPLICIT height: MMpx !important
        ├── card_mod ha-card { height: MMpx !important; }
        └── (actual card, e.g. horizontal-stack of buttons)
```

### Heuristics

1. **Wrap every vstack child in a `custom:mod-card`** with an explicit pixel height. `flex: 0 0 NNpx !important` on the vstack child's `:first-child` / `:last-child` does not reliably stretch the wrapped card's host element — without an explicit `ha-card { height: NNpx }`, the inner card collapses to content height.

2. **Account for the outer mod-card's padding** when budgeting heights. A `padding: 6px` on the outer ha-card costs 12 px total — easy to miss and exactly the amount that pushed our `200 + 95 + 4` budget over a 300-px cell.

3. **`ha-card > * { height: 100% !important; display: block !important; }`** in each child mod-card's card_mod is the easy way to force the inner card's host (button-card, clock-weather-card, etc.) to fill the slot. Without this, even with the slot pinned to 200 px, the button-card content can render top-aligned with the slot's background visible only behind the actual content (looks like the card collapsed even though it didn't).

4. **`overflow: hidden`** on a fixed-height slot clips overflow visually but does not change the box height — the parent grid cell stays the same size.

5. **`layout: vertical` on `mushroom-template-card`** in tight slots (< 90 px) hides primary/secondary text. Stick with the default horizontal layout in compact cards.

6. **The `<<: *anchor` YAML merge pattern** with explicit overrides produces "duplicate key" warnings in HA's annotated YAML loader. The override wins at runtime, but the warnings clutter logs. Acceptable for now.

7. **Don't use the `| strftime('%a')` filter** — it doesn't exist in HA's Jinja. Use `(value | as_datetime | as_local).strftime('%a')` as a method call.

8. **Long Jinja dict literals** in YAML hit the `yamllint` 250-char line-length limit. Wrap dict entries across lines; HA's Jinja accepts multi-line dict literals.

---

## Where to next

**Immediate refinements:**

- A wrapper script `~/.local/bin/kiosk-snap` that does restart + scrot + scp in one command. Saves ~30 s of typing per cycle.
- Authorize SSH to the HAOS VM so exploratory iteration can `scp` the YAML directly (skip PR + CI) and only PR the final state.
- Batch multiple cell edits per PR; aim for 1 PR per "design idea" not 1 PR per tweak.

**Open layout issues to revisit:**

- Clock-weather-card content is naturally ~250 px tall and clips slightly at 215 px allocation. Either accept the clip or replace with a mushroom-template-card clock + condition strip for full control over sizing.
- Forecast strip condition icons render but are visually small in the 80 px slot — could be larger if we trade off some clock height.

**Process tweaks:**

- Treat each new feature as a *design doc* first (sketch the layout intent + cell budgets), THEN make the edits and PR them together. Helps avoid the 4-iteration "wait that breaks the layout" pattern.
- When the visual is hard to predict, build the change in a `kiosk-test.yaml` dashboard first (cheap to register a second YAML dashboard), iterate there, port the working version back to `kiosk.yaml` once stable.
