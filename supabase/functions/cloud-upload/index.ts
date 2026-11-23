import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import {handleCloud} from '../_shared/bunny-cloud.ts';
Deno.serve(async req=>(await handleCloud(req))??new Response(JSON.stringify({error:'Storage is not configured'}),{status:503,headers:{'Content-Type':'application/json'}}));
