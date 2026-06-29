import { createClient } from "@/lib/supabase/server";
import { CAMION_ESTADOS } from "@/lib/constants";
import { PageHeader } from "@/components/layout/page-header";
import { Button } from "@/components/ui/button";
import { DataTable } from "@/components/ui/data-table";
import { Badge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import { formatNumber } from "@/lib/format";

export default async function CamionesPage() {
  const supabase = await createClient();
  const { data } = await supabase.from("camiones").select("*").order("placa");

  return (
    <div className="space-y-6">
      <PageHeader
        title="Camiones"
        action={<Button href="/camiones/nuevo">Nuevo camión</Button>}
      />
      <Card>
        <DataTable
          columns={[
            { key: "placa", label: "Placa" },
            { key: "modelo", label: "Modelo" },
            { key: "capacidad", label: "Capacidad (kg)" },
            { key: "estado", label: "Estado" },
          ]}
          rows={(data ?? []).map((c) => ({
            id: c.id,
            cells: {
              placa: c.placa,
              modelo: c.modelo,
              capacidad: formatNumber(c.capacidad_kg),
              estado: (
                <Badge>
                  {CAMION_ESTADOS.find((e) => e.value === c.estado)?.label ??
                    c.estado}
                </Badge>
              ),
            },
          }))}
        />
      </Card>
    </div>
  );
}
