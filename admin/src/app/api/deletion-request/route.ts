import { NextResponse } from "next/server";
export async function POST(request: Request) {
  const origin = request.headers.get("origin");
  if (origin && origin !== new URL(request.url).origin) return NextResponse.json({error:"Invalid request origin."},{status:403});
  if (Number(request.headers.get("content-length") || 0) > 8192) return NextResponse.json({error:"Request too large."},{status:413});
  try {
    const raw = await request.text();
    if (raw.length > 4096) return NextResponse.json({error:"Request too large."},{status:413});
    const body = JSON.parse(raw);
    const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
    if (!url || !key) throw new Error("Request service unavailable");
    const response = await fetch(url + "/functions/v1/deletion-request", {
      method:"POST", headers:{"Content-Type":"application/json",apikey:key},
      body:JSON.stringify(body), cache:"no-store", signal:AbortSignal.timeout(15000),
    });
    const data = await response.json();
    return NextResponse.json(data,{status:response.status,headers:{"Cache-Control":"no-store"}});
  } catch {
    return NextResponse.json({error:"Request could not be recorded. Please email help.vayora@gmail.com."},{status:503});
  }
}
