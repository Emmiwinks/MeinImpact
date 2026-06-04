# Authentication

## Purpose
Defines how the app controls access in MVP and documents the V2 account
architecture for future implementation.

---

## Decisions

- **MVP uses beta tokens only.** No accounts, no passwords, no session
  management. A beta token is a UUID delivered via invite link that unlocks
  the app permanently on the receiving device.

- **Beta tokens are anonymous.** The backend stores only the UUID and whether
  it has been used. No name, email, device fingerprint, or IP is stored.

- **Premium subscriptions are a V2 feature.** Subscription tokens are
  architected here but not implemented in MVP. Payment processing is not
  active.

- **V2 accounts use E2E-encrypted profile backup.** The encryption key is
  derived client-side from the user's password and never sent to the server.
  The backend stores an opaque encrypted blob it cannot read.

---

## MVP: Beta Token Flow

### Invite link generation (admin)
```
Admin generates invite batch:
  POST /admin/beta-tokens/generate
  Body: { count: 50 }
  Response: [ { token: UUID, invite_url: "https://meinimpact.de/beta?t=UUID" } ]
  Backend: INSERT INTO beta_tokens (token, used=false)
```

### First launch on device
```
User taps invite link → app opens with ?t=UUID in deep link
  App:
    1. POST /beta/activate { token: UUID }
       Backend: validate token exists AND used=false
                SET used=true
                Response: { valid: true }
    2. Store token in Hive meta.beta_token
    3. Proceed to onboarding
```

### Subsequent launches
```
App start:
  1. Read meta.beta_token from Hive
  2. GET /health?token={beta_token}
     Backend: validate token exists (used check not repeated)
     Response: { valid: true, pool_version: "..." }
  3. If invalid: show "Beta access required" screen with link to request invite
```

### Beta token table
```sql
beta_tokens (
  token UUID PRIMARY KEY,
  used BOOLEAN DEFAULT false,
  activated_at TIMESTAMP,  -- set when first used, no identity attached
  created_at TIMESTAMP
)
```

---

## Push Notification Token

Push tokens are separate from beta tokens. See `architecture/data-flow.md`
Flow 6. They are device-issued UUIDs from FCM/APNS with no identity attached.

---

## V2: Account System (documented, not implemented in MVP)

To be implemented when premium subscriptions or cross-device sync are
introduced. The following is a forward architecture decision.

### Account creation
```
User provides email + password (or magic link email only)
  App (client-side only):
    1. Derive encryption key from password using Argon2id:
       key = Argon2id(password, salt=user_id, memory=64MB, iterations=3)
    2. key never leaves the device
  App → Backend:
    POST /auth/register { email, password_hash (bcrypt, not raw) }
    Response: { user_id: UUID, subscription_token: UUID }
```

### Profile backup (cross-device sync)
```
App (client-side):
  1. Serialize Hive profile box to JSON
  2. Encrypt: encrypted_blob = AES-256-GCM(profile_json, key)
  App → Backend:
    PUT /profile/backup { encrypted_blob: base64 }
    Backend: stores opaque bytes, cannot read content
```

### Profile restore on new device
```
User logs in on new device
  App derives same key from password + user_id
  App → Backend:
    GET /profile/backup
    Response: { encrypted_blob: base64 }
  App decrypts locally → restore Hive profile
```

### What the backend stores in V2
```sql
users (
  id UUID PRIMARY KEY,
  email TEXT UNIQUE,
  password_hash TEXT,
  subscription_token UUID,
  encrypted_profile BYTEA,  -- opaque, backend cannot read
  streak INT,               -- non-sensitive, synced for display
  created_at TIMESTAMP
)
```

Note: The backend stores `streak` in V2 for cross-device display. Streak
is not Art. 9 data. Completed action IDs are stored only locally even in V2
to avoid any inference about political activity patterns.

### GDPR posture in V2
The backend stores `encrypted_profile` but cannot process or read it.
The privacy policy discloses this storage. The legal basis is Art. 6(1)(b)
(contract performance for cross-device sync feature). Deletion of the account
deletes the encrypted blob; the key is gone with it.

---

## Token Passing Convention

All API requests include the beta token (MVP) or session token (V2) as a
Bearer token in the Authorization header:

```
Authorization: Bearer {token}
```

The backend validates the token on every request. No request succeeds without
a valid token. Tokens are not logged in any access log.

---

## Dependencies

- Reads: `architecture/overview.md`, `architecture/dsgvo.md`
- Referenced by: `technical/api-endpoints.md`

---

## Open Questions

- [ ] V2: decide between magic-link-only (no password, simpler) vs
      password-based (required for client-side key derivation for E2E backup).
      Magic link alone cannot support E2E profile backup.
