import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import {handleBunny} from "../_shared/bunny-handler.ts";
Deno.serve(req=>handleBunny(req,"bunny-cleanup"));
