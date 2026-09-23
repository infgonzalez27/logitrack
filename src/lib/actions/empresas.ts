'use server';

import { createClient } from '@/lib/supabase/server';
import { revalidatePath } from 'next/cache';

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
 * Llama a la base de datos central para crear una nueva empresa
 */
export async function submitCrearEmpresaAction(formData: FormData) {
  const supabase = await createClient(); // Cliente que resuelve a Central o Tenant
  
  const params = {
    p_codigo_empresa: formData.get('codigoEmpresa'),
    p_nombre_empresa: formData.get('nombreEmpresa'),
    p_supabase_url: formData.get('supabaseUrl'),
    p_supabase_anon_key: formData.get('supabaseAnonKey')
  };

  const { data, error } = await supabase.rpc('crea_nueva_empresa', params);

  if (error) {
    return {
      success: false,
      error: error.message,
      code: 'API_ERROR'
    };
  }

  const response = data as RPCResponse<CrearEmpresaData>;

  if (!response.success) {
    return {
      success: false,
      error: response.error?.message || 'Error al crear la empresa.',
      code: response.error?.code
    };
  }

  revalidatePath('/admin/empresas');
  
  return {
    success: true,
    data: response.data
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
