import { createClient } from '@supabase/supabase-js';
import AsyncStorage from '@react-native-async-storage/async-storage';

const supabaseUrl = 'https://dwupfoofqluzcjwnhrhy.supabase.co';
const supabaseAnonKey = 'sb_publishable_I3JzN2ZrqYTAC6RAghENQw_sw4ZAvfO';

// Session persistence:
// - Browser / Expo / React Native (window exists): real AsyncStorage (localStorage
//   on web), so the login survives a refresh.
// - Static rendering on the server (no window): no-op storage. AsyncStorage reads
//   `window` at call time and would crash `expo export` / static HTML generation
//   with "window is not defined".
const storage =
  typeof window === 'undefined'
    ? {
        getItem: async () => null,
        setItem: async () => {},
        removeItem: async () => {},
      }
    : AsyncStorage;

export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  auth: {
    storage,
    autoRefreshToken: true,
    persistSession: true,
    detectSessionInUrl: false,
  },
});
