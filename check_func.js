const { createClient } = require('@supabase/supabase-js');
const url = 'https://egwryptydgxdnjvwtrfq.supabase.co';
const key = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVnd3J5cHR5ZGd4ZG5qdnd0cmZxIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4MjczODc0NCwiZXhwIjoyMDk4MzE0NzQ0fQ.BqKqWbUUodDvPkV-HSOuq8ADW-ox9nKkfG9wimTJCKQ';
const supabase = createClient(url, key, { auth: { autoRefreshToken: false, persistSession: false } });

async function check() {
  const { data } = await supabase.rpc('retorna_lista_usuarios_segun_parametros', { p_nombre: '', p_rol: '' });
  console.log('RPC retorna_lista_usuarios_segun_parametros:', data);
  
  // Try to find the function definition
  const { data: func } = await supabase.from('pg_proc').select('*'); // We probably can't query pg_proc directly from API
}
check();
