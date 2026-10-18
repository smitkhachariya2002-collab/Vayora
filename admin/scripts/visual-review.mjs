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
const reviewed=await client.rpc("review_channel",{channel_id:channelId,approve:true,audience:"all"});if(reviewed.error)throw reviewed.error;
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
 if(stage==="after"&&(response.status()>=400||overflow||await page.getByText("Application error",{exact:false}).count()||await page.getByRole("heading",{name:"This page could not load",exact:true}).count()||await page.locator("main [role=alert]").count()))throw new Error(stage+" "+section+" "+label+" status="+response.status()+" overflow="+overflow);
 report.push({stage,section,width,status:response.status(),overflow});await page.screenshot({path:"visual-artifacts/"+stage+"-"+section+"-"+label+".png",fullPage:true});
 }
 await context.close();
 }
 }
 // Verify create/save/delete feedback through real server actions.
 const ownerContext=await browser.newContext(),ownerPage=await ownerContext.newPage();
 await ownerPage.goto("http://localhost:3000/login");await ownerPage.locator('input[name="email"]').fill(email);await ownerPage.locator('input[name="password"]').fill(password);await ownerPage.getByRole("button",{name:"Sign in",exact:true}).click();await ownerPage.waitForURL("http://localhost:3000/");


 // Review through the real server action; verify all atomic database effects.
 await ownerPage.goto("http://localhost:3000/channels");
 const requestCard=ownerPage.locator('[data-testid^="channel-request-"]').filter({hasText:"Community channel request"});
 await requestCard.getByText("creator@example.test",{exact:false}).waitFor();
 await requestCard.locator('select[name="audience"]').selectOption("organic");
 await ownerPage.screenshot({path:"visual-artifacts/channel-request-before-desktop.png",fullPage:true});
 await requestCard.getByRole("button",{name:"Approve",exact:true}).click();
 await ownerPage.waitForURL(url=>url.pathname==="/channels"&&url.searchParams.has("ok"));
 const {data:approvedChannel,error:reviewError}=await admin.from("channels").select("*").eq("name","Community channel request").single();
 if(reviewError||approvedChannel.review_status!=="approved"||approvedChannel.status!=="published"||approvedChannel.audience!=="organic"||!approvedChannel.reviewed_at||approvedChannel.reviewed_by!==user.id)throw new Error("Approval did not publish chosen audience and reviewer");
 const {data:creatorMembership}=await admin.from("channel_members").select("*").eq("channel_id",approvedChannel.id).eq("user_id",member.data.user.id);
 if(creatorMembership?.length!==1)throw new Error("Approval did not auto-join creator");
 await ownerPage.screenshot({path:"visual-artifacts/channel-request-approved-desktop.png",fullPage:true});
 const {error:rejectSeed}=await admin.from("channels").insert({name:"Reject this request",description:"Rejected fixture",created_by:member.data.user.id});if(rejectSeed)throw rejectSeed;
 await ownerPage.reload();
 const rejectCard=ownerPage.locator('[data-testid^="channel-request-"]').filter({hasText:"Reject this request"});
 ownerPage.once("dialog",dialog=>dialog.accept());
 await rejectCard.getByRole("button",{name:"Reject",exact:true}).click();
 await ownerPage.waitForURL(url=>url.pathname==="/channels"&&url.searchParams.has("ok"));
 const {data:rejectedChannel}=await admin.from("channels").select("review_status,status").eq("name","Reject this request").single();
 if(rejectedChannel?.review_status!=="rejected"||rejectedChannel?.status!=="draft")throw new Error("Reject must keep draft");
 report.push({check:"channel-review-audience-reviewer-auto-join-reject",passed:true});
 // Real browser plan edits + real Postgres Changes delivery, with no production data.
 await ownerPage.goto("http://localhost:3000/plans");
 const trialForm=ownerPage.locator("form").filter({has:ownerPage.getByRole("heading",{name:"Trial",exact:true})});
 await trialForm.locator('input[name="code"]').evaluate(el=>{if(!el.readOnly)throw new Error("Code must be readonly")});
 await ownerPage.screenshot({path:"visual-artifacts/plans-edit-desktop.png",fullPage:true});
 const guest=createClient(api,anon);const {error:guestError}=await guest.auth.signInAnonymously();if(guestError)throw guestError;
 let revisionEvents=0,planEvents=0;
 const live=guest.channel("plans-browser-review").on("postgres_changes",{event:"*",schema:"public",table:"plans"},()=>planEvents++)
 .on("postgres_changes",{event:"*",schema:"public",table:"plan_catalog"},()=>revisionEvents++);
 await new Promise((resolve,reject)=>{
  const timeout=setTimeout(()=>reject(new Error("PostgreSQL realtime listener did not become ready")),20000);
  live.on("system",{},message=>{
   console.log("Realtime system",JSON.stringify(message));
   if(message.extension==="postgres_changes"&&message.status==="ok"){clearTimeout(timeout);resolve();}
   else if(message.status==="error"){clearTimeout(timeout);reject(new Error(message.message));}
  });
  live.subscribe((state,error)=>{
   console.log("Realtime state",state,error?.message??"");
   if(state==="CHANNEL_ERROR"||state==="TIMED_OUT"){clearTimeout(timeout);reject(new Error("Realtime channel failed"));}
  });
 });
 await trialForm.getByLabel("Price (₹)",{exact:true}).fill("79");
 await trialForm.getByLabel("Badge (optional)",{exact:true}).fill("Best value");
 ownerPage.once("dialog",dialog=>dialog.accept());
 await trialForm.getByRole("button",{name:"Save plan",exact:true}).click();
 await ownerPage.getByRole("status").filter({hasText:"Plan saved."}).waitFor();
 for(let i=0;i<100&&(!planEvents||!revisionEvents);i++)await new Promise(r=>setTimeout(r,100));
 if(!planEvents||!revisionEvents)throw new Error("Real plan/catalog realtime events missing: plans="+planEvents+" revisions="+revisionEvents);
 const {data:changed}=await guest.from("plans").select("price_inr,badge").eq("code","trial").single();
 if(changed?.price_inr!==79||changed.badge!=="Best value")throw new Error("Live catalog edit not readable");
 const revisionBeforeHide=revisionEvents;
 await trialForm.getByLabel("Show in app",{exact:true}).uncheck();
 ownerPage.once("dialog",dialog=>dialog.accept());
 await trialForm.getByRole("button",{name:"Save plan",exact:true}).click();
 for(let i=0;i<100&&revisionEvents===revisionBeforeHide;i++)await new Promise(r=>setTimeout(r,100));
 if(revisionEvents===revisionBeforeHide)throw new Error("Hide invalidation missing");
 const {data:hidden}=await guest.from("plans").select("id").eq("code","trial");
 if(hidden?.length)throw new Error("Hidden plan leaked through guest RLS");
 await guest.removeChannel(live);await guest.auth.signOut();
 await ownerPage.goto("http://localhost:3000/plans?new=1");
 const addForm=ownerPage.locator("form").filter({has:ownerPage.getByRole("heading",{name:"New plan",exact:true})});
 await addForm.getByLabel("Name",{exact:true}).fill("Weekend");
 await addForm.locator('input[name="code"]').fill("weekend");
 await addForm.getByLabel("Price (₹)",{exact:true}).fill("99");
 await addForm.locator('input[name="duration_days"]').fill("2");
 await addForm.locator('textarea[name="perks"]').fill("Full premium videos\n2 TB cloud storage\nDownload to your phone");
 await addForm.getByLabel("Badge (optional)",{exact:true}).fill("New");
 await addForm.getByLabel("Order",{exact:true}).fill("5");
 await ownerPage.evaluate(()=>{document.activeElement?.blur();window.scrollTo(0,0)});
 await ownerPage.screenshot({path:"visual-artifacts/plans-add-desktop.png",fullPage:true});
 await addForm.getByRole("button",{name:"Save plan",exact:true}).click();
 await addForm.getByRole("status").filter({hasText:"Plan saved."}).waitFor();
 const {data:createdPlan}=await client.from("plans").select("active,code").eq("code","weekend").single();
 if(createdPlan?.active!==false)throw new Error("Created plan must default inactive");
 report.push({check:"plan-edit-add-confirmation-and-real-realtime-price-hide",passed:true});
 await ownerPage.goto("http://localhost:3000/channels/new");await ownerPage.getByLabel("Channel name",{exact:true}).fill("Created through the browser");await ownerPage.getByRole("button",{name:"Create channel",exact:true}).click();await ownerPage.waitForURL(url=>url.pathname==="/channels"&&url.searchParams.has("ok"));await ownerPage.getByRole("status").filter({hasText:"Changes saved"}).waitFor();
 const {data:panelChannel}=await admin.from("channels").select("review_status,status").eq("name","Created through the browser").single();
 if(panelChannel?.review_status!=="approved"||panelChannel?.status!=="published")throw new Error("Admin panel creation must approve immediately");
 await ownerPage.goto("http://localhost:3000/posts/new");await ownerPage.getByLabel("Title",{exact:true}).fill("Browser-created draft");await ownerPage.locator('select[name="channel_id"]').selectOption(channelId);await ownerPage.getByRole("button",{name:"Create post",exact:true}).click();await ownerPage.waitForURL(url=>url.pathname.startsWith("/posts/")&&url.searchParams.has("ok"));await ownerPage.getByText("No media yet. Add a video or image below.",{exact:true}).waitFor();
 await ownerPage.waitForLoadState("networkidle");
 const image=await ownerPage.evaluate(()=>{const canvas=document.createElement("canvas");canvas.width=32;canvas.height=32;const ctx=canvas.getContext("2d");ctx.fillStyle="#b91c1c";ctx.fillRect(0,0,32,32);return canvas.toDataURL("image/png").split(",")[1]});
 await ownerPage.locator('input[name="main"]').setInputFiles({name:"fixture.png",mimeType:"image/png",buffer:Buffer.from(image,"base64")});
 await ownerPage.getByRole("button",{name:"Add media item",exact:true}).click();await ownerPage.getByText("Media 1",{exact:true}).waitFor();
 const createdPostId=new URL(ownerPage.url()).pathname.split("/").pop();const {data:savedMedia}=await admin.from("post_items").select("thumbnail_key").eq("post_id",createdPostId);if(!savedMedia?.[0]?.thumbnail_key)throw new Error("Generated thumbnail was not saved");report.push({check:"upload-and-generated-thumbnail",passed:true});
 ownerPage.once("dialog",dialog=>dialog.accept());await ownerPage.getByRole("button",{name:"Delete post",exact:true}).click();await ownerPage.waitForURL(url=>url.pathname==="/posts"&&url.searchParams.has("ok"));await ownerContext.close();
 // Content admins must not see owner navigation or enter owner pages.
 const context=await browser.newContext(),page=await context.newPage();await page.goto("http://localhost:3000/login");await page.locator('input[name="email"]').fill("editor@example.test");await page.locator('input[name="password"]').fill(password);await page.getByRole("button",{name:"Sign in",exact:true}).click();await page.waitForURL("http://localhost:3000/");
 if(await page.getByRole("navigation",{name:"Main navigation"}).getByRole("link",{name:"Payments",exact:true}).count())throw new Error("Content admin sees owner navigation");
 await page.goto("http://localhost:3000/payments");await page.waitForURL(url=>url.pathname==="/");await page.getByRole("alert").filter({hasText:"only available to the owner"}).waitFor();
 // Public invocation must not delete an account.
 const anonymousInvite=await fetch(api+"/functions/v1/admin-invite",{method:"POST",headers:{"Content-Type":"application/json"},body:"{}"});if(anonymousInvite.status!==401)throw new Error("Invite endpoint must reject unauthenticated callers");
 const unauthorized=await fetch(api+"/functions/v1/admin-delete-account",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({request_id:randomUUID(),confirm:true})});
 if(unauthorized.status!==401)throw new Error("Deletion endpoint must reject unauthenticated callers");
 await context.close();
 const request=await admin.from("support_requests").insert({user_id:member.data.user.id,email:"creator@example.test",kind:"deletion",reason:"Delete my fixture account"}).select("id").single();if(request.error)throw request.error;
 const contentClient=createClient(api,anon);await contentClient.auth.signInWithPassword({email:"editor@example.test",password});const {data:{session:contentSession}}=await contentClient.auth.getSession();
 const denied=await fetch(api+"/functions/v1/admin-delete-account",{method:"POST",headers:{"Content-Type":"application/json",Authorization:"Bearer "+contentSession.access_token},body:JSON.stringify({request_id:request.data.id,confirm:true})});if(denied.status!==403)throw new Error("Content admin deletion must be denied");
 const {data:{session:ownerSession}}=await client.auth.getSession();
 const removed=await fetch(api+"/functions/v1/admin-delete-account",{method:"POST",headers:{"Content-Type":"application/json",Authorization:"Bearer "+ownerSession.access_token},body:JSON.stringify({request_id:request.data.id,confirm:true})});if(!removed.ok)throw new Error("Owner requested deletion failed: "+removed.status);
 const deleted=await admin.auth.admin.getUserById(member.data.user.id);if(deleted.data.user)throw new Error("Requested account was not deleted");
 const {data:closed}=await admin.from("support_requests").select("status").eq("id",request.data.id).single();if(closed?.status!=="closed")throw new Error("Deletion request not closed");
 report.push({check:"owner-requested-deletion-and-content-denial",passed:true});
 await writeFile("visual-artifacts/report.json",JSON.stringify(report,null,2));
}finally{await browser.close();for(const s of servers)s.kill("SIGTERM")}
