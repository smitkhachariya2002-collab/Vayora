import {redirect} from "next/navigation";
export default async function SharedPost({params}:{params:Promise<{id:string}>}){
 const {id}=await params;
 redirect("/d?post="+encodeURIComponent(id));
}
