import assert from "node:assert/strict";
import {createServer} from "node:http";
import {spawn} from "node:child_process";
let recorded;
const upstream=createServer(async(req,res)=>{
 let text="";for await(const chunk of req)text+=chunk;
 recorded={url:req.url,body:JSON.parse(text)};
 res.setHeader("Content-Type","application/json");
 res.end(JSON.stringify({reference:"test-reference",message:"Request recorded"}));
});
await new Promise(r=>upstream.listen(0,"127.0.0.1",r));
const port=upstream.address().port;
const app=spawn(process.execPath,["node_modules/next/dist/bin/next","start","-p","3107"],{env:{...process.env,NEXT_PUBLIC_SUPABASE_URL:"http://127.0.0.1:"+port,NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY:"test-public-key"},stdio:["ignore","pipe","pipe"]});
app.stdout.pipe(process.stdout);app.stderr.pipe(process.stderr);
try{
 let ready=false;
 for(let i=0;i<60;i++){try{const response=await fetch("http://localhost:3107/delete-account");if(response.ok){ready=true;break;}}catch{}await new Promise(r=>setTimeout(r,500));}
 assert(ready,"public deletion page must load without login");
 const response=await fetch("http://localhost:3107/delete-account");
 const html=await response.text();
 for(const text of ["Delete your account","Account email address","Request account deletion","What is deleted?","What is retained?","help.vayora@gmail.com"])assert(html.includes(text),text);
 const body={email:"test@example.invalid",consent:true};
 const submitted=await fetch("http://localhost:3107/api/deletion-request",{method:"POST",headers:{"Content-Type":"application/json",origin:"http://localhost:3107"},body:JSON.stringify(body)});
 assert.equal(submitted.status,200);assert.equal((await submitted.json()).reference,"test-reference");
 assert.equal(recorded.url,"/functions/v1/deletion-request");assert.deepEqual(recorded.body,body);
 const blocked=await fetch("http://localhost:3107/api/deletion-request",{method:"POST",headers:{origin:"https://other.example"},body:JSON.stringify(body)});assert.equal(blocked.status,403);
 console.log("Public deletion page and request forwarding verified; no real account or request was used.");
}finally{app.kill();upstream.close();}
