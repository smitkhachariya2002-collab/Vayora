"use server";
import { randomUUID } from "node:crypto";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { db, requireAdmin } from "@/lib/supabase";

const text = (form: FormData, key: string) => String(form.get(key) ?? "").trim();
function checked(error: { message: string } | null) { if (error) throw new Error(error.message); }
export async function signIn(form: FormData) {
  const client = await db();
  const credentials = { email: text(form, "email"), password: String(form.get("password") ?? "") };
  const { error } = form.get("signup") === "yes"
    ? await client.auth.signUp(credentials)
    : await client.auth.signInWithPassword(credentials);
  if (error) redirect("/login?error=" + encodeURIComponent(error.message));
  if (form.get("signup") === "yes") redirect("/login?message=Check+your+email+then+ask+the+owner+to+grant+access");
  redirect("/");
}
export async function signOut() {
  const client = await db();
  await client.auth.signOut();
  redirect("/login");
}
export async function changeAccess(form: FormData) {
  const { client } = await requireAdmin(true);
  const status = text(form,"status");
  if (!["approved","rejected","none"].includes(status)) throw new Error("Invalid access status");
  checked((await client.rpc("set_ads_access",{user_id:text(form,"user_id"),status})).error);
  revalidatePath("/dashboard","layout");
}
export async function grantPlan(form: FormData) {
  const { client } = await requireAdmin(true);
  checked((await client.rpc("grant_premium",{user_id:text(form,"user_id"),plan_id:text(form,"plan_id")})).error);
  revalidatePath("/dashboard","layout");
}
export async function markPaid(form: FormData) {
  const { client } = await requireAdmin(true);
  checked((await client.rpc("admin_mark_payment_paid",{order_id:text(form,"order_id"),utr:text(form,"utr")})).error);
  revalidatePath("/dashboard","layout");
}
export async function revokePayment(form: FormData) {
  const { client } = await requireAdmin(true);
  checked((await client.rpc("admin_revoke_payment",{order_id:text(form,"order_id"),reason:text(form,"reason")})).error);
  revalidatePath("/dashboard","layout");
}
export async function saveMode(form: FormData) {
  const { client } = await requireAdmin(true);
  const mode = text(form,"free_mode");
  if (!["true","false"].includes(mode)) throw new Error("Invalid mode");
  checked((await client.from("app_mode").update({
    free_mode: mode === "true",
  }).eq("id",true)).error);
  revalidatePath("/dashboard","layout");
}
export async function saveUpi(form: FormData) {
  const { client } = await requireAdmin(true);
  checked((await client.from("payment_settings").update({
    upi_id:text(form,"upi_id"), payee_name:text(form,"payee_name"), enabled:form.has("enabled"), activation_mode:text(form,"activation_mode")||"instant",
  }).eq("id",true)).error);
  revalidatePath("/dashboard/payments");
}
export async function saveChannel(form: FormData) {
  const { client } = await requireAdmin();
  const {error} = await client.rpc("admin_save_channel", {
    channel_id:text(form,"id")||null,
    channel_name:text(form,"name"),description:text(form,"description"),
    category:text(form,"category"),icon_url:text(form,"icon_url")||null,
    audience:text(form,"audience")||"all",status:text(form,"status")||"published",
    tags:text(form,"tags").split(",").map(v=>v.trim()).filter(Boolean),
  });
  checked(error);
  revalidatePath("/channels");
}
export async function savePost(form: FormData) {
  const { client, user } = await requireAdmin();
  const id = text(form,"id") || randomUUID();
  const values = {channel_id:text(form,"channel_id"),title:text(form,"title"),description:text(form,"description"),
    audience:text(form,"audience") || "all",status:text(form,"status") || "draft",publish_at:text(form,"publish_at") ? new Date(text(form,"publish_at")+"+05:30").toISOString() : null};
  if(values.status==="scheduled"&&!values.publish_at)throw new Error("Choose a schedule date and time");
  checked((text(form,"id") ? await client.from("posts").update(values).eq("id",id)
    : await client.from("posts").insert({...values,id,created_by:user.id})).error);
  revalidatePath("/dashboard/posts");
  return id;
}
