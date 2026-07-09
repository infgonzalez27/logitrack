import { notFound } from "next/navigation";
import { obtenerProductoParaEditarAction } from "@/lib/actions/productos";
import { PageHeader } from "@/components/layout/page-header";
import { ProductoEditarForm } from "./producto-editar-form";

export default async function ProductoEditarPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const result = await obtenerProductoParaEditarAction(id);

  if (!result.ok) {
    notFound();
  }

  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <PageHeader
        title="Editar producto"
        description={result.producto.nombre}
      />
      <ProductoEditarForm producto={result.producto} />
    </div>
  );
}
