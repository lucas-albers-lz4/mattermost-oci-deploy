# 13 - Parent Community Brief (Work In Progress)

Draft notes for a parent-facing decision summary. **Not** a finished letter—use this to continue the conversation later.

**Model:** Invite-only; known families/friends; admin creates every account.

**Related deployment docs:** [`09-security-hardening.md`](09-security-hardening.md), [`10-audio-video-calls.md`](10-audio-video-calls.md), [`05-backups-and-restore.md`](05-backups-and-restore.md)

---

## Open decisions

- [ ] Draft one-page parent letter (sections 1–3, 5, 9 below)
- [ ] Decide community DM/call policy (channels-only vs allowlist DMs vs status quo)
- [ ] If policy requires it: technical changes (`RestrictDirectMessage`, disable DM video, DM-disable plugin)
- [ ] Fill in placeholders: admin name/contact, prod hostname, team names, minimum age, consent process

---

## 1. One-paragraph pitch (what this is)

- **Private community chat**, not a public app like Discord/TikTok open servers.
- **Self-hosted** on a single server you operate; data stays on infrastructure you control (OCI VM + encrypted HTTPS).
- **Purpose:** group chat and calls for a **known circle** (friends, neighbors, teams)—not open discovery.
- **Who runs it:** [You/name] as system admin; accounts are **created by admin**, not self-signup.

---

## 2. Direct answers to the two big fears

### Fear A: “My kid will talk to strangers”

| Claim | True today? | Plain-language explanation |
|-------|-------------|----------------------------|
| Random people can sign up and find my child | **No** | Open signup is **off** (`EnableUserCreation=false`, email signup off). No public registration page. |
| Random people can browse teams and join | **No** | Open server is **off** (`EnableOpenServer=false`). Users join teams **by admin invite** only. |
| Anyone on the internet can message if they guess the URL | **No** | They still need a **username + password** an admin created. |
| An invited adult/parent could message my child | **Yes, possible** | Everyone on the server is someone an admin added. This is a **trusted-community** model, not “zero contact with adults.” |
| Completely unknown strangers | **Unlikely** if you only invite known families | Residual risk is **mis-invite** (wrong email/name) or **account sharing**, not open social discovery. |

**Key parent line:** *“This is closer to a private group chat for people we already know—not a place where strangers wander in.”*

### Fear B: “My kid will talk privately with adults”

| Feature | Current behavior | Parent implication |
|---------|------------------|-------------------|
| **Direct messages (text)** | Mattermost allows DMs between members on the server (default: anyone on server can DM anyone) | A child **can** private-message another member, including adults, unless you add extra rules/plugins. |
| **Voice calls in channels** | Enabled for all channel members | Group voice in team channels—not 1:1 hidden unless they use DMs. |
| **Voice + webcam in DMs** | **Enabled** (`MM_CALLS_ENABLE_VIDEO=true`) | 1:1 private **audio and video** is possible in direct messages between any two members. |
| **Screen share** | Enabled in channel/group calls | Usually visible in a channel context, not silently hidden. |
| **Built-in parental controls** | **None** | No age gates, time limits, or “kids can’t DM adults” in stock Mattermost. |
| **Admin visibility** | Admin can deactivate users, reset passwords, remove from teams | See [Admin visibility and encryption](#admin-visibility-and-encryption) below. |

**Key parent line:** *“We can control who gets an account, but we cannot automatically block every private conversation between a child and an adult unless we add community rules and possibly extra technical limits.”*

---

## 3. How access works (step-by-step for parents)

1. Admin creates account (no self-registration).
2. Child is added only to agreed teams (e.g. `friends-group`, sports team channel).
3. Strong password required (14+ chars, complexity enforced).
4. No email-based password reset (admin must help)—reduces account takeover via email, but means **you** handle lockouts.
5. MFA is **planned later**, not required at trial start.

---

## 4. What is **not** on this platform

- Not anonymous; usernames are real/community-known.
- Not algorithmic feeds or public profiles.
- Not end-to-end encrypted chat (see below).
- Not moderated by a company—**community admin + parent rules** apply.
- Not COPPA-compliant out of the box—you are responsible for age/consent choices.

---

## 5. Community rules (you write the specifics)

Suggest parents see explicit policies on:

- **Minimum age**
- **Parent consent** required before admin creates account
- **DM policy:** e.g. “Kids may only DM parents/coaches on the allowlist” or “no DMs, channels only”
- **Call policy:** e.g. “Voice/video only in group channels” or “no 1:1 calls with adults”
- **Reporting:** who to contact if something feels wrong
- **Consequences:** account suspension/removal

*Technical note:* Mattermost **cannot enforce** “kids don’t DM adults” without extra work; **rules + trust + admin response** are the baseline for trial.

---

## 6. Technical safeguards already in place

- **Invite-only accounts** — no open signup
- **Encrypted website connection** (HTTPS/TLS via Caddy)
- **Server hardening** — firewall, fail2ban, no public database exposure
- **Backups** — daily backups to private cloud storage (see [Backup encryption](#backup-encryption))
- **Separate test site** — admin-only test hostname, not for kids

---

## 7. Residual risks to disclose

1. **Invited adults are not strangers to the system** — DM/call with them is technically possible.
2. **DM video/voice is on** for 1:1 chats today.
3. **Kids on multiple teams** see broader member lists within those teams.
4. **Screenshots/forwarding** — users can copy content outside the app.
5. **Device-level risks** — malware, shared devices, weak passwords.
6. **No 24/7 professional moderation** — volunteer/admin model.

---

## 8. Optional future mitigations

| Mitigation | Effect on parent concerns |
|------------|---------------------------|
| `RestrictDirectMessage=team` | Limits **starting** new DMs to same-team members only |
| Disable DM video (`MM_CALLS_ENABLE_VIDEO=false`) | Removes webcam in 1:1; audio DMs may still exist |
| DM Disable plugin | Can block 1:1 and group DMs; forces channel-only talk |
| Separate teams (kids vs adults) | Reduces overlap; still not a child/adult firewall |
| MFA for adults first | Reduces account theft; doesn’t block kid-adult contact |
| Written allowlist + admin removes violators | Operational policy; fastest for small trial |

---

## 9. Parent decision checklist

- [ ] I understand this is **private to invited people**, not open to the public internet.
- [ ] I understand **my child could DM or 1:1 call** other members unless we adopt stricter rules/settings later.
- [ ] I know **who the admin is** and how to report problems.
- [ ] I agree to **community rules** (age, DM/call policy, behavior).
- [ ] I will **help my child with a strong password** and not share accounts.
- [ ] I am OK with **trial without MFA** for now, knowing it will be added later.

---

## 10. FAQ snippets (copy/paste starters)

**Q: Can random people join?**  
A: No. Accounts are created by the admin; open signup is disabled.

**Q: Can my child video-chat privately with an adult?**  
A: Today, 1:1 direct message calls support audio and video between any two members on the server. We rely on invite-only membership and community rules; we can tighten settings if the group decides.

**Q: Do you read my child’s messages?**  
A: The server stores messages like most chat platforms. We don’t routinely monitor DMs, but the operator could access stored messages for recovery or safety. This is not end-to-end encrypted.

**Q: What if something goes wrong?**  
A: Contact [admin]. Accounts can be disabled immediately.

**Q: Is this forever?**  
A: Trial phase; rules and technical controls (like MFA) may tighten based on feedback.

---

## 11. Tone guidance

- **Lead with invite-only / no strangers**, then **clearly disclose DM + 1:1 video**.
- Avoid “100% safe”; use “designed for a known community with admin-controlled access.”
- Offer an **opt-out** without pressure.
- One page for skimmers; FAQ appendix for detail-oriented parents.

---

## Admin visibility and encryption

*Discussion notes — July 2026*

### Can a channel hide messages from the admin?

**In the UI — mostly yes for private channels.** A private channel is only visible to members. A system admin who is **not** a member usually won’t see it in the app.

**At the server/database level — no.** Messages (public channels, private channels, DMs) are stored in PostgreSQL in a form the server can read. Anyone with database access, backups, or shell on the VM can read them. Mattermost compares this to self-hosted email: **encryption at rest protects disks, not the operator.**

There is **no built-in “even the server operator cannot read this channel”** mode in stock Mattermost.

| Layer | Admin can read? |
|-------|-----------------|
| Private channel in UI (admin not a member) | Usually hidden |
| Database / backups / server access | **Yes** |
| “Only participants, not even admin” | **Not natively** |

### End-to-end encryption (E2E)?

**Not out of the box.** Standard Mattermost provides HTTPS in transit and optional disk/bucket encryption at rest—not E2E. The server sees message content.

**Third-party E2E plugins exist** (e.g. Quarkslab Mattermost E2EE plugin). Tradeoffs: per-channel opt-in, key management per device, broken search/bots, community/experimental, **not deployed in this repo today**. **Calls (voice/video) are not E2E** with Mattermost Calls.

**Parent one-liner:** *“Private channels hide content from other users in the app, but they don’t create a vault that the server operator can never read.”*

---

## Backup encryption

*Discussion notes — July 2026*

### Do we encrypt backups today?

**Partially, by default cloud storage—not application-level.**

| Copy | Format | Encryption today |
|------|--------|------------------|
| Live DB on VM | PostgreSQL | Not E2E; server admin can read |
| Local backups (`/opt/mattermost/backups/`) | Plain `pg_dump` + `.tar.gz` | **No** extra encryption in backup script |
| OCI Object Storage | Same files uploaded | **Private bucket**; OCI encrypts at rest with Oracle-managed keys by default. Customer-managed Vault key is **optional** (documented, not in OpenTofu yet). |

Backup files contain **readable chat content**. They are not public, but they are not “encrypted so only you can decrypt” unless you add that.

### What would encrypting backups protect from?

| Approach | Protects against | Does not protect against |
|----------|------------------|---------------------------|
| OCI at-rest encryption (default SSE) | Raw storage theft without OCI access | OCI console/API access, server admin restore, compromised VM |
| Customer-managed Vault key on bucket | Same + you control key lifecycle | Server admin at restore time |
| Encrypt tarballs before upload (`age`/`gpg`) | Leaked backup files without decryption key; bucket read-only insider without key | Compromised VM with key on disk; admin at restore time |
| All of the above | — | Strangers, kid-adult DMs, “admin can’t read messages” (that’s E2E, not backup encryption) |

### Should we?

For **invite-only known-families trial**:

- **Private bucket + lifecycle:** already in place—keep it
- **OCI default at-rest encryption:** fine as baseline
- **Customer-managed Vault key:** optional; good for key-control story to parents
- **Encrypt before upload:** probably overkill now—adds restore complexity; local plaintext copies on VM for 7 days are the bigger exposure

**Parent one-liner:** *“Chat is stored on our server; backups are kept in a private cloud account, not a public link. Backups are not end-to-end encrypted—the operator could access stored messages if needed for recovery or safety.”*

---

## Changelog

| Date | Notes |
|------|-------|
| 2026-07-04 | Initial brainstorm: parent fears, invite-only model, Calls/DM disclosure, admin visibility Q&A, backup encryption Q&A |
