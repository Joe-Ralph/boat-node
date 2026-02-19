class Constants {
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://ltlftxaskaebqwptcbdq.supabase.co',
  );
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_R9EBVNhFL2rQOAUV2ihJ3A_SaSaPqbz',
  );
}
