"use client";
import {useFormStatus} from "react-dom";
import {Button,type Variant} from "./ui";
export function Submit({children="Save changes",variant="primary",confirm}:{children?:React.ReactNode;variant?:Variant;confirm?:string}){const {pending}=useFormStatus();return <Button type="submit" variant={variant} disabled={pending} onClick={e=>{if(confirm&&!window.confirm(confirm))e.preventDefault();}}>{pending?"Saving…":children}</Button>}
