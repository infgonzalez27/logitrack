const { createClient } = require('@supabase/supabase-js');
const url = 'https://egwryptydgxdnjvwtrfq.supabase.co';
const key = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVnd3J5cHR5ZGd4ZG5qdnd0cmZxIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4MjczODc0NCwiZXhwIjoyMDk4MzE0NzQ0fQ.BqKqWbUUodDvPkV-HSOuq8ADW-ox9nKkfG9wimTJCKQ';
const supabase = createClient(url, key, { auth: { autoRefreshToken: false, persistSession: false } });

async function check() {
  const { data: users, error: err1 } = await supabase.auth.admin.listUsers();
  console.log('Auth Users Count:', users?.users?.length, err1?.message || '');
  
  const { data: emp, error: err2 } = await supabase.from('usuarios_empresas').select('*');
  console.log('Usuarios_Empresas Count:', emp?.length, err2?.message || '');
}
check();
