import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

serve(async (req) => {
  const authHeader = req.headers.get("Authorization");
  const token = authHeader?.replace("Bearer ", "");
  let tokenParts = null;
  if (token) {
    try {
      const payload = JSON.parse(atob(token.split('.')[1]));
      tokenParts = payload;
    } catch (e) {
      tokenParts = "Invalid JWT structure";
    }
  }
  
  return new Response(JSON.stringify({ 
    message: "pong",
    tokenRole: tokenParts?.role
  }), { headers: { "Content-Type": "application/json" } });
});

