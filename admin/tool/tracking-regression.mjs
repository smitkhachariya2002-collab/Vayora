import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import ts from 'typescript';
function load(name) {
 let consent=true, settings=null; const calls=[], scripts=[],effects=[];
 const window={};
 const context={window,console,Date,Set,URLSearchParams,crypto:{randomUUID:()=> 'test'},location:{search:'',origin:'https://example.test',pathname:'/'},sessionStorage:{getItem:()=>null,setItem(){}},document:{cookie:'',createElement:()=>({}),head:{appendChild:s=>scripts.push(s)}},fetch:async()=>({}),process:{env:{}},setInterval:fn=>{effects.push(fn);return 1},clearInterval(){},exports:{},require:id=>id==='react'?{useEffect:fn=>fn()}:id==='next/navigation'?{usePathname:()=>'/'}:id.includes('PrivacyChoices')?{readWebChoices:()=>({google:consent}),hasAdvertisingConsent:()=>consent}:{supabaseBrowser:()=>({rpc:async()=>({data:settings})})}};
 window.addEventListener=()=>{};window.removeEventListener=()=>{};
 const source=readFileSync(new URL('../src/components/'+name+'.tsx',import.meta.url),'utf8');
 vm.runInNewContext(ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020,jsx:ts.JsxEmit.ReactJSX}}).outputText,context);
 return {api:context.exports,window,scripts,effects,calls,setConsent:v=>consent=v,setSettings:v=>settings=v};
}
const config={web_enabled:true,web_method:'direct',conversion_id:'AW-12345',download_label:'test'};
const g=load('GoogleTags');g.setSettings(config);g.setConsent(false);
assert.equal(await g.api.loadGoogle(),null);assert.equal(g.scripts.length,0);
g.setConsent(true);await g.api.trackGoogleDownload();assert.equal(g.scripts.length,1);
assert.equal(Object.prototype.toString.call(g.window.dataLayer[0]),'[object Arguments]');
assert.equal(g.window.dataLayer.at(-1)[0],'event');
g.window.__vayoraGoogle.at=0;g.setSettings({...config,conversion_id:'AW-67890'});
assert.equal(await g.api.loadGoogle(),null);const before=g.window.dataLayer.length;
await g.api.trackGoogleDownload();await g.api.trackGoogleDownload();assert.equal(g.window.dataLayer.length,before,'cached changed destination must not send');
const bad=load('GoogleTags');bad.setSettings({...config,conversion_id:'bad'});assert.equal(await bad.api.loadGoogle(),null);assert.equal(await bad.api.loadGoogle(),null);assert.equal(bad.scripts.length,0);
const m=load('MetaPixel');m.setSettings({pixel_id:'123456789'});await m.api.loadPixel();m.window.__vayoraPixel.at=0;await m.api.loadPixel();
assert.equal(m.window.fbq.queue.filter(x=>x[0]==='init').length,1,'refresh must not reinitialize pixel');
m.window.__vayoraPixel.at=0;m.setSettings(null);await m.api.loadPixel();m.window.__vayoraPixel.at=0;m.setSettings({pixel_id:'123456789'});await m.api.loadPixel();
assert.equal(m.window.fbq.queue.filter(x=>x[0]==='init').length,1,'re-enable must not duplicate init');
console.log('Tracking regression checks passed: consent, command format, destination changes, invalid settings, Meta refresh/re-enable.');
