import { notFound } from "next/navigation";
import { obtenerProductoParaEditarAction } from "@/lib/actions/productos";
import { listarTiposContenedoresAction } from "@/lib/actions/ordenes";
import { PageHeader } from "@/components/layout/page-header";
import { ProductoEditarForm } from "./producto-editar-form";

export default async function ProductoEditarPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const [result, contenedoresResult] = await Promise.all([
    obtenerProductoParaEditarAction(id),
    listarTiposContenedoresAction(),
  ]);

  if (!result.ok) {
    notFound();
  }

  const contenedores = contenedoresResult.ok
    ? contenedoresResult.contenedores.map((c) => ({
        id: c.id,
        nombre: c.nombre,
      }))
    : [];

  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <PageHeader
        title="Editar producto"
        description={result.producto.nombre}
      />
      <ProductoEditarForm
        producto={result.producto}
        contenedores={contenedores}
      />
    </div>
  );
}
