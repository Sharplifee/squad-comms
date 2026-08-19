// Turns a transcribed utterance into a structured voice intent.
//
// Runs server-side so the model call needs no OS 27 / Foundation Models support
// on device — the iPhone only ever sends already-transcribed text (Speech
// framework transcribes on-device) and receives JSON back.
//
// Deploy:  supabase functions deploy parse-command
// Secrets: supabase secrets set OPENROUTER_API_KEY=...
//
// Contract: { utterance: string, roster?: string[] }
//        -> { action, volume, target, confidence }
// Any failure returns a non-2xx so the client falls back to its keyword table.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const MODEL = "anthropic/claude-sonnet-4.5";

const ACTIONS = [
  "mute",
  "unmute",
  "muteAll",
  "unmuteAll",
  "setVolume",
  "whosOn",
  "rewind",
  "leave",
  "unknown",
] as const;

const SYSTEM = `You classify short spoken commands from a hands-free walkie-talkie app used mid-workout.
Input is a raw on-device speech transcription: no punctuation, frequent mishearings, filler words, and gym noise artifacts.
Return the single intent the speaker most plausibly meant.

Actions:
- mute        silence the speaker's own microphone ("mute me", "cut my mic", "don't pick me up")
- unmute      re-open their own microphone ("i'm back", "unmute me", "open my mic")
- muteAll     silence everyone else ("mute everyone", "quiet the squad")
- unmuteAll   un-silence everyone else
- setVolume   change how loud the squad is in their ears. Set volume 0.0-1.0.
              Map spoken percentages and scales: "half" 0.5, "all the way up" 1.0,
              "turn them down" 0.3, "volume to 7" (out of 10) 0.7.
- whosOn      asking who is currently connected ("who's on", "who's here", "anyone else on")
- rewind      replay what was just missed ("what did you say", "rewind that", "say again")
- leave       exit the squad entirely ("close the line", "i'm out", "leave squad", "hang up")
- unknown     not a command — ordinary conversation, or too garbled to act on

Confidence is 0.0-1.0 and reflects how sure you are the speaker issued that command.
Ordinary talk between squad members must return unknown with low confidence — acting on
a false positive mid-set is worse than missing one. Never guess a destructive action
(leave, muteAll) above 0.7 unless the phrasing is unambiguous.`;

const SCHEMA = {
  type: "object",
  properties: {
    action: { type: "string", enum: ACTIONS },
    volume: {
      type: ["number", "null"],
      minimum: 0,
      maximum: 1,
      description: "Only for setVolume, otherwise null.",
    },
    target: {
      type: ["string", "null"],
      description: "Squad member name if the command names one, else null.",
    },
    confidence: { type: "number", minimum: 0, maximum: 1 },
  },
  required: ["action", "volume", "target", "confidence"],
  additionalProperties: false,
};

Deno.serve(async (req) => {
  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } },
    );

    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return new Response("Unauthorized", { status: 401 });

    const { utterance, roster } = await req.json();
    if (typeof utterance !== "string" || utterance.trim().length === 0) {
      return new Response("utterance required", { status: 400 });
    }
    // Long input is conversation, not a command. Don't pay for it.
    if (utterance.length > 300) {
      return new Response(
        JSON.stringify({ action: "unknown", volume: null, target: null, confidence: 0 }),
        { headers: { "Content-Type": "application/json" } },
      );
    }

    const key = Deno.env.get("OPENROUTER_API_KEY");
    if (!key) return new Response("model credential missing", { status: 503 });

    const names = Array.isArray(roster) ? roster.filter((n) => typeof n === "string") : [];
    const context = names.length
      ? `\n\nSquad members currently on the line: ${names.join(", ")}.`
      : "";

    const upstream = await fetch("https://openrouter.ai/api/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${key}`,
        "Content-Type": "application/json",
        "X-Title": "squad comms",
      },
      body: JSON.stringify({
        model: MODEL,
        max_tokens: 200,
        temperature: 0,
        messages: [
          { role: "system", content: SYSTEM + context },
          { role: "user", content: utterance },
        ],
        response_format: {
          type: "json_schema",
          json_schema: { name: "voice_intent", strict: true, schema: SCHEMA },
        },
      }),
    });

    if (!upstream.ok) {
      const detail = await upstream.text();
      // 429 and 5xx are both "fall back to keywords", not "fail the command".
      return new Response(
        JSON.stringify({ error: "model_unavailable", status: upstream.status, detail }),
        { status: upstream.status === 429 ? 429 : 503, headers: { "Content-Type": "application/json" } },
      );
    }

    const payload = await upstream.json();
    const raw = payload?.choices?.[0]?.message?.content;
    if (typeof raw !== "string") return new Response("empty model response", { status: 503 });

    let parsed;
    try {
      parsed = JSON.parse(raw);
    } catch {
      return new Response("unparseable model response", { status: 503 });
    }

    const action = ACTIONS.includes(parsed?.action) ? parsed.action : "unknown";
    const volume = typeof parsed?.volume === "number"
      ? Math.min(1, Math.max(0, parsed.volume))
      : null;
    const confidence = typeof parsed?.confidence === "number"
      ? Math.min(1, Math.max(0, parsed.confidence))
      : 0;

    return new Response(
      JSON.stringify({
        action,
        volume,
        target: typeof parsed?.target === "string" ? parsed.target : null,
        confidence,
      }),
      { headers: { "Content-Type": "application/json" } },
    );
  } catch (error) {
    return new Response(JSON.stringify({ error: String(error) }), { status: 500 });
  }
});
