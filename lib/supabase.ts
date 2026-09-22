import { createClient } from '@supabase/supabase-js';
import AsyncStorage from '@react-native-async-storage/async-storage';

const supabaseUrl = 'https://dwupfoofqluzcjwnhrhy.supabase.co';
const supabaseAnonKey = 'sb_publishable_I3JzN2ZrqYTAC6RAghENQw_sw4ZAvfO';

export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  auth: {
    storage: AsyncStorage,
    autoRefreshToken: true,
    persistSession: true,
    detectSessionInUrl: false,
  },
});
