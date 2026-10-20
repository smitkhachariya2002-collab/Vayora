import {deletionHandler} from "./handler.ts";
function assert(value:unknown,message:string){if(!value)throw new Error(message);}
Deno.test("public request records only email and details; arbitrary identity and status are ignored",async()=>{
 let saved:unknown;
 const handler=deletionHandler({record:async(input)=>{saved=input;return "request-reference";}});
 const response=await handler(new Request("https://example.test",{method:"POST",body:JSON.stringify({email:" Owner@Example.com ",details:" Help ",consent:true,user_id:"victim",status:"closed",kind:"anything"})}));
 assert(response.status===200,"must succeed");
 assert(JSON.stringify(saved)===JSON.stringify({email:"owner@example.com",details:"Help"}),"must not trust caller identity fields");
 const result=await response.json();assert(result.reference==="request-reference","must return queue reference");
});
Deno.test("invalid requests never write; failed storage does not show success",async()=>{
 let writes=0;
 const handler=deletionHandler({record:async()=>{writes++;throw new Error("private database details");}});
 for(const body of [{email:"bad",consent:true},{email:"a@b.test",consent:false},{email:"a@b.test",consent:true,website:"spam"},{email:"a@b.test",consent:true,details:"x".repeat(1001)}]){
 const response=await handler(new Request("https://example.test",{method:"POST",body:JSON.stringify(body)}));assert(response.status===400,"invalid data must fail");}
 assert(writes===0,"invalid data must not persist");
 const response=await handler(new Request("https://example.test",{method:"POST",body:JSON.stringify({email:"a@b.test",consent:true})}));
 assert(response.status===503,"storage failure must fail");
 assert(!(await response.text()).includes("private database"),"must not expose internal errors");
});
Deno.test("preflight and read requests never write",async()=>{
 const handler=deletionHandler({record:async()=>{throw new Error("must not write");}});
 assert((await handler(new Request("https://example.test",{method:"OPTIONS"}))).status===204,"preflight");
 assert((await handler(new Request("https://example.test"))).status===405,"GET must fail");
});
