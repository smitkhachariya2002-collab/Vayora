import {assertEquals,assertRejects,assertMatch} from 'jsr:@std/assert@1.0.14';
import {cleanupReason,signedCdnUrl,tusAuthorization,sha256} from './bunny.ts';
import {cutPreview} from './bunny-preview.ts';
Deno.test('TUS signature binds library, video, expiry and server secret',async()=>{
 const expiry=Math.floor(Date.now()/1000)+600,id='12345678-1234-1234-1234-123456789012';
 const h=await tusAuthorization('42','private',id,expiry);
 assertEquals(h.AuthorizationSignature,await sha256('42private'+expiry+id));
 await assertRejects(()=>tusAuthorization('42','private',id,1));
});
Deno.test('Signed paths reject traversal and mismatched directory scopes',async()=>{
 await assertRejects(()=>signedCdnUrl('zone.b-cdn.net','/a/../secret','key',123));
 await assertRejects(()=>signedCdnUrl('zone.b-cdn.net','/other/main.m3u8','key',123,'/a/'));
 await assertRejects(()=>signedCdnUrl('zone.b-cdn.net','/a/%2e%2e/secret','key',123));
 assertMatch(await signedCdnUrl('zone.b-cdn.net','/files/backup..txt','key',123),/backup\.\.txt\?token=/);
 assertMatch(await signedCdnUrl('zone.b-cdn.net','/video/playlist.m3u8','key',123,'/video/'),/bcdn_token=HS256-[A-Za-z0-9_-]+&expires=123&token_path=%2Fvideo%2F/);
});
Deno.test('Preview contains at most two minutes and no reusable full-video token',async()=>{
 const lines=['#EXTM3U','#EXT-X-TARGETDURATION:7'];for(let i=0;i<25;i++)lines.push('#EXTINF:7,',`segment${i}.ts`);
 const signed:string[]=[];const result=await cutPreview(lines.join('\n'),async p=>{signed.push(p);return `https://preview.test/segment?part=${p}&signature=individual`;});
 assertEquals(signed.length,17);assertEquals(result.includes('segment17.ts'),false);assertEquals(result.includes('bcdn_token'),false);assertEquals(result.endsWith('#EXT-X-ENDLIST\n'),true);
});
Deno.test('Byte range files cannot escape the preview limit through initialization maps',async()=>{
 await assertRejects(()=>cutPreview('#EXTM3U\n#EXT-X-MAP:URI="full.mp4",BYTERANGE="100@0"\n#EXTINF:10,\nfull.mp4',async p=>p));
 await assertRejects(()=>cutPreview('#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=200\nfull.m3u8',async p=>p));
});
Deno.test('Cleanup excludes attached, recent and undated videos',()=>{
 const now=Date.parse('2026-11-24T12:00:00Z');
 assertEquals(cleanupReason({dateUploaded:'2026-11-24T11:00:00Z'},false,now),null);
 assertEquals(cleanupReason({dateUploaded:'2026-11-20T11:00:00Z'},true,now),null);
 assertEquals(cleanupReason({},false,now),null);
 assertEquals(cleanupReason({dateUploaded:'2026-11-20T11:00:00Z',status:5},false,now),'Processing failed');
});

Deno.test('Browser preflight permits the Supabase client header without authenticating an operation',async()=>{
 const {handleBunny}=await import('./bunny-handler.ts');
 const response=await handleBunny(new Request('https://example.test',{method:'OPTIONS'}),'bunny-status');
 assertEquals(response.status,200);assertEquals(response.headers.get('Access-Control-Allow-Headers')?.includes('x-client-info'),true);
});
