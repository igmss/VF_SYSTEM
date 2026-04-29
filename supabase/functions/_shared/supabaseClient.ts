import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL");
const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

if (!supabaseUrl || !supabaseServiceRoleKey) {
  throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY environment variables.");
}

/**
 * Creates a Supabase client with the service role key.
 * Use this for administrative tasks that bypass RLS.
 */
export function createServiceClient(): SupabaseClient {
  return createClient(supabaseUrl!, supabaseServiceRoleKey!, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
  });
}

/**
 * Creates a Supabase client using the user's JWT.
 * Use this to perform actions on behalf of a user while respecting RLS.
 */
export function createUserClient(jwt: string): SupabaseClient {
  return createClient(supabaseUrl!, Deno.env.get("SUPABASE_ANON_KEY") || "", {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
    global: {
      headers: {
        Authorization: `Bearer ${jwt}`,
      },
    },
  });
}
