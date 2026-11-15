import SiteShell from "@/components/SiteShell";
import { loadPlans } from "@/lib/plans";
import SubscribeClient from "./SubscribeClient";

export const dynamic = "force-dynamic";
export const metadata = { title: "Go Premium", robots: { index: false } };

export default async function Subscribe({ searchParams: pending }: { searchParams: Promise<{ app?: string; free?: string; paused?: string }> }) {
 const searchParams=await pending;
  const plans = await loadPlans();
  const free = (searchParams.free ?? "").split(",").filter(Boolean);
  return (
    <SiteShell bare>
      <SubscribeClient plans={plans} freeIds={free} paused={searchParams.paused === "1"} inApp={searchParams.app === "1"} />
    </SiteShell>
  );
}
