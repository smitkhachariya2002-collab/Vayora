import { readdir, readFile } from 'node:fs/promises';
import path from 'node:path';
const bad = /\uFFFD|\u00C3[\u0080-\u00BF]|\u00C2[\u0080-\u00BF]|\u00E2[\u0080-\u00BF\u20AC\u2020\u2122]/u;
async function scan(dir) {
 let errors=0;
 for (const entry of await readdir(dir,{withFileTypes:true})) {
  const file=path.join(dir,entry.name);
  if(entry.isDirectory()) errors+=await scan(file);
  else if(/\.(?:tsx?|css|json)$/.test(file)) {
   const bytes=await readFile(file); let text;
   try {text=new TextDecoder('utf-8',{fatal:true}).decode(bytes);} catch {console.error(file+': invalid UTF-8');errors++;continue;}
   for(const [index,line] of text.split('\n').entries())if(bad.test(line)){console.error(file+':'+(index+1)+': corrupted text');errors++;}
  }
 }
 return errors;
}
const errors=await scan('src');
if(errors)process.exit(1);
console.log('PASS UTF-8 and text encoding across all admin/public source files');
