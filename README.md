# squad comms

An always-on private audio layer that rides on top of whatever you're already
listening to. Open it once, connect with whoever you're training with, put your
phone away and forget it exists. When someone in your squad talks, their voice
comes through your headphones naturally and your music steps aside — then picks
right back up. No buttons, no call metaphor, no pulling earbuds out.

Formerly **OpenLine**. Renamed to squad comms.

---

## Why this rebuild exists

The original build lived only on the M1 Max at `/Users/connorsharp` with no git
and no remote, so there was no recoverable source. This repo is a clean rebuild
from the full architecture that survived in the corpus, with the known defects
fixed rather than carried forward.

**The bug that killed the original:** `AVAudioSession` was configured with
`.duckOthers` / `.voiceChat` permanently, which degraded background audio
quality for the entire session. The fix is baked in here — `.mixWithOthers` is
the permanent base option, and all ducking is done through LiveKit remote track
volume plus `MPMusicPlayerController`, never by reconfiguring the session.

---

## How the audio actually flows

```
Your voice
  -> earbud mic (Bluetooth, local to your phone only)
  -> iPhone, AVAudioEngine captures it
  -> WiFi or LTE, WebRTC to LiveKit Cloud
  -> LiveKit routes to everyone in the squad
  -> their iPhone
  -> their earbuds
```

Bluetooth is only ever the last metre between you and your own headphones. It is
never used between people. That means someone across the country is identical to
someone across the gym — 80-120ms versus 40-60ms, both well under the 150-200ms
a normal phone call runs at.

---

## What's in it

| Piece | File | What it does |
|---|---|---|
| Voice activity detection | `Audio/VADEngine.swift` | RMS tap with a SILENCE → TRANSMITTING → TRAILING state machine. This is what removes the button. |
| Ducking | `Audio/DuckingController.swift` | Owns AVAudioSession. Ramped fades so nothing sounds like a hard cut. |
| Voice commands | `Audio/CommandEngine.swift` | On-device `SFSpeechRecognizer`. "mute all", "rewind that", "close the line". |
| Coordinator | `Audio/AudioCoordinator.swift` | Single owner of everything audio-shaped, including phone-call interruptions. |
| Room + presence | `Session/SessionManager.swift` | LiveKit room, membership, per-listener mixing. |
| Token minting | `supabase/functions/mint-livekit-token` | The LiveKit secret lives here, never in the bundle. |
| Nearby detection | `Session/ProximityEngine.swift` | CoreBluetooth RSSI, badge only — not transport. |
| Staying alive | `Session/VoIPPushManager.swift`, `KeepAlive.swift` | VoIP push + 60s heartbeat. Screen off, phone in pocket, still running. |

Each person controls their own experience entirely. You choose who you hear, how
loud they are, whether your music ducks, pauses, or pauses and rewinds. Turning
someone down is local and silent — nobody else knows.

---

## Setup

1. Create a Supabase project, run `supabase/001_squad_comms_schema.sql`.
2. Deploy the edge function and set its secrets:
   ```
   supabase functions deploy mint-livekit-token
   supabase secrets set LIVEKIT_API_KEY=... LIVEKIT_API_SECRET=...
   ```
3. Register bundle `com.connor.squadcomms` in the Apple Developer portal and
   create the App Store Connect app record.
4. Add these GitHub Actions secrets:
   `APPLE_DIST_P12`, `APPLE_DIST_P12_PASSWORD`, `APPLE_TEAM_ID`,
   `APPLE_PROVISION_PROFILE`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`,
   `LIVEKIT_URL`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SENTRY_DSN`,
   `POSTHOG_API_KEY`.
5. Run the **iOS build and TestFlight** workflow from the Actions tab. No Mac
   required — it builds on a `macos-15` runner, same pattern as Momentum Crew.

## Testing

Two iPhone 16 Pros, two sets of earbuds. The second one doesn't need cellular —
WiFi carries LiveKit fine. The moment two people are talking through each
other's headphones with music ducking in a real gym, the MVP is proven.
