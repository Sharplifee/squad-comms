// Mints a short-lived LiveKit access token for squad comms.
// The LiveKit API secret lives ONLY here — never in the iOS bundle.
// squad comms is an anonymous, code-based app: there is no user sign-in,
// so this endpoint does not require a JWT. It is reached with the project
// publishable/anon key and issues a per-device random identity.
//
// Deploy:  supabase functions deploy mint-livekit-token --no-verify-jwt
// Secrets: LIVEKIT_API_KEY, LIVEKIT_API_SECRET

import { AccessToken } from "https://esm.sh/livekit-server-sdk@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const { squadId, displayName } = await req.json();
    if (!squadId) {
      return new Response(JSON.stringify({ error: "squadId required" }),
        { status: 400, headers: { ...cors, "Content-Type": "application/json" } });
    }
    const identity = crypto.randomUUID();
    const token = new AccessToken(
      Deno.env.get("LIVEKIT_API_KEY")!,
      Deno.env.get("LIVEKIT_API_SECRET")!,
      { identity, name: displayName ?? "Squad member", ttl: "2h" },
    );
    token.addGrant({
      room: String(squadId),
      roomJoin: true,
      canPublish: true,
      canSubscribe: true,
      canPublishData: true,
    });
    return new Response(JSON.stringify({ token: await token.toJwt() }),
      { headers: { ...cors, "Content-Type": "application/json" } });
  } catch (error) {
    return new Response(JSON.stringify({ error: String(error) }),
      { status: 500, headers: { ...cors, "Content-Type": "application/json" } });
  }
});
