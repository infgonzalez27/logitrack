import Link from "next/link";
import { listarProductosAction } from "@/lib/actions/productos";
import { PageHeader } from "@/components/layout/page-header";
import { Button } from "@/components/ui/button";
import { DataTable } from "@/components/ui/data-table";
import { Card } from "@/components/ui/card";
import { formatNumber } from "@/lib/format";
import { ProductosBusqueda } from "./productos-busqueda";

export default async function ProductosPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string }>;
}) {
  const { q = "" } = await searchParams;
  const result = await listarProductosAction(q);
  const productos = result.ok ? result.productos : [];

  return (
    <div className="space-y-6">
      <PageHeader
        title="Productos"
        action={<Button href="/productos/nuevo">Nuevo producto</Button>}
      />

      <ProductosBusqueda defaultValue={q} />

      {!result.ok && (
        <p className="text-sm text-lt-danger-text">{result.error}</p>
      )}

      <Card>
        <DataTable
          columns={[
            { key: "codigo", label: "Código" },
            { key: "nombre", label: "Nombre" },
            { key: "barras", label: "Cód. barras" },
            { key: "precio", label: "Precio lista 1" },
            { key: "stock", label: "Stock" },
            { key: "acciones", label: "" },
          ]}
          rows={productos.map((p) => ({
            id: p.id,
            cells: {
              codigo: p.codigo_producto ?? "—",
              nombre: p.nombre,
              barras: p.codigo_barras ?? "—",
              precio: formatNumber(p.precio_lista1 ?? p.precio),
              stock: p.stock_disponible,
              acciones: (
                <Link
                  href={`/productos/${p.id}`}
                  className="text-sm font-medium text-lt-primary hover:underline"
                >
                  Editar
                </Link>
              ),
            },
          }))}
          emptyMessage={
            q
              ? "No se encontraron productos con ese criterio."
              : "No hay productos registrados."
          }
        />
      </Card>
    </div>
  );
}
