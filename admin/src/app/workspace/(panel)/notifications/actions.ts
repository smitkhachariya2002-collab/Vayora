"use server";
import {requireAdmin,flash,str,UUID} from '@/lib/admin';
export async function createNotification(fd:FormData){
 const {sb,user}=await requireAdmin(true),title=str(fd,'title'),body=str(fd,'body'),type=str(fd,'type'),target:Record<string,string>={type};
 if(!title||title.length>150||!body||body.length>2000)flash('/workspace/notifications',{message:'Enter a title and message within the limits.'},'');
 if(!['explore','video','channel','premium','link'].includes(type))flash('/workspace/notifications',{message:'Invalid destination.'},'');
 if(type==='video'||type==='channel'){target.id=str(fd,'target_id');if(!UUID.test(target.id))flash('/workspace/notifications',{message:'Enter a valid content ID.'},'');}
 if(type==='link'){try{const u=new URL(str(fd,'url'));if(u.protocol!=='https:'||u.username||u.password)throw Error();target.url=u.toString();}catch{flash('/workspace/notifications',{message:'Enter an HTTPS link.'},'');}}
 const audience:Record<string,unknown>={};const source=str(fd,'source'),premium=str(fd,'premium'),guest=str(fd,'guest');
 if(['ads','organic'].includes(source))audience.source=source;
 if(['true','false'].includes(premium))audience.premium=premium==='true';
 if(['true','false'].includes(guest))audience.guest=guest==='true';
 const channels=str(fd,'channel_ids').split(',').map(s=>s.trim()).filter(Boolean);if(channels.some(id=>!UUID.test(id)))flash('/workspace/notifications',{message:'Channel IDs must be comma-separated UUIDs.'},'');if(channels.length)audience.channel_ids=channels;
 if(fd.get('test')==='on')audience.user_ids=[user.id];
 const image=str(fd,'image_url');if(image&&!/^https:\/\//i.test(image))flash('/workspace/notifications',{message:'Image must use HTTPS.'},'');
 let scheduled_at=new Date();if(str(fd,'scheduled_at')){scheduled_at=new Date(str(fd,'scheduled_at')+'+05:30');if(!Number.isFinite(scheduled_at.getTime()))flash('/workspace/notifications',{message:'Invalid schedule.'},'');}
 const {error}=await sb.from('push_messages').insert({title,body,target,audience,image_url:image||null,scheduled_at:scheduled_at.toISOString(),status:'scheduled',created_by:user.id});
 flash('/workspace/notifications?tab=history',error,'Message scheduled. Delivery starts after Firebase is configured and the sender is enabled.');
}
export async function saveAutomation(fd:FormData){const {sb}=await requireAdmin(true);const {error}=await sb.from('push_automations').update({enabled:fd.get('enabled')==='on',title:str(fd,'title'),body:str(fd,'body'),updated_at:new Date().toISOString()}).eq('key',str(fd,'key'));flash('/workspace/notifications?tab=automatic',error,'Automatic message saved.');}
export async function saveFirebase(fd:FormData){const {sb}=await requireAdmin(true);let options:unknown;try{options=JSON.parse(str(fd,'options'));if(!options||typeof options!=='object'||JSON.stringify(options).includes('private_key'))throw Error();}catch{flash('/workspace/notifications?tab=settings',{message:'Use public Firebase app options, not a service-account private key.'},'');}
 const {error}=await sb.from('integration_public_config').update({firebase_options:options,updated_at:new Date().toISOString()}).eq('id',1);flash('/workspace/notifications?tab=settings',error,'Public Firebase configuration saved. The service account belongs in the FCM_SERVICE_ACCOUNT Edge secret.');}
export async function runSender(){const {sb}=await requireAdmin(true);const {data,error}=await sb.functions.invoke('push-send',{body:{action:'flush'}});flash('/workspace/notifications?tab=history',error?{message:data?.error??error.message}:null,`Sender checked: ${data?.sent??0} sent, ${data?.failed??0} failed.`);}
