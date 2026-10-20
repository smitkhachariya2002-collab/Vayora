const validFingerprints=(value:string)=>value.split(",").map(s=>s.trim().toUpperCase()).filter(s=>/^([0-9A-F]{2}:){31}[0-9A-F]{2}$/.test(s));
export async function GET(){
 const direct=validFingerprints(process.env.ANDROID_SIGNING_SHA256??"");
 const play=validFingerprints(process.env.ANDROID_PLAY_SIGNING_SHA256??process.env.ANDROID_SIGNING_SHA256??"");
 const entries=[["com.vayora.app",direct],["com.vayora.play",play]] as const;
 return Response.json(entries.filter(([,certs])=>certs.length).map(([id,certs])=>({
   relation:["delegate_permission/common.handle_all_urls"],
   target:{namespace:"android_app",package_name:id,sha256_cert_fingerprints:certs},
 })),{headers:{"Cache-Control":"public, max-age=300"}});
}
