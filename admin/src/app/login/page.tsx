import { signIn } from "../actions";
export default async function Login({searchParams}:{searchParams:Promise<{error?:string;message?:string}>}) {
 const query=await searchParams;
 return <main><h1>Vayora admin</h1>{query.error&&<p role="alert">{query.error}</p>}{query.message&&<p>{query.message}</p>}
 <form action={signIn} className="panel"><p><input name="email" type="email" required placeholder="Email" autoComplete="username"/></p>
 <p><input name="password" type="password" required minLength={8} placeholder="Password" autoComplete="current-password"/></p>
 <label><input name="signup" type="checkbox" value="yes"/>Create an account first</label><p><button>Continue</button></p></form>
 <p>Confirm your email before signing in. Only accounts granted an admin role can open the dashboard.</p></main>;
}
