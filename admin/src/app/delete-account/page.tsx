import type { Metadata } from "next";
import Link from "next/link";
import DeletionForm from "./request-form";

export const metadata: Metadata = {
  title: "Delete your account | Vayora",
  description: "Request deletion of your Vayora account and associated data without signing in.",
};
export default function DeleteAccountPage() {
  return <main className="mx-auto max-w-3xl px-5 py-10 text-gray-900 sm:py-16">
    <header className="mb-8"><span className="text-lg font-bold text-violet-800">Vayora</span>
      <h1 className="mt-4 text-3xl font-bold tracking-tight sm:text-4xl">Delete your account</h1>
      <p className="mt-4 leading-7 text-gray-600">You can request deletion of your Vayora account and its associated data here. You do not need to sign in, pay, or reinstall the app.</p>
    </header>
    <section aria-labelledby="request-title" className="rounded-2xl border border-gray-200 bg-white p-6 shadow-sm sm:p-8">
      <h2 id="request-title" className="text-xl font-semibold">Request account deletion</h2>
      <p className="mt-3 mb-6 leading-6 text-gray-600">Enter the email address used for your Vayora account. Our support team will contact that address to verify ownership before deleting anything. Never send your password, payment PIN or one-time codes.</p>
      <DeletionForm />
    </section>
    <section className="mt-10 space-y-5 leading-7" aria-labelledby="next-title">
      <h2 id="next-title" className="text-xl font-semibold">What happens next?</h2>
      <ol className="list-decimal space-y-2 pl-6"><li>Your request is recorded for the Vayora support team.</li><li>We contact your account email to verify ownership. Submitting this form alone does not delete an account.</li><li>After verification, we process the deletion and confirm completion by email. If you cannot access your email, contact support for help verifying ownership.</li></ol>
      <h2 className="pt-3 text-xl font-semibold">What is deleted?</h2>
      <p>Your sign-in account, profile, channel memberships, channels you created, uploaded posts, and cloud files associated with your account are removed. Account deletion is permanent; download any files you want to keep first. Files other people have already downloaded to their own devices cannot be recalled.</p>
      <h2 className="pt-3 text-xl font-semibold">What is retained?</h2>
      <p>Payment and transaction records are retained for accounting, payment disputes and fraud prevention. Relevant support and security audit records may also be retained to document the request and protect the service. These records are restricted to authorised staff. No fixed automatic expiry is currently configured for these retained records; contact support for details about a specific record.</p>
      <h2 className="pt-3 text-xl font-semibold">Delete directly in the app</h2>
      <p>Sign in to Vayora, open <strong>Profile → Settings</strong>, find <strong>Delete Account</strong>, and confirm <strong>Delete</strong>. You can also use the form above if you no longer have the app.</p>
      <p>Deleting your account does not automatically cancel a subscription billed by Google Play. If you have one, cancel it under <strong>Google Play → Payments &amp; subscriptions → Subscriptions</strong>. You do not need to make a payment to request deletion.</p>
      <p>For help or to request deletion by email, write to <a className="font-medium text-violet-800 underline" href="mailto:help.vayora@gmail.com?subject=Vayora%20account%20deletion%20request">help.vayora@gmail.com</a> from your account email with the subject “Vayora account deletion request”.</p>
    </section>
    <footer className="mt-10 border-t border-gray-200 pt-6 text-sm text-gray-500"><Link className="text-violet-800 underline" href="/privacy">Privacy policy</Link><p className="mt-3">Vayora · Updated 20 October 2026</p></footer>
  </main>;
}
