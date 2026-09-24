'use server';

import { createClient } from '@/lib/supabase/server';
import { revalidatePath } from 'next/cache';
import { createClient as createSupabaseClient } from '@supabase/supabase-js';

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

/**
 * Llama a la base de datos central para crear una nueva empresa y a su usuario Gerente
 */
export async function submitCrearEmpresaAction(formData: FormData) {
  const supabase = await createClient(); 
  
  const codigoEmpresa = formData.get('codigoEmpresa') as string;
  const nombreEmpresa = formData.get('nombreEmpresa') as string;
  const gerenteEmail = formData.get('gerenteEmail') as string;
  const gerentePassword = formData.get('gerentePassword') as string;

  // 1. Crear la empresa en la tabla central
  const paramsEmpresa = {
    p_codigo_empresa: codigoEmpresa,
    p_nombre_empresa: nombreEmpresa,
    p_supabase_url: formData.get('supabaseUrl') as string,
    p_supabase_anon_key: formData.get('supabaseAnonKey') as string
  };

  const { data: dataEmpresa, error: errorEmpresa } = await supabase.rpc('crea_nueva_empresa', paramsEmpresa);

  if (errorEmpresa) return { success: false, error: errorEmpresa.message, code: 'API_ERROR' };
  
  const responseEmpresa = dataEmpresa as RPCResponse<CrearEmpresaData>;
  if (!responseEmpresa.success || !responseEmpresa.data) {
    return { success: false, error: responseEmpresa.error?.message || 'Error al crear la empresa.', code: responseEmpresa.error?.code };
  }

  const empresaId = responseEmpresa.data.empresa_id;

  // 2. Crear al usuario Gerente en la Auth Central (Requiere SERVICE_ROLE_KEY)
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
    return { success: false, error: `La empresa se creó, pero falló el usuario: ${authError.message}`, code: 'AUTH_ERROR' };
  }

  // 3. Asignar el nuevo usuario a la empresa con el rol de 'gerente'
  const paramsAsignacion = {
    p_user_id: authData.user.id,
    p_empresa_id: empresaId,
    p_rol: 'gerente'
  };

  const { data: dataAsignacion, error: errorAsignacion } = await supabase.rpc('asignar_usuario_empresa', paramsAsignacion);

  if (errorAsignacion) {
     return { success: false, error: `Usuario creado, pero falló la asignación: ${errorAsignacion.message}`, code: 'API_ERROR' };
  }

  revalidatePath('/admin/empresas');
  
  // 4. Retornar éxito con todos los datos
  return {
    success: true,
    data: {
      ...responseEmpresa.data,
      gerente_id: authData.user.id,
      gerente_email: authData.user.email,
      mensaje: `¡Empresa ${responseEmpresa.data.nombre_empresa} y su Gerente creados exitosamente!`
    }
  };
}

/**
 * Llama a la base de datos central para asignar un usuario a una empresa
 */
export async function submitAsignarUsuarioEmpresaAction(formData: FormData) {
  const supabase = await createClient(); // Cliente que resuelve a Central o Tenant
  
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
