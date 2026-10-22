import { createClient, type User } from "npm:@supabase/supabase-js@2";

type AuthenticationResult =
  | { user: User; error: null }
  | { user: null; error: string };

export async function authenticateRequest(
  request: Request,
): Promise<AuthenticationResult> {
  const authorization = request.headers.get("Authorization");

  if (!authorization?.startsWith("Bearer ")) {
    return { user: null, error: "Missing authorization token" };
  }

  const accessToken = authorization.slice("Bearer ".length).trim();
  if (!accessToken) {
    return { user: null, error: "Missing authorization token" };
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");

  if (!supabaseUrl || !supabaseAnonKey) {
    console.error("Supabase authentication environment variables are missing");
    return { user: null, error: "Authentication is unavailable" };
  }

  const supabase = createClient(supabaseUrl, supabaseAnonKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });

  const {
    data: { user },
    error,
  } = await supabase.auth.getUser(accessToken);

  if (error || !user) {
    return { user: null, error: "Invalid or expired authorization token" };
  }

  return { user, error: null };
}

