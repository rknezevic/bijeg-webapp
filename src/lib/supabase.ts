import { createClient } from '@supabase/supabase-js';

const url = import.meta.env.VITE_SUPABASE_URL as string | undefined;
const key = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined;

export const configured = Boolean(url && key);

export const supabase = createClient(url ?? 'http://localhost', key ?? 'missing', {
  auth: { persistSession: true, autoRefreshToken: true },
  realtime: { params: { eventsPerSecond: 20 } },
});

/** No accounts: every browser gets an anonymous Supabase session, kept in localStorage. */
let sessionPromise: Promise<string> | null = null;
export function ensureSession(): Promise<string> {
  if (!sessionPromise) {
    sessionPromise = (async () => {
      const { data } = await supabase.auth.getSession();
      if (data.session) return data.session.user.id;
      const { data: signed, error } = await supabase.auth.signInAnonymously();
      if (error || !signed.user) {
        sessionPromise = null;
        throw new Error('Ne mogu se spojiti na poslužitelj. Provjeri je li u Supabaseu uključen anonimni ulaz.');
      }
      return signed.user.id;
    })();
  }
  return sessionPromise;
}
