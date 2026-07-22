import { listarProductosAction } from "@/lib/actions/productos";
import { PageHeader } from "@/components/layout/page-header";
import { Button } from "@/components/ui/button";
import { PrintButton } from "@/components/print/print-button";
import { ProductosListaClient } from "./productos-lista-client";

export default async function ProductosPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string }>;
}) {
  const { q = "" } = await searchParams;
  const result = await listarProductosAction(q);

  return (
    <div className="lt-print-document space-y-4">
      <div className="lt-no-print">
        <PageHeader
          title="Productos"
          action={
            <div className="flex flex-wrap gap-2">
              <PrintButton label="Imprimir listado" />
              <Button href="/productos/nuevo">Nuevo producto</Button>
            </div>
          }
        />
      </div>

      <ProductosListaClient
        initialProductos={result.ok ? result.productos : []}
        initialQuery={q}
        initialError={result.ok ? null : result.error}
      />
    </div>
  );
}
