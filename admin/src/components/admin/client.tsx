"use client";
import { useSearchParams } from "next/navigation";
import { useFormStatus } from "react-dom";
import type { ReactNode } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";

const BTN: Record<string, string> = {
  primary: "bg-teal-700 text-white hover:bg-teal-800",
  secondary: "border border-gray-300 bg-white text-gray-700 hover:bg-gray-50",
  danger: "bg-red-600 text-white hover:bg-red-700",
  success: "bg-green-600 text-white hover:bg-green-700",
};

/** Submit button with a loading state and an optional confirm dialog (use inside a <form>). */
export function SubmitButton({ children, confirm, variant = "primary", small }: { children: ReactNode; confirm?: string; variant?: keyof typeof BTN; small?: boolean }) {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      onClick={(e) => { if (confirm && !window.confirm(confirm)) e.preventDefault(); }}
      className={"inline-flex items-center justify-center rounded-xl font-medium transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-teal-400 disabled:opacity-50 " + (small ? "px-2.5 py-1 text-xs " : "px-3.5 py-2 text-sm ") + BTN[variant]}
    >
      {pending ? "Working…" : children}
    </button>
  );
}

/** Flash message from ?ok= / ?error= after a save. */
export function Flash() {
  const q = useSearchParams();
  const ok = q.get("ok"), error = q.get("error");
  if (!ok && !error) return null;
  return (
    <p role={error ? "alert" : "status"} className={"mb-4 rounded-lg border px-3 py-2 text-sm " + (error ? "border-red-200 bg-red-50 text-red-700" : "border-green-200 bg-green-50 text-green-700")}>
      {error ?? ok}
    </p>
  );
}

export function SignOut() {
  return (
    <button
      className="admin-signout mt-3 w-full rounded-xl border border-slate-300 bg-white px-3 py-2 text-xs font-medium text-slate-600 hover:bg-slate-50"
      onClick={async () => { await supabaseBrowser().auth.signOut(); window.location.href = "/workspace/login"; }}
    >
      Sign out
    </button>
  );
}
