# For Parents and Families

Plain-language summary of what this private chat server is, how access works, and what it does **not** guarantee.

**Operators and community organizers:** use the [Community channel policy worksheet](community-channel-policy.md) to plan teams, channels, and DM/call rules.

**Technical details:** [Security hardening](09-security-hardening.md) · [Audio and video calls](10-audio-video-calls.md) · [Backups](05-backups-and-restore.md)

---

## What this is

This is **private community chat** for people you already know — friends, neighbors, sports teams, or similar groups. It is **not** a public app where strangers discover and join servers like large social platforms.

- **Invite-only:** the community administrator creates every account. There is no open signup page.
- **Self-hosted:** messages are stored on a server the operator runs (Oracle Cloud), not sold as a consumer product by a big chat company.
- **Encrypted in transit:** the website uses HTTPS (padlock in the browser), like online banking.

---

## Can strangers contact my child?

| Question | Answer |
|----------|--------|
| Can random people sign up? | **No.** Open account creation is disabled. |
| Can random people browse and join teams? | **No.** The server is not an “open server.” |
| Could someone on the internet guess the URL and chat? | **No.** They still need a username and password the admin created. |
| Could another **invited** adult message my child? | **Yes, it is possible.** Everyone on the server was added on purpose. This is a **trusted community**, not “zero contact with adults.” |
| Completely unknown strangers? | **Unlikely** if only known families are invited. Residual risk is a wrong invite or shared passwords. |

**In one sentence:** *This is closer to a private group for people we already know — not a place where strangers wander in.*

---

## Can my child talk privately with adults?

| Feature | What it means |
|---------|----------------|
| **Text in channels** | Group rooms; membership is controlled by admins. |
| **Direct messages (text)** | By default, any two members on the server can private-message each other unless the community adopts stricter rules. |
| **Voice in channels** | Group voice calls in channels members belong to. |
| **Voice or video in direct messages** | **1:1 private calls are possible** between any two members with the current server settings, including video in DMs. |
| **Built-in parental controls** | **None.** There are no age gates or automatic “kids cannot DM adults” features in stock Mattermost. |

**In one sentence:** *We control who gets an account, but we cannot automatically block every private conversation unless the community adds rules and the operator changes server settings.*

For how **audio** vs **DM video** are enabled: channel voice requires the Calls plugin and network setup; DM video is one additional server setting on top. See [Audio and video calls](10-audio-video-calls.md).

---

## How admins control channels (your main lever)

Community shape is **team- and channel-based**, not per-user “turn audio on for this person.”

**Organizers control directly in Mattermost (no code changes):**

- **Teams** — separate groups (e.g. “U12 soccer” vs “Neighborhood parents”).
- **Private channels** — only invited members see the channel in the app.
- **Membership** — who is added or removed from each channel.
- **Channel moderators** — trusted adults manage one room.

**Requires the server operator to change settings** (see [Community channel policy](community-channel-policy.md)):

- Disable DMs entirely (channel-only talk).
- Limit DMs to the same team only.
- Turn off 1:1 video (or all DM calls).

---

## How access works

1. The administrator creates the account (no self-registration).
2. The child is added only to agreed teams and channels.
3. Passwords must be strong (14+ characters with complexity rules).
4. Email password reset is off — the admin helps with lockouts.
5. Multi-factor authentication may be added later for adults.

---

## What this platform is **not**

- Not anonymous — usernames are known within the community.
- Not end-to-end encrypted — the operator can access stored messages for recovery or safety (like self-hosted email).
- Not moderated by a large company — community rules and the administrator apply.
- Not COPPA-certified out of the box — adults are responsible for age and consent choices.

---

## Can the administrator read messages?

**In the app:** private channels are usually hidden from admins who are not members.

**On the server:** messages (including DMs) are stored in a form the operator can read from the database or backups. Private channels hide content from other **users**, not from the server operator.

Voice and video calls are **not** end-to-end encrypted with Mattermost Calls.

---

## Backups

Chat is backed up to a **private** cloud storage account (not a public link). Backups are not encrypted in a way that prevents the operator from reading them during restore. See [Backups and restore](05-backups-and-restore.md).

---

## FAQ

**Can random people join?**  
No. Accounts are created by the administrator only.

**Can my child video-chat privately with an adult?**  
With current defaults, 1:1 direct message calls support audio and video between any two members. The community can tighten this — see the [channel policy worksheet](community-channel-policy.md).

**Do you read my child’s messages?**  
Messages are stored on the server. The operator does not routinely monitor DMs but could access stored messages for recovery or safety. This is not end-to-end encrypted.

**What if something goes wrong?**  
Contact the community administrator. Accounts can be disabled immediately.

**Is group voice the same as turning on video for one user?**  
No. **Channel voice** needs the Calls feature (plugin + network). **DM video** is a separate server-wide setting. Organizers choose **who is in which channel**; the operator chooses **global** DM/call rules.

---

## Decision checklist for parents

- [ ] I understand this is **private to invited people**, not open to the public internet.
- [ ] I understand **my child could DM or 1:1 call** other members unless the community adopts stricter settings.
- [ ] I know **who the administrator is** and how to report problems.
- [ ] I agree to **community rules** (age, DM/call policy, behavior).
- [ ] I will **help my child with a strong password** and not share accounts.

---

## Safeguards already in this deployment

- Invite-only accounts and strong password policy.
- HTTPS for all web traffic.
- Firewall and intrusion blocking on the server; database not exposed to the internet.
- Daily backups to private object storage.
- Separate admin-only test site, not for children.

See [Security hardening](09-security-hardening.md) for the full operator checklist.
