import {Card,Badge,Field,Input,Select} from "@/components/admin/ui";
import {SubmitButton} from "@/components/admin/client";
import {savePaymentSettings,clearUpi} from "../actions";
export default function UpiSettings({s}:{s:Record<string,any>|null}){const live=!!s?.enabled&&!!s?.upi_id;return (
      <Card title="UPI settings" className="mb-5">
        <div className="mb-3 flex flex-wrap items-center gap-2 text-sm">
          <Badge tone={live ? "green" : "red"}>{live ? "Payments live" : "Payments off"}</Badge>
          <span className="text-gray-700">Money goes to <strong className="text-gray-900">{s?.upi_id || "no UPI ID set"}</strong>{s?.payee_name ? <> · {s.payee_name}</> : null}</span>
        </div>
        <form action={savePaymentSettings} className="grid gap-3 md:grid-cols-2">
          <Field label="UPI ID" hint="Like name@bank"><Input name="upi_id" defaultValue={s?.upi_id ?? ""} placeholder="name@bank" /></Field>
          <Field label="Payee name" hint="Shown in the customer's UPI app"><Input name="payee_name" defaultValue={s?.payee_name ?? ""} /></Field>
          <Field label="Activation" hint="Instant mode grants the plan after a matching UPI SUCCESS response. This is not bank verification: phone responses can be forged and unpaid plans may activate. Bank checks remain outstanding. Manual mode waits for your approval." className="md:col-span-2">
            <Select name="activation_mode" defaultValue={s?.activation_mode ?? "instant"}>
              <option value="instant">Instant (UPI response; bank unverified)</option><option value="manual">Manual (verify bank first)</option>
            </Select>
          </Field>
          <label className="flex items-center gap-2 text-sm text-gray-800"><input type="checkbox" name="enabled" defaultChecked={!!s?.enabled} /> Enable payments</label>
          <div className="flex flex-wrap gap-2 md:col-span-2">
            <SubmitButton confirm="New payments will go to the UPI ID you entered. Continue?">Save UPI settings</SubmitButton>
          </div>
        </form>
        {s?.upi_id ? <form action={clearUpi} className="mt-2"><SubmitButton variant="danger" small confirm="Clear the UPI ID? This stops all new payments.">Clear UPI ID</SubmitButton></form> : null}
      </Card>

);}
