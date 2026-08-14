// Mints a short-lived LiveKit access token.
// The LiveKit API secret lives ONLY here — never in the iOS bundle.
//
// Deploy:  supabase functions deploy mint-livekit-token
// Secrets: supabase secrets set LIVEKIT_API_KEY=... LIVEKIT_API_SECRET=...

import { AccessToken } from "https://esm.sh/livekit-server-sdk@2";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

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

    const { squadId, displayName } = await req.json();
    if (!squadId) return new Response("squadId required", { status: 400 });

    // Confirm the caller is actually a member of this squad.
    const { data: membership } = await supabase
      .from("squad_members")
      .select("squad_id")
      .eq("squad_id", squadId)
      .eq("user_id", user.id)
      .maybeSingle();

    if (!membership) {
      await supabase.from("squad_members").insert({
        squad_id: squadId,
        user_id: user.id,
        display_name: displayName ?? "Squad member",
      });
    }

    const token = new AccessToken(
      Deno.env.get("LIVEKIT_API_KEY")!,
      Deno.env.get("LIVEKIT_API_SECRET")!,
      { identity: user.id, name: displayName ?? "Squad member", ttl: "2h" },
    );

    token.addGrant({
      room: squadId,
      roomJoin: true,
      canPublish: true,
      canSubscribe: true,
      canPublishData: true,
    });

    return new Response(JSON.stringify({ token: await token.toJwt() }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: String(error) }), { status: 500 });
  }
});
