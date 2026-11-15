import { createServerClient, type CookieOptions } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

// Refreshes the session cookie and keeps signed-out visitors out of /admin.
// Real authorisation is enforced in Postgres (is_admin / is_owner inside every RPC).
export async function proxy(req: NextRequest) {
  let res = NextResponse.next({ request: req });
  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
    {
      cookies: {
        getAll: () => req.cookies.getAll(),
        setAll: (list: { name: string; value: string; options: CookieOptions }[]) => {
          list.forEach(({ name, value }) => req.cookies.set(name, value));
          res = NextResponse.next({ request: req });
          list.forEach(({ name, value, options }) => res.cookies.set(name, value, options));
        },
      },
    },
  );
  const { data } = await supabase.auth.getUser();
  const path = req.nextUrl.pathname;
  if (path.startsWith("/workspace") && path !== "/workspace/login" && !data.user) {
    const url = req.nextUrl.clone();
    url.pathname = "/workspace/login";
    return NextResponse.redirect(url);
  }
  return res;
}

export const config = { matcher: ["/workspace/:path*"] };
