import {chromium} from 'playwright';
import assert from 'node:assert/strict';
import {mkdir} from 'node:fs/promises';
const root='http://localhost:3000';
await mkdir('shots',{recursive:true});
const browser=await chromium.launch();
const report=[];
for(const width of [390,1280]){
 const context=await browser.newContext({viewport:{width,height:900}});const page=await context.newPage();
 const tracking=[];page.on('request',r=>{if(/connect\.facebook|facebook\.com\/tr|googletagmanager\.com|google-analytics\.com/.test(r.url()))tracking.push(r.url());});
 for(const path of ['/','/d','/privacy','/terms','/refund','/delete-account','/community-guidelines','/report-content','/workspace/login']){
  const response=await page.goto(root+path,{waitUntil:'networkidle'});assert.equal(response.status(),200,path);
  assert.equal(await page.locator('body').evaluate(el=>el.scrollWidth>innerWidth+1),false,'horizontal overflow '+path+' '+width);
  await page.screenshot({path:`shots/${width}_${path.replaceAll('/','_')||'home'}.png`,fullPage:true});
 }
 const identity=await (await context.request.get(root+'/.well-known/assetlinks.json')).json();
 assert.equal(identity.length,1);assert.equal(identity[0].target.package_name,'com.vayora.app');
 assert.match(identity[0].target.sha256_cert_fingerprints[0],/^([A-F0-9]{2}:){31}[A-F0-9]{2}$/);
 assert.equal(tracking.length,0,'No optional provider request before consent');
 await page.goto(root+'/');await page.getByRole('button',{name:'Essential only',exact:true}).click();
 assert.equal(await page.locator('[aria-labelledby="privacy-title"]').count(),0);
 await page.reload();assert.equal(await page.locator('[aria-labelledby="privacy-title"]').count(),0,'choice persists');
 await page.getByRole('button',{name:'Privacy choices',exact:true}).click();
 assert.equal(await page.getByLabel('Meta advertising measurement',{exact:true}).isChecked(),false);
 assert.equal(await page.getByLabel('Google advertising measurement',{exact:true}).isChecked(),false);
 await page.getByRole('button',{name:'Essential only',exact:true}).click();
 await page.goto(root+'/d');const organic=await page.getByRole('link',{name:'Download APK',exact:true}).getAttribute('href');assert.match(organic,/\/Vayora\.apk$/);
 await page.goto(root+'/d?gclid=smoke-test');await page.waitForTimeout(250);const ads=await page.getByRole('link',{name:'Download APK',exact:true}).getAttribute('href');assert.match(ads,/\/Vayora-ads\.apk$/);
 assert.equal(tracking.length,0,'Download variant does not require optional tracking');
 for(const path of ['/admin','/admin/login'])assert.equal((await page.goto(root+path)).status(),404,'old admin route stays closed');
 report.push({width,passed:true,providerRequestsBeforeConsent:tracking.length});await context.close();
}
await browser.close();console.log(JSON.stringify(report));
