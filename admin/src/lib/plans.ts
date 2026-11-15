import { createClient } from "@supabase/supabase-js";

export type Plan = {
  id: string; code: string; name: string; price_inr: number; duration_days: number; duration_hours?: number;
  perks: string[] | null; badge: string | null; position: number;
};

export async function loadPlans(): Promise<Plan[]> {
  const sb = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!);
  const { data } = await sb.rpc("public_plans");
  return (data as Plan[]) ?? [];
}

export const durationLabel = (d: number, h = 0): string => {
  if (h > 0) return h % 24 === 0 ? durationLabel(h / 24) : h === 1 ? "1 Hour" : `${h} Hours`;
  if (d >= 365 && d % 365 === 0) return d === 365 ? "1 Year" : `${d / 365} Years`;
  if (d >= 30 && d % 30 === 0) return d === 30 ? "1 Month" : `${d / 30} Months`;
  return d === 1 ? "1 Day" : `${d} Days`;
};
