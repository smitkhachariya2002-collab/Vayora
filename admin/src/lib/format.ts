export const inr = (n: number | string | null | undefined) =>
  "₹" + new Intl.NumberFormat("en-IN").format(Number(n ?? 0));

export const ist = (d: string | null | undefined) =>
  d
    ? new Intl.DateTimeFormat("en-IN", {
        timeZone: "Asia/Kolkata",
        day: "2-digit",
        month: "short",
        year: "numeric",
        hour: "2-digit",
        minute: "2-digit",
      }).format(new Date(d))
    : "—";

export const gb = (b: number | null | undefined) => {
  const n = Number(b ?? 0);
  if (n >= 2 ** 40) return (n / 2 ** 40).toFixed(2) + " TB";
  if (n >= 2 ** 30) return (n / 2 ** 30).toFixed(2) + " GB";
  if (n >= 2 ** 20) return (n / 2 ** 20).toFixed(1) + " MB";
  return Math.round(n / 1024) + " KB";
};

/** RPC results are jsonb: either an array or { rows: [...] }. */
export const rowsOf = (x: unknown): Record<string, unknown>[] => {
  if (Array.isArray(x)) return x as Record<string, unknown>[];
  if (x && typeof x === "object" && Array.isArray((x as { rows?: unknown }).rows))
    return (x as { rows: Record<string, unknown>[] }).rows;
  return [];
};

export const cell = (k: string, v: unknown): string => {
  if (v === null || v === undefined || v === "") return "—";
  if (/(_at|^at)$/.test(k) && typeof v === "string") return ist(v);
  if (/(amount|price|revenue|spent)/.test(k) && !isNaN(Number(v))) return inr(v as number);
  if (/bytes/.test(k) && !isNaN(Number(v))) return gb(Number(v));
  if (typeof v === "object") return JSON.stringify(v);
  return String(v);
};
