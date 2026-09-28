"use client";

import { useState } from "react";
import {
  ClienteCombobox,
  type ClienteComboboxOption,
} from "@/components/clientes/cliente-combobox";

export function ProductoPicker({
  productos,
}: {
  productos: ClienteComboboxOption[];
}) {
  const [productoId, setProductoId] = useState("");

  return (
    <ClienteCombobox
      label="Producto"
      name="producto_id"
      required
      placeholder="Buscar producto por nombre…"
      emptyMessage="Sin productos que coincidan."
      options={productos}
      value={productoId}
      onChange={setProductoId}
    />
  );
}
