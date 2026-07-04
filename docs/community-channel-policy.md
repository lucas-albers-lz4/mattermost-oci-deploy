# Community Channel Policy

Worksheet for **community organizers and server operators** planning teams, channels, and communication rules before inviting families.

**Parents:** see the plain-language summary in [For parents and families](for-parents.md).

---

## Purpose

Decide how your community is structured **before** accounts are created:

- Which teams and channels exist
- Who belongs where
- Whether direct messages and 1:1 calls are allowed
- What requires **Mattermost UI** changes vs **server configuration**

Fill in the sections below for your community. Do not commit this file with real names or secrets if you fork the repo — keep a private copy.

---

## 1. Community profile

| Field | Your value |
|-------|------------|
| Community name | |
| Administrator name / contact | |
| Production chat URL | `https://` |
| Minimum age | |
| Parent consent process | |
| Last reviewed (date) | |

---

## 2. Team and channel map

List each **team** (Mattermost “team” = a workspace grouping) and its channels.

### Team: _______________

| Channel | Public or private | Purpose | Moderator(s) | Who is invited |
|---------|-------------------|---------|--------------|----------------|
| `#` | | | | |
| `#` | | | | |

### Team: _______________

| Channel | Public or private | Purpose | Moderator(s) | Who is invited |
|---------|-------------------|---------|--------------|----------------|
| `#` | | | | |

**UI steps (operator or team admin):**

1. **System Console** or team menu → create team if needed.
2. Create channel → choose **Public** or **Private**.
3. Add members explicitly to private channels.
4. **Channel dropdown → Manage members** to add/remove people.
5. Assign **Channel admin** role to moderators.

---

## 3. Communication policy decisions

Check one option per row, then implement using Section 4.

### Direct messages (text)

- [ ] **Open** — any member can DM any member (Mattermost default)
- [ ] **Team-scoped** — new DMs only within the same team (`RestrictDirectMessage=team`)
- [ ] **Disabled** — channel-only; use DM Disable plugin or equivalent

### Voice and video calls

| Setting | Channel / group voice | DM voice | DM video | Screen share |
|---------|----------------------|----------|----------|--------------|
| Allowed? | ☐ Yes ☐ No | ☐ Yes ☐ No | ☐ Yes ☐ No | ☐ Yes ☐ No |

**Notes:**

- **Channel voice** requires Mattermost Calls (plugin + UDP `8443`). See [10-audio-video-calls.md](10-audio-video-calls.md).
- **DM video** is controlled by `MM_CALLS_ENABLE_VIDEO` in [`templates/compose.yml`](../templates/compose.yml) (enabled in this repo’s default prod stack).
- Disabling DM video does not remove DM text or DM audio.

### Community rules (write your norms)

- Reporting contact:
- Consequences (suspension, removal):
- Review cadence (e.g. start of each season):

---

## 4. UI vs technical enforcement

| Policy goal | Mattermost UI / ops | Server / repo change | Default in this repo |
|-------------|---------------------|----------------------|----------------------|
| Separate groups (sports vs neighbors) | Create teams; assign members | None | UI only |
| Private channel for one group | Private channel + membership | None | UI only |
| Remove someone from one room | Remove from channel | None | UI only |
| No DMs at all | Community rules | DM Disable plugin | **Not enabled** |
| DMs only within same team | — | `RestrictDirectMessage=team` in config | **Not set** |
| No 1:1 video | Community rules | `MM_CALLS_ENABLE_VIDEO=false` + recreate prod | **Video enabled** |
| Channel voice for members | Add to channels with Calls | Calls plugin + UDP (already in deploy) | **Enabled** |
| Only admins start calls | — | Calls Test Mode / `DefaultEnabled=false` | **All channel members** |

### How to apply server changes

**Disable DM video (prod):**

1. Edit `/opt/mattermost/compose.yml` (or template): set `MM_CALLS_ENABLE_VIDEO: "false"` on `mattermost-prod`.
2. `docker compose --env-file .env -p mattermost -f compose.yml up -d mattermost-prod`

**Restrict DMs to same team:**

1. System Console → Environment → or set in `config.json`: `"RestrictDirectMessage": "team"`.
2. Restart Mattermost if required.

**DM Disable plugin:**

1. Install plugin via System Console or `mmctl`.
2. Configure per plugin documentation.

See [09-security-hardening.md](09-security-hardening.md) and [10-audio-video-calls.md](10-audio-video-calls.md).

---

## 5. Example policy bundles

Pick the closest match, then customize Section 2–3.

### A. Channels-only (strictest)

- No DMs; all talk in named channels.
- Channel voice allowed; no DM calls.
- **Technical:** DM Disable plugin + `MM_CALLS_ENABLE_VIDEO=false` optional.

### B. Team-scoped DMs, no DM video

- DMs only within the same team (e.g. soccer team members).
- No 1:1 video; channel voice OK.
- **Technical:** `RestrictDirectMessage=team` + `MM_CALLS_ENABLE_VIDEO=false`.

### C. Trusted community (this repo’s defaults)

- Open DMs between members; channel voice enabled; DM video enabled.
- Relies on **invite-only membership + written community rules + admin response**.
- **Technical:** no extra plugins required; document honestly in [for-parents.md](for-parents.md).

---

## 6. Review cadence

Revisit this worksheet when:

- Adding a new age group or team
- Onboarding a new cohort of families
- After a safety or conduct incident
- Before enabling MFA or changing call/DM settings

---

## Related documentation

- [For parents and families](for-parents.md)
- [Security hardening](09-security-hardening.md)
- [Audio and video calls](10-audio-video-calls.md)
- [Documentation index](README.md)
