'use server';

import { createClient } from '@/lib/supabase/server';
import { revalidatePath } from 'next/cache';
import { createClient as createSupabaseClient } from '@supabase/supabase-js';
import postgres from 'postgres';
import fs from 'fs';
import path from 'path';
import crypto from 'crypto';

interface RPCResponse<T> {
  success: boolean;
  data: T | null;
  error: {
    code: string;
    message: string;
    details: string | null;
  } | null;
}

interface CrearEmpresaData {
  empresa_id: string;
  codigo_empresa: string;
  nombre_empresa: string;
}

interface AsignarUsuarioEmpresaData {
  asignacion_id: string;
  user_id: string;
  empresa_id: string;
  rol: string;
}

const SUPABASE_API_URL = 'https://api.supabase.com/v1/projects';
const SUPABASE_ACCESS_TOKEN = process.env.SUPABASE_ACCESS_TOKEN!;
const SUPABASE_ORG_ID = process.env.SUPABASE_ORG_ID!;
const REGION = 'us-east-1'; // default region

async function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Llama a la base de datos central para crear una nueva empresa y a su usuario Gerente
 */
export async function submitCrearEmpresaAction(formData: FormData) {
  const supabase = await createClient(); 
  
  const codigoEmpresa = formData.get('codigoEmpresa') as string;
  const nombreEmpresa = formData.get('nombreEmpresa') as string;
  const gerenteEmail = formData.get('gerenteEmail') as string;
  const gerentePassword = formData.get('gerentePassword') as string;

  if (!SUPABASE_ACCESS_TOKEN || !SUPABASE_ORG_ID) {
    return { success: false, error: 'Faltan credenciales de Management API en el servidor.', code: 'ENV_ERROR' };
  }

  // Generar un password aleatorio seguro para la nueva DB
  const dbPass = crypto.randomBytes(16).toString('hex') + 'Aa1!';
  
  // 1. Llamar a la Management API para aprovisionar el proyecto
  let projectRef = '';
  try {
    const createRes = await fetch(SUPABASE_API_URL, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${SUPABASE_ACCESS_TOKEN}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        name: nombreEmpresa,
        organization_id: SUPABASE_ORG_ID,
        region: REGION,
        db_pass: dbPass,
        plan: 'free' // Especificamos el plan gratuito
      })
    });
    
    if (!createRes.ok) {
      const errTxt = await createRes.text();
      return { success: false, error: `Error de Supabase creando el proyecto: ${errTxt}`, code: 'API_ERROR' };
    }
    
    const projData = await createRes.json();
    projectRef = projData.id;
  } catch (err: any) {
    return { success: false, error: `Excepción interna creando proyecto: ${err.message}`, code: 'API_ERROR' };
  }
  
  // 2. Polling: Esperar a que el servidor esté activo (ACTIVE_HEALTHY)
  let isReady = false;
  let anonKey = '';
  let apiUrl = '';
  
  // Esperar un máximo de 4 minutos (24 intentos de 10 seg)
  for (let i = 0; i < 24; i++) {
    await sleep(10000); 
    
    const checkRes = await fetch(`${SUPABASE_API_URL}/${projectRef}`, {
      headers: { 'Authorization': `Bearer ${SUPABASE_ACCESS_TOKEN}` }
    });
    
    if (checkRes.ok) {
      const projInfo = await checkRes.json();
      if (projInfo.status === 'ACTIVE_HEALTHY') {
        isReady = true;
        // Cuando está listo, extraemos las API Keys generadas
        const keysRes = await fetch(`${SUPABASE_API_URL}/${projectRef}/api-keys`, {
          headers: { 'Authorization': `Bearer ${SUPABASE_ACCESS_TOKEN}` }
        });
        
        if (keysRes.ok) {
          const keysData = await keysRes.json();
          const anon = keysData.find((k: any) => k.name === 'anon');
          if (anon) {
            anonKey = anon.api_key;
            apiUrl = `https://${projectRef}.supabase.co`;
          }
        }
        break;
      }
    }
  }
  
  if (!isReady || !anonKey || !apiUrl) {
    return { success: false, error: 'Tiempo de espera agotado aprovisionando el proyecto en Supabase.', code: 'TIMEOUT' };
  }
  
  // 3. Inyección del Molde (Clonar tablas a través de SQL directo)
  // Utilizamos el puerto 5432 directo (no pooler 6543) para migraciones largas
  const dbUrl = `postgres://postgres.${projectRef}:${dbPass}@aws-0-${REGION}.pooler.supabase.com:5432/postgres`;
  try {
    const sqlScriptPath = path.join(process.cwd(), 'supabase', 'schema_base.sql');
    
    // Conectarse a la nueva DB
    const sql = postgres(dbUrl, { max: 1, idle_timeout: 10 });
    
    // Inyectar el archivo SQL completo, esto arrojará error si hay fallos en las tablas
    await sql.file(sqlScriptPath);
    await sql.end();
  } catch (err: any) {
    return { success: false, error: `Error clonando tablas en el nuevo servidor: ${err.message}`, code: 'DB_INIT_ERROR' };
  }

  // 4. Registrar en el Enrutador Central de LogiTrack
  const paramsEmpresa = {
    p_codigo_empresa: codigoEmpresa,
    p_nombre_empresa: nombreEmpresa,
    p_supabase_url: apiUrl,
    p_supabase_anon_key: anonKey
  };

  const { data: dataEmpresa, error: errorEmpresa } = await supabase.rpc('crea_nueva_empresa', paramsEmpresa);

  if (errorEmpresa) return { success: false, error: errorEmpresa.message, code: 'API_ERROR' };
  
  const responseEmpresa = dataEmpresa as RPCResponse<CrearEmpresaData>;
  if (!responseEmpresa.success || !responseEmpresa.data) {
    return { success: false, error: responseEmpresa.error?.message || 'Error al guardar en el enrutador.', code: responseEmpresa.error?.code };
  }

  const empresaId = responseEmpresa.data.empresa_id;

  // 5. Crear al usuario Gerente en la Auth Central (Requiere SERVICE_ROLE_KEY)
  const supabaseAdmin = createSupabaseClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!
  );

  const { data: authData, error: authError } = await supabaseAdmin.auth.admin.createUser({
    email: gerenteEmail,
    password: gerentePassword,
    email_confirm: true
  });

  if (authError) {
    return { success: false, error: `La empresa se creó, pero falló la creación del usuario: ${authError.message}`, code: 'AUTH_ERROR' };
  }

  // 6. Asignar el nuevo usuario a la empresa con el rol de 'gerente'
  const paramsAsignacion = {
    p_user_id: authData.user.id,
    p_empresa_id: empresaId,
    p_rol: 'gerente'
  };

  const { data: dataAsignacion, error: errorAsignacion } = await supabase.rpc('asignar_usuario_empresa', paramsAsignacion);

  if (errorAsignacion) {
     return { success: false, error: `Usuario creado, pero falló la asignación a la empresa: ${errorAsignacion.message}`, code: 'API_ERROR' };
  }

  revalidatePath('/admin/empresas');
  
  // 7. Finalizado con éxito
  return {
    success: true,
    data: {
      ...responseEmpresa.data,
      gerente_id: authData.user.id,
      gerente_email: authData.user.email,
      mensaje: `¡El servidor para ${responseEmpresa.data.nombre_empresa} fue aprovisionado e inicializado exitosamente!`
    }
  };
}

/**
 * Llama a la base de datos central para asignar un usuario a una empresa
 */
export async function submitAsignarUsuarioEmpresaAction(formData: FormData) {
  const supabase = await createClient(); 
  
  const params = {
    p_user_id: formData.get('userId'),
    p_empresa_id: formData.get('empresaId'),
    p_rol: formData.get('rol') || 'operador'
  };

  const { data, error } = await supabase.rpc('asignar_usuario_empresa', params);

  if (error) {
    return {
      success: false,
      error: error.message,
      code: 'API_ERROR'
    };
  }

  const response = data as RPCResponse<AsignarUsuarioEmpresaData>;

  if (!response.success) {
    return {
      success: false,
      error: response.error?.message || 'Error al asignar el usuario a la empresa.',
      code: response.error?.code
    };
  }

  revalidatePath('/admin/usuarios');
  
  return {
    success: true,
    data: response.data
  };
}
