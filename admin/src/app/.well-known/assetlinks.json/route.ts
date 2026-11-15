import { NextResponse } from "next/server";

export const dynamic = "force-dynamic";

export function GET() {
  const fps = (process.env.ANDROID_SIGNING_SHA256 || "").split(",").map((s) => s.trim()).filter((s) => /^([A-Fa-f0-9]{2}:){31}[A-Fa-f0-9]{2}$/.test(s));
  const body = (fps.length ? ["com.vayora.app"] : []).map((pkg) => ({
    relation: ["delegate_permission/common.handle_all_urls"],
    target: { namespace: "android_app", package_name: pkg, sha256_cert_fingerprints: fps },
  }));
  return NextResponse.json(body);
}
