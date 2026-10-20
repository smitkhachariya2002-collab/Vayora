import Link from "next/link";
import { notFound } from "next/navigation";
const policies:Record<string,{title:string;body:string}>={
 privacy:{title:"Privacy",body:"Vayora stores account details, consent, install attribution, content and payment records to provide the service. Contact help.vayora@gmail.com to request access or deletion."},
 terms:{title:"Terms",body:"Use Vayora lawfully. Upload only content you have the right to share. Plans do not renew automatically and begin after payment verification. Access depends on your plan and channel permissions."},
 refund:{title:"Refunds",body:"Contact help.vayora@gmail.com with your order reference if a verified payment did not activate access or if you wish to request a refund. Support reviews requests."},
 community:{title:"Community rules",body:"Illegal, abusive and infringing content is prohibited. Report a post or channel inside Vayora. User-created channels require review."},
};
export default async function Policy({params}:{params:Promise<{policy:string}>}){
 const {policy}=await params,p=policies[policy];if(!p)notFound();
 return <main><Link href="/">Vayora</Link><h1>{p.title}</h1><p>{p.body}</p><p><Link href="/delete-account">Request account and data deletion</Link></p><p>Policy version v1 · Support: help.vayora@gmail.com</p></main>;
}
