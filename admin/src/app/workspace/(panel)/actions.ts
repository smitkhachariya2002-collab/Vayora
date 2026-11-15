"use server";
import { redirect } from "next/navigation";
import { requireAdmin, flash, str, UUID } from "@/lib/admin";

const back = (fd: FormData, fallback: string) => {
  const b = str(fd, "back");
  return b.startsWith("/workspace") ? b : fallback;
};
const fnError = async (error: unknown): Promise<{ message: string } | null> => {
  if (!error) return null;
  const e = error as { message?: string; context?: Response };
  try {
    const j = await e.context?.json();
    if (j?.error) return { message: j.detail ? `${j.error}: ${j.detail}` : String(j.error) };
  } catch { /* not json */ }
  return { message: e.message ?? "Request failed" };
};

// ---------------- channels ----------------
export async function reviewChannel(fd: FormData) {
  const { sb } = await requireAdmin(true);
  const approve = str(fd, "approve") === "1";
  const { error } = await sb.rpc("review_channel", { p_channel: str(fd, "id"), p_approve: approve, p_audience: str(fd, "audience") || "all" });
  flash("/workspace/channels", error, approve ? "Channel approved." : "Channel rejected.");
}

export async function saveChannel(fd: FormData) {
  const { sb, role } = await requireAdmin();
  const id = str(fd, "id");
  const name = str(fd, "name");
  if (name.length < 2) flash(id ? `/workspace/channels/${id}` : "/workspace/channels/new", { message: "The name needs at least 2 characters." }, "");
  const row: Record<string, unknown> = {
    name,
    description: str(fd, "description"),
    category: str(fd, "category") || null,
    tags: str(fd, "tags").split(",").map((t) => t.trim()).filter(Boolean).slice(0, 12),
  };
  if (role === "owner" || id) { row.audience = str(fd, "audience") || "all"; row.status = str(fd, "status") === "draft" ? "draft" : "published"; }
  if (id) {
    const { error } = await sb.from("channels").update(row).eq("id", id);
    flash(`/workspace/channels/${id}`, error, "Channel saved.");
  }
  if (role !== "owner") flash("/workspace/channels", { message: "Only the owner can create channels here." }, "");
  const { data, error } = await sb.from("channels").insert(row).select("id").single();
  if (error || !data) flash("/workspace/channels/new", error ?? { message: "Could not create the channel." }, "");
  redirect(`/workspace/channels/${data!.id}?ok=` + encodeURIComponent("Channel created. You can add a picture now."));
}

export async function setHidden(fd: FormData) {
  const { sb } = await requireAdmin(true);
  const hidden = str(fd, "hidden") === "1";
  const { error } = await sb.rpc("set_content_hidden", { p_type: str(fd, "type"), p_id: str(fd, "id"), p_hidden: hidden });
  flash(back(fd, "/workspace/channels"), error, hidden ? "Hidden from the app." : "Visible in the app again.");
}

// ---------------- posts ----------------
export async function approveVideo(fd: FormData) {
  const { sb } = await requireAdmin();
  const id = str(fd, "id"), audience = str(fd, "audience");
  if (!UUID.test(id) || !["all", "ads", "organic"].includes(audience)) {
    flash("/workspace/posts", { message: "Choose a valid video and audience." }, "");
  }
  const { data: media, error: mediaError } = await sb.from("post_items").select("id").eq("post_id", id).limit(1);
  if (mediaError || !media?.length) flash("/workspace/posts", mediaError ?? { message: "Add media before approving this video." }, "");
  const { data, error } = await sb.from("posts").update({ status: "published", audience, publish_at: null }).eq("id", id).eq("status", "draft").select("id").single();
  flash("/workspace/posts", error ?? (!data ? { message: "Video could not be approved." } : null), "Video approved for the selected audience.");
}

const istToUtc = (local: string) => (local ? new Date(local + ":00+05:30").toISOString() : null);

export async function createPost(fd: FormData) {
  const { sb } = await requireAdmin();
  const status = str(fd, "status") || "draft";
  const publishAt = status === "scheduled" ? istToUtc(str(fd, "publish_at")) : null;
  if (!str(fd, "title")) flash("/workspace/posts/new", { message: "Add a title." }, "");
  if (!UUID.test(str(fd, "channel_id"))) flash("/workspace/posts/new", { message: "Choose a channel." }, "");
  if (status === "scheduled" && !publishAt) flash("/workspace/posts/new", { message: "Choose the date and time for a scheduled post." }, "");
  const { data, error } = await sb.from("posts").insert({
    title: str(fd, "title"), description: str(fd, "description"), channel_id: str(fd, "channel_id"),
    audience: str(fd, "audience") || "all", status, publish_at: publishAt,
  }).select("id").single();
  if (error || !data) flash("/workspace/posts/new", error ?? { message: "Could not create the post." }, "");
  redirect(`/workspace/posts/${data!.id}?ok=` + encodeURIComponent("Post created. Add the video below."));
}

export async function savePost(fd: FormData) {
  const { sb } = await requireAdmin();
  const id = str(fd, "id");
  const status = str(fd, "status") || "draft";
  const publishAt = status === "scheduled" ? istToUtc(str(fd, "publish_at")) : null;
  if (status === "scheduled" && !publishAt) flash(`/workspace/posts/${id}`, { message: "Choose the date and time for a scheduled post." }, "");
  const { error } = await sb.from("posts").update({
    title: str(fd, "title"), description: str(fd, "description"), audience: str(fd, "audience") || "all", status, publish_at: publishAt,
  }).eq("id", id);
  flash(`/workspace/posts/${id}`, error, "Post saved.");
}

export async function deletePost(fd: FormData) {
  const { sb } = await requireAdmin();
  const id = str(fd, "id");
  const { error } = await sb.functions.invoke("post-delete", { body: { post_id: id } });
  const e = await fnError(error);
  if (e) flash(`/workspace/posts/${id}`, e, "");
  flash("/workspace/posts", null, "Post and its files deleted.");
}

// ---------------- approvals / users ----------------
export async function setAccess(fd: FormData) {
  const { sb } = await requireAdmin(true);
  const status = str(fd, "status");
  const { error } = await sb.rpc("set_ads_access", { p_user: str(fd, "user"), p_status: status });
  flash(back(fd, "/workspace/approvals"), error, status === "approved" ? "Full access approved." : status === "rejected" ? "Request rejected." : "Access revoked.");
}

export async function grantPremium(fd: FormData) {
  const { sb } = await requireAdmin(true);
  if (!UUID.test(str(fd, "plan"))) flash(back(fd, "/workspace/users"), { message: "Choose a plan." }, "");
  const { error } = await sb.rpc("grant_premium", { p_user: str(fd, "user"), p_plan: str(fd, "plan") });
  flash(back(fd, "/workspace/users"), error, "Premium granted.");
}

// ---------------- payments ----------------
export async function savePaymentSettings(fd: FormData) {
  const { sb } = await requireAdmin(true);
  const upi = str(fd, "upi_id");
  if (upi && !/^[A-Za-z0-9._-]{2,256}@[A-Za-z0-9]{2,64}$/.test(upi)) flash("/workspace/payments", { message: "UPI ID must look like name@bank." }, "");
  const enabled = fd.get("enabled") === "on" && upi !== "";
  const { error } = await sb.from("payment_settings").update({
    upi_id: upi, payee_name: str(fd, "payee_name"), enabled, activation_mode: str(fd, "activation_mode") === "manual" ? "manual" : "instant",
  }).eq("id", 1);
  flash("/workspace/payments", error, enabled ? `Saved. New payments go to ${upi}.` : "Saved. Payments are off.");
}

export async function clearUpi() {
  const { sb } = await requireAdmin(true);
  const { error } = await sb.from("payment_settings").update({ upi_id: "", enabled: false }).eq("id", 1);
  flash("/workspace/payments", error, "UPI ID cleared. Payments are off.");
}

export async function orderAction(fd: FormData) {
  const { sb } = await requireAdmin(true);
  const id = str(fd, "id"), kind = str(fd, "kind"), note = str(fd, "note");
  const b = back(fd, "/workspace/payments");
  if (kind === "paid") {
    if (!/^\d{12}$/.test(note)) flash(b, { message: "Enter the 12-digit UTR from your bank statement." }, "");
    const { error } = await sb.rpc("admin_mark_paid", { p_order: id, p_utr: note });
    flash(b, error, "Marked paid. The plan is active.");
  }
  if (kind === "bank") {
    const { error } = await sb.rpc("admin_confirm_bank", { p_order: id });
    flash(b, error, "Bank verified.");
  }
  if (kind === "reject") {
    const { error } = await sb.rpc("admin_reject_order", { p_order: id, p_note: note || null });
    flash(b, error, "Payment rejected.");
  }
  if (kind === "revoke") {
    const { error } = await sb.rpc("admin_revoke_order", { p_order: id, p_note: note || null });
    flash(b, error, "Payment revoked. The plan has ended.");
  }
  flash(b, { message: "Unknown action." }, "");
}

// ---------------- requests ----------------
export async function closeRequest(fd: FormData) {
  const { sb } = await requireAdmin(true);
  const { error } = await sb.rpc("admin_close_request", { p_id: str(fd, "id") });
  flash(back(fd, "/workspace/requests"), error, "Request closed.");
}

export async function deleteAccount(fd: FormData) {
  const { sb } = await requireAdmin(true);
  const { error } = await sb.functions.invoke("admin-delete-account", { body: { user_id: str(fd, "user"), request_id: str(fd, "id") || undefined } });
  flash(back(fd, "/workspace/requests"), await fnError(error), "Account deleted.");
}

// ---------------- plans / app mode ----------------
export async function saveMode(fd: FormData) {
  const { sb } = await requireAdmin(true);
  const patch: Record<string, unknown> = {};
  if (fd.has("free_mode")) patch.free_mode = str(fd, "free_mode") === "on";
  for (const k of ["free_plans_for", "plans_visible_for"]) {
    if (fd.has(k)) {
      const v = str(fd, k);
      if (!["everyone", "ads", "organic", "none"].includes(v)) flash("/workspace/plans", { message: "Invalid choice." }, "");
      patch[k] = v;
    }
  }
  const { error } = await sb.from("app_mode").update(patch).eq("id", 1);
  flash("/workspace/plans", error, "Saved. The app updates within a minute.");
}

const planFields = (fd: FormData) => {
  const n = Math.max(1, Math.floor(Number(str(fd, "duration")) || 1));
  const hours = str(fd, "unit") === "h";
  return {
    name: str(fd, "name"),
    price_inr: Math.floor(Number(str(fd, "price_inr"))),
    duration_days: hours ? 1 : n,
    duration_hours: hours ? n : 0,
    perks: str(fd, "perks").split("\n").map((p) => p.trim()).filter(Boolean).slice(0, 10),
    badge: str(fd, "badge") || null,
    position: Math.floor(Number(str(fd, "position")) || 0),
    active: fd.get("active") === "on",
    free_eligible: fd.get("free_eligible") === "on",
  };
};

export async function savePlan(fd: FormData) {
  const { sb } = await requireAdmin(true);
  const row = planFields(fd);
  if (!row.name || !(row.price_inr >= 1)) flash("/workspace/plans", { message: "A plan needs a name and a price of at least ₹1." }, "");
  const { error } = await sb.from("plans").update(row).eq("id", str(fd, "id"));
  flash("/workspace/plans", error, `${row.name} saved.`);
}

export async function addPlan(fd: FormData) {
  const { sb } = await requireAdmin(true);
  const row = planFields(fd);
  const code = str(fd, "code").toLowerCase();
  if (!/^[a-z0-9][a-z0-9_-]{1,30}$/.test(code)) flash("/workspace/plans", { message: "Code: 2–31 lowercase letters, numbers, - or _." }, "");
  if (!row.name || !(row.price_inr >= 1)) flash("/workspace/plans", { message: "A plan needs a name and a price of at least ₹1." }, "");
  const { error } = await sb.from("plans").insert({ ...row, code, active: true });
  flash("/workspace/plans", error, `${row.name} added.`);
}

// ---------------- meta ----------------
export async function saveMeta(fd: FormData) {
  const { sb } = await requireAdmin(true);
  const pixel = str(fd, "pixel_id").replace(/\s+/g, "");
  if (pixel && !/^\d{5,20}$/.test(pixel)) flash("/workspace/meta", { message: "The Pixel ID is a number of about 15 or 16 digits. Copy it from Events Manager." }, "");
  // Not-null text columns: empty string means "not set".
  const patch: Record<string, unknown> = { pixel_id: pixel, test_event_code: str(fd, "test_event_code"), enabled: fd.get("enabled") === "on", updated_at: new Date().toISOString() };
  const token = str(fd, "capi_token").replace(/\s+/g, "");
  if (token) patch.capi_token = token; // write-only: an empty box keeps the saved token
  if (fd.get("clear_token") === "on") patch.capi_token = "";
  const { error } = await sb.from("meta_settings").update(patch).eq("id", 1);
  if (error) flash("/workspace/meta", error, "");
  if(!patch.enabled) flash("/workspace/meta",null,"Settings saved. Meta event delivery is off.");
  // Check the new Pixel ID and token with Meta straight away, so a typo shows up now and not after ads are running.
  const { data, error: fe } = await sb.functions.invoke("meta-send", { body: { action: "verify" } });
  const d = (data ?? {}) as { ok?: boolean; name?: string; message?: string };
  if (fe || !d.ok) flash("/workspace/meta", { message: "Saved, but Meta did not accept this Pixel ID and token: " + (d.message ?? (await fnError(fe))?.message ?? "no answer") }, "");
  flash("/workspace/meta", null, `Saved and connected to pixel “${d.name ?? pixel}”. The website and eligible, consented app events now use these central settings. Check Test Events before starting ads.`);
}

export async function metaSend(fd: FormData) {
  const { sb } = await requireAdmin(true);
  const kind = str(fd, "kind");
  if (kind === "retry") {
    const { data, error } = await sb.rpc("admin_meta_retry");
    flash("/workspace/meta", error, `${data ?? 0} failed event(s) queued again.`);
  }
  const { data, error } = await sb.functions.invoke("meta-send", { body: { action: kind === "test" ? "test" : kind === "verify" ? "verify" : "flush" } });
  const e = await fnError(error);
  if (e) flash("/workspace/meta", e, "");
  const d = (data ?? {}) as Record<string, unknown>;
  if (kind === "verify") flash("/workspace/meta", d.ok ? null : { message: "Meta did not accept the Pixel ID and token: " + d.message }, `Connected to pixel “${d.name}”.`);
  if (d.skipped) flash("/workspace/meta", { message: "Meta is not set up or not enabled yet." }, "");
  if (kind === "test") flash("/workspace/meta", d.ok ? null : { message: String(d.message ?? "Meta rejected the test event.") }, "Test Purchase sent. Open Events Manager → Test events to see it.");
  flash("/workspace/meta", null, `Sent ${d.sent ?? 0}, test events ${d.test_sent ?? 0}, suppressed ${d.suppressed ?? 0}, failed ${d.failed ?? 0}, still waiting ${d.pending ?? 0}.`);
}

// ---------------- admins ----------------
export async function inviteAdmin(fd: FormData) {
  const { sb } = await requireAdmin(true);
  const role = str(fd, "role") === "owner" ? "owner" : "content";
  const channel_ids = fd.getAll("channels").map(String).filter((c) => UUID.test(c));
  const { error } = await sb.functions.invoke("admin-invite", { body: { email: str(fd, "email"), role, channel_ids } });
  flash("/workspace/admins", await fnError(error), "Admin saved. New people get an invite email.");
}

export async function removeAdmin(fd: FormData) {
  const { sb, user } = await requireAdmin(true);
  const id = str(fd, "user");
  if (id === user.id) flash("/workspace/admins", { message: "You cannot remove yourself." }, "");
  await sb.from("admin_channel_access").delete().eq("user_id", id);
  const { error } = await sb.from("admins").delete().eq("user_id", id);
  flash("/workspace/admins", error, "Admin removed.");
}


