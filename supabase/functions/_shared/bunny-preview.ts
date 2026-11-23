/** Build an independent, bounded media playlist. Never disclose the main directory token. */
export async function cutPreview(playlist:string,sign:(path:string)=>Promise<string>,limit=120):Promise<string> {
 if(playlist.includes('#EXT-X-STREAM-INF') || playlist.includes('BYTERANGE')) throw new Error('Preview requires a segment-based media playlist');
 const output=['#EXTM3U','#EXT-X-PLAYLIST-TYPE:VOD'];let elapsed=0,duration:number|null=null,pending:string[]=[];
 for(const line of playlist.split(/\r?\n/).map(x=>x.trim())) {
  if(!line||line==='#EXTM3U'||line.startsWith('#EXT-X-PLAYLIST-TYPE')||line==='#EXT-X-ENDLIST') continue;
  if(line.startsWith('#EXTINF:')) {duration=Number(line.slice(8).split(',')[0]);pending.push(line);continue;}
  if(line.startsWith('#')) {
   if(line.startsWith('#EXT-X-KEY:') || line.startsWith('#EXT-X-MAP:')) {
    const m=line.match(/URI="([^"]+)"/);if(!m)throw new Error('Invalid preview resource');
    output.push(line.replace(m[1],await sign(m[1])));
   } else if(/^#EXT-X-(VERSION|TARGETDURATION|MEDIA-SEQUENCE|DISCONTINUITY|DISCONTINUITY-SEQUENCE|INDEPENDENT-SEGMENTS)(?::|$)/.test(line)){if(duration===null)output.push(line);else pending.push(line);}
   continue;
  }
  if(duration===null||!Number.isFinite(duration)||duration<=0) throw new Error('Invalid HLS segment');
  if(elapsed+duration>limit) break;
  output.push(...pending,await sign(line));elapsed+=duration;duration=null;pending=[];
 }
 if(elapsed===0) throw new Error('Preview segments are not available');
 output.push('#EXT-X-ENDLIST');return output.join('\n')+'\n';
}
