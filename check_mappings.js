const { createClient } = require('@supabase/supabase-js');
const url = 'https://egwryptydgxdnjvwtrfq.supabase.co';
const key = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVnd3J5cHR5ZGd4ZG5qdnd0cmZxIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4MjczODc0NCwiZXhwIjoyMDk4MzE0NzQ0fQ.BqKqWbUUodDvPkV-HSOuq8ADW-ox9nKkfG9wimTJCKQ';
const supabase = createClient(url, key, { auth: { autoRefreshToken: false, persistSession: false } });

async function check() {
  const { data: users } = await supabase.auth.admin.listUsers();
  const { data: emp } = await supabase.from('usuarios_empresas').select('*');
  const { data: empDetails } = await supabase.from('empresas').select('*');
  console.log('Users mapped:');
  users.users.forEach(u => {
    const mapping = emp.find(e => e.user_id === u.id);
    const empresa = mapping ? empDetails.find(ed => ed.id === mapping.empresa_id) : null;
    console.log(`- ${u.email}: ${empresa ? empresa.codigo_empresa : 'NO MAPPING'}`);
  });
}
check();
