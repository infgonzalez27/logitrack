const { createClient } = require('@supabase/supabase-js');
const url = 'https://egwryptydgxdnjvwtrfq.supabase.co';
const key = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVnd3J5cHR5ZGd4ZG5qdnd0cmZxIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4MjczODc0NCwiZXhwIjoyMDk4MzE0NzQ0fQ.BqKqWbUUodDvPkV-HSOuq8ADW-ox9nKkfG9wimTJCKQ';
const supabase = createClient(url, key, { auth: { autoRefreshToken: false, persistSession: false } });

async function check() {
  const { data: users, error: err1 } = await supabase.auth.admin.listUsers();
  const admin = users?.users?.find(u => u.email === 'inf.gonzalez27@gmail.com');
  console.log('Admin user ID:', admin?.id, admin?.email);

  if (admin) {
    const { data: emp, error: err2 } = await supabase.from('usuarios_empresas').select('*, empresas(*)').eq('user_id', admin.id);
    console.log('Admin empresas:', JSON.stringify(emp, null, 2), err2?.message || '');
  }

  const { data: allEmpresas } = await supabase.from('empresas').select('*');
  console.log('All empresas:', JSON.stringify(allEmpresas, null, 2));
}
check();
