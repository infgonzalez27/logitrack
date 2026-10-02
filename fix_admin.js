const { createClient } = require('@supabase/supabase-js');
const url = 'https://egwryptydgxdnjvwtrfq.supabase.co';
const key = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVnd3J5cHR5ZGd4ZG5qdnd0cmZxIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4MjczODc0NCwiZXhwIjoyMDk4MzE0NzQ0fQ.BqKqWbUUodDvPkV-HSOuq8ADW-ox9nKkfG9wimTJCKQ';
const supabase = createClient(url, key, { auth: { autoRefreshToken: false, persistSession: false } });

async function fix() {
  const { data: users } = await supabase.auth.admin.listUsers();
  const admin = users?.users?.find(u => u.email === 'inf.gonzalez27@gmail.com');
  if (!admin) {
    console.log('Admin not found');
    return;
  }

  const { data: allEmpresas } = await supabase.from('empresas').select('*');
  console.log(`Found ${allEmpresas.length} empresas.`);

  for (const emp of allEmpresas) {
    const { error } = await supabase.from('usuarios_empresas').upsert({
      user_id: admin.id,
      empresa_id: emp.id,
      rol: 'admin' // Or 'gerente'
    }, { onConflict: 'user_id, empresa_id' });
    
    if (error) {
      console.error('Error linking:', emp.nombre_empresa, error.message);
    } else {
      console.log('Linked to:', emp.nombre_empresa);
    }
  }
}
fix();
