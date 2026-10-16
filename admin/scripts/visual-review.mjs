import {chromium} from "@playwright/test";
import {createClient} from "@supabase/supabase-js";
import {execFileSync,spawn} from "node:child_process";
import {randomUUID} from "node:crypto";
import {mkdir,writeFile} from "node:fs/promises";
const status=JSON.parse(execFileSync("supabase",["status","-o","json"],{cwd:"..",encoding:"utf8",stdio:["ignore","pipe","ignore"]}));
const api=status.API_URL,anon=status.ANON_KEY,service=status.SERVICE_ROLE_KEY;
if(!api||!anon||!service)throw new Error("Disposable Supabase not ready");
const admin=createClient(api,service),password=randomUUID()+"Aa1!",email="visual-owner@example.test";
const {data:{user},error}=await admin.auth.admin.createUser({email,password,email_confirm:true});if(error)throw error;
await admin.from("admins").insert({user_id:user.id,role:"owner"});
const client=createClient(api,anon);await client.auth.signInWithPassword({email,password});
const channelId=randomUUID(),postId=randomUUID();
const channel=await client.from("channels").insert({id:channelId,name:"Stories across India",description:"Independent voices and everyday inspiration.",category:"Lifestyle",created_by:user.id,audience:"all",status:"active"});if(channel.error)throw channel.error;
const post=await client.from("posts").insert({id:postId,channel_id:channelId,title:"A fresh perspective",description:"A new story from our community.",audience:"all",status:"published",created_by:user.id});if(post.error)throw post.error;
await client.from("post_items").insert({post_id:postId,media_key:user.id+"/"+postId+"/fixture",mime:"video/mp4",is_premium:true,duration_s:120});
const member=await admin.auth.admin.createUser({email:"creator@example.test",password:randomUUID()+"Bb2!",email_confirm:true});
if(member.error)throw member.error;
await admin.from("support_requests").insert({user_id:member.data.user.id,email:"creator@example.test",kind:"content",reason:"Review this content",details:"Example content report for the review screen.",post_id:postId});
await client.rpc("set_ads_access",{user_id:member.data.user.id,status:"pending"});
await admin.from("channels").insert({name:"Community channel request",description:"A creator is waiting for review.",category:"Community",created_by:member.data.user.id,audience:"organic"});
await client.rpc("record_install",{install_id:randomUUID(),referrer_status:"provided",raw_referrer:"utm_source=meta&utm_campaign=India_creators",install_secret:randomUUID()+randomUUID()});
const {data:fixturePlans}=await admin.from("plans").select("id,duration_days,price_inr").limit(1);
if(fixturePlans?.[0]){const plan=fixturePlans[0];await client.rpc("grant_premium",{user_id:member.data.user.id,plan_id:plan.id});await admin.from("payment_orders").insert({user_id:member.data.user.id,plan_id:plan.id,duration_days:plan.duration_days,amount_paise:Math.round(plan.price_inr*100),reference:"VISUAL_PENDING_ORDER",status:"pending"});}

const content=await admin.auth.admin.createUser({email:"editor@example.test",password,email_confirm:true});if(content.error)throw content.error;
await admin.from("admins").insert({user_id:content.data.user.id,role:"content"});
await admin.from("admin_channel_access").insert({user_id:content.data.user.id,channel_id:channelId});
const env={...process.env,NEXT_PUBLIC_SUPABASE_URL:api,NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY:anon};
const servers=[spawn("npm",["run","dev","--","--port","3000"],{env,stdio:"ignore"}),spawn("npm",["run","dev","--","--port","3001"],{env,cwd:"../baseline/admin",stdio:"ignore"})];
const browser=await chromium.launch();await mkdir("visual-artifacts",{recursive:true});const report=[];
async function ready(url){for(let i=0;i<60;i++){try{if((await fetch(url)).ok)return}catch{}await new Promise(r=>setTimeout(r,1000))}throw new Error("Server unavailable")}
try{
 await Promise.all([ready("http://localhost:3000/login"),ready("http://localhost:3001/login")]);
 for(const [label,width] of [["desktop",1280],["mobile",375]]){
 for(const [stage,port] of [["before",3001],["after",3000]]){
 const context=await browser.newContext({viewport:{width,height:900}}),page=await context.newPage(),origin="http://localhost:"+port;
 await page.goto(origin+"/login");await page.screenshot({path:"visual-artifacts/"+stage+"-login-"+label+".png",fullPage:true});
 await page.locator('input[name="email"]').fill(email);await page.locator('input[name="password"]').fill(password);await page.getByRole("button",{name:stage==="before"?"Continue":"Sign in",exact:true}).click();await page.waitForURL(url=>!url.pathname.startsWith("/login"));
 const sections=["dashboard","channels","posts","approvals","payments","meta","users","requests","plans","admins","channels-new","channels-edit","posts-new","posts-edit"];
 for(const section of sections){let path=section==="dashboard"?"":section.replace("-new","/new").replace("-edit","/"+(section.startsWith("posts")?postId:channelId));if(stage==="before")path="/dashboard"+(path?"/"+path:"");else path="/"+path;
 const response=await page.goto(origin+path);await page.waitForLoadState("networkidle");const overflow=await page.evaluate(()=>document.documentElement.scrollWidth>window.innerWidth);
 if(stage==="after"&&(response.status()>=400||overflow||await page.getByText("Application error",{exact:false}).count()||await page.getByRole("heading",{name:"This page could not load",exact:true}).count()||await page.getByRole("alert").count()))throw new Error(stage+" "+section+" "+label+" status="+response.status()+" overflow="+overflow);
 report.push({stage,section,width,status:response.status(),overflow});await page.screenshot({path:"visual-artifacts/"+stage+"-"+section+"-"+label+".png",fullPage:true});
 }
 await context.close();
 }
 }
 // Verify create/save/delete feedback through real server actions.
 const ownerContext=await browser.newContext(),ownerPage=await ownerContext.newPage();
 await ownerPage.goto("http://localhost:3000/login");await ownerPage.locator('input[name="email"]').fill(email);await ownerPage.locator('input[name="password"]').fill(password);await ownerPage.getByRole("button",{name:"Sign in",exact:true}).click();await ownerPage.waitForURL("http://localhost:3000/");
 await ownerPage.goto("http://localhost:3000/channels/new");await ownerPage.getByLabel("Channel name",{exact:true}).fill("Created through the browser");await ownerPage.getByRole("button",{name:"Create channel",exact:true}).click();await ownerPage.waitForURL(url=>url.pathname==="/channels"&&url.searchParams.has("ok"));await ownerPage.getByRole("status").filter({hasText:"Changes saved"}).waitFor();
 await ownerPage.goto("http://localhost:3000/posts/new");await ownerPage.getByLabel("Title",{exact:true}).fill("Browser-created draft");await ownerPage.getByLabel("Channel",{exact:true}).selectOption(channelId);await ownerPage.getByRole("button",{name:"Create post",exact:true}).click();await ownerPage.waitForURL(url=>url.pathname.startsWith("/posts/")&&url.searchParams.has("ok"));await ownerPage.getByText("No media yet. Add a video or image below.",{exact:true}).waitFor();
 ownerPage.once("dialog",dialog=>dialog.accept());await ownerPage.getByRole("button",{name:"Delete post",exact:true}).click();await ownerPage.waitForURL(url=>url.pathname==="/posts"&&url.searchParams.has("ok"));await ownerContext.close();
 // Content admins must not see owner navigation or enter owner pages.
 const context=await browser.newContext(),page=await context.newPage();await page.goto("http://localhost:3000/login");await page.locator('input[name="email"]').fill("editor@example.test");await page.locator('input[name="password"]').fill(password);await page.getByRole("button",{name:"Sign in",exact:true}).click();await page.waitForURL("http://localhost:3000/");
 if(await page.getByRole("navigation",{name:"Main navigation"}).getByRole("link",{name:"Payments",exact:true}).count())throw new Error("Content admin sees owner navigation");
 await page.goto("http://localhost:3000/payments");await page.waitForURL(url=>url.pathname==="/");await page.getByRole("alert").filter({hasText:"only available to the owner"}).waitFor();
 // Public invocation must not delete an account.
 const anonymousInvite=await fetch(api+"/functions/v1/admin-invite",{method:"POST",headers:{"Content-Type":"application/json"},body:"{}"});if(anonymousInvite.status!==401)throw new Error("Invite endpoint must reject unauthenticated callers");
 const unauthorized=await fetch(api+"/functions/v1/admin-delete-account",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({request_id:randomUUID(),confirm:true})});
 if(unauthorized.status!==401)throw new Error("Deletion endpoint must reject unauthenticated callers");
 await context.close();await writeFile("visual-artifacts/report.json",JSON.stringify(report,null,2));
}finally{await browser.close();for(const s of servers)s.kill("SIGTERM")}
