import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

serve(async (req) => {
  console.log("Bybit connectivity test started...");
  
  try {
    const response = await fetch("https://api.bybit.com/v5/market/time");
    const data = await response.json();
    
    console.log("Bybit response received:", data);
    
    return new Response(
      JSON.stringify({ 
        success: true, 
        message: "Successfully reached Bybit API from Tokyo Edge Function",
        data: data 
      }),
      { headers: { "Content-Type": "application/json" } },
    )
  } catch (error) {
    console.error("Bybit connectivity error:", error);
    
    return new Response(
      JSON.stringify({ 
        success: false, 
        message: "Failed to reach Bybit API",
        error: error.message 
      }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    )
  }
})
