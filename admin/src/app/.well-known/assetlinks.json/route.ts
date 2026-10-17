export async function GET(){
 const fingerprints=(process.env.ANDROID_SIGNING_SHA256??"").split(",").map(s=>s.trim().toUpperCase()).filter(s=>/^([0-9A-F]{2}:){31}[0-9A-F]{2}$/.test(s));
 if(!fingerprints.length)return Response.json([],{headers:{"Cache-Control":"public, max-age=300"}});
 return Response.json([{relation:["delegate_permission/common.handle_all_urls"],target:{namespace:"android_app",package_name:"com.vayora.app",sha256_cert_fingerprints:fingerprints}}],{headers:{"Cache-Control":"public, max-age=3600"}});
}
