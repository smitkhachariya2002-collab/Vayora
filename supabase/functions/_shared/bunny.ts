/** Bunny protocol helpers. Credentials are supplied by the Edge environment only. */
export class BunnyNotConfigured extends Error {
  constructor(public missing: string[]) { super(`Bunny setup incomplete: ${missing.join(', ')}`); }
}
export function requiredEnv(names: string[]) {
  const missing = names.filter(name => !Deno.env.get(name)?.trim());
  if (missing.length) throw new BunnyNotConfigured(missing);
  return Object.fromEntries(names.map(name => [name, Deno.env.get(name)!.trim()]));
}
export const videoId = (id: unknown): string => {
  if (typeof id !== 'string' || !/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(id)) throw new Error('Invalid video ID');
  return id;
};
export function cdnOrigin(host: string): string {
  const u = new URL(host.startsWith('https://') ? host : `https://${host}`);
  if (u.protocol !== 'https:' || u.username || u.password || u.port || u.pathname !== '/' || u.search || u.hash || !u.hostname.endsWith('.b-cdn.net')) throw new Error('Use the Bunny .b-cdn.net hostname');
  return u.origin;
}
const base64url = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes)).replaceAll('+','-').replaceAll('/','_').replace(/=+$/,'');
export async function sha256(input: string) {
  return [...new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(input)))].map(x=>x.toString(16).padStart(2,'0')).join('');
}
export async function tusAuthorization(libraryId: string, apiKey: string, id: string, expires: number) {
  if (!/^\d+$/.test(libraryId) || !Number.isSafeInteger(expires) || expires <= Math.floor(Date.now()/1000)) throw new Error('Invalid upload authorization');
  return {AuthorizationSignature:await sha256(libraryId+apiKey+expires+videoId(id)),AuthorizationExpire:String(expires),LibraryId:libraryId,VideoId:id};
}
export async function signedCdnUrl(origin: string, path: string, key: string, expires: number, directory?: string) {
  if (!path.startsWith('/') || path.includes('..') || /[?#\\\x00-\x20]/.test(path)) throw new Error('Invalid media path');
  if (directory && (!directory.endsWith('/') || !path.startsWith(directory) || directory.includes('..'))) throw new Error('Invalid token scope');
  const params = directory ? `token_path=${directory}` : '';
  const signing = (directory ?? path)+expires+params;
  const cryptoKey = await crypto.subtle.importKey('raw',new TextEncoder().encode(key),{name:'HMAC',hash:'SHA-256'},false,['sign']);
  const token = 'HS256-'+base64url(new Uint8Array(await crypto.subtle.sign('HMAC',cryptoKey,new TextEncoder().encode(signing))));
  const query = `token=${token}&expires=${expires}`+(directory?`&token_path=${encodeURIComponent(directory)}`:'');
  return directory ? `${cdnOrigin(origin)}/bcdn_${query}${path}` : `${cdnOrigin(origin)}${path}?${query}`;
}
export async function streamApi(path: string, init: RequestInit = {}) {
  const env=requiredEnv(['BUNNY_STREAM_LIBRARY_ID','BUNNY_STREAM_API_KEY']);
  if(!/^\d+$/.test(env.BUNNY_STREAM_LIBRARY_ID) || !/^\/videos(?:\/[a-f0-9-]+)?(?:\?page=\d+&itemsPerPage=\d+)?$/.test(path)) throw new Error('Invalid Stream request');
  const r=await fetch(`https://video.bunnycdn.com/library/${env.BUNNY_STREAM_LIBRARY_ID}${path}`,{...init,headers:{'AccessKey':env.BUNNY_STREAM_API_KEY,'Content-Type':'application/json',...init.headers},signal:AbortSignal.timeout(20000)});
  if(init.method==='DELETE'&&r.status===404)return {};
  if(!r.ok) throw new Error(`Bunny Stream request failed (${r.status})`);
  return r.status===204?{}:await r.json();
}
export function cleanupReason(v:{dateUploaded?:string;status?:number},referenced:boolean,now=Date.now()) {
  const date=Date.parse(v.dateUploaded??'');
  if(referenced || !Number.isFinite(date) || now-date<86400000) return null;
  if(v.status===5) return 'Processing failed';
  if(v.status===0 || v.status===1) return 'Upload never finished';
  if(v.status===2 || v.status===3) return 'Stuck in processing';
  return 'Not used by any post';
}
