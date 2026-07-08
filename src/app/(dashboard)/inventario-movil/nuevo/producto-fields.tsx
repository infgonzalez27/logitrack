"use client";

import { useState } from "react";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";

type ProductoOption = {
  id: string;
  nombre: string;
  codigo_barras: string | null;
};

export function ProductoFields({ productos }: { productos: ProductoOption[] }) {
  const [productoId, setProductoId] = useState("");

  const seleccionado = productos.find((p) => p.id === productoId);

  return (
    <>
      <Select
        label="Producto"
        name="producto_id"
        required
        placeholder="Selecciona producto"
        value={productoId}
        onChange={(e) => setProductoId(e.target.value)}
        options={productos.map((p) => ({
          value: p.id,
          label: p.nombre,
        }))}
      />
      <Input
        label="Código de producto"
        readOnly
        tabIndex={-1}
        placeholder="—"
        value={seleccionado?.codigo_barras ?? ""}
        className="bg-lt-surface-muted text-lt-text-muted"
      />
    </>
  );
}
