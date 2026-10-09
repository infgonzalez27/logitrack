import { ReporteEntregasResponse } from "@/lib/actions/reporte-entregas";
import { formatNumber } from "@/lib/format";
import Image from "next/image";

type Props = {
  data: ReporteEntregasResponse;
  empresaNombre: string | null;
};

export function EntregasReporte({ data, empresaNombre }: Props) {
  let totalCargados = 0;
  let totalEntregados = 0;
  let totalDevolucion = 0;

  return (
    <div className="mx-auto w-full max-w-[800px] bg-white p-8 text-black">
      <div className="mb-6 flex flex-col items-center">
        <Image
          src="/logo-dark.png"
          alt="LogiTrack"
          width={180}
          height={60}
          className="mb-4 h-12 w-auto object-contain"
        />
        <h1 className="text-xl font-bold uppercase tracking-wide">
          {empresaNombre ?? "EMPRESA"}
        </h1>
        <h2 className="mt-2 text-lg font-semibold uppercase">
          REPORTE PRODUCTOS ENTREGADOS
        </h2>
      </div>

      <div className="space-y-8">
        {data.entregas.map((entrega) => {
          let clienteCargados = 0;
          let clienteEntregados = 0;
          let clienteDevolucion = 0;

          return (
            <div key={entrega.cliente_id} className="text-sm">
              <div className="mb-2 grid grid-cols-[150px_1fr] font-bold">
                <span className="uppercase">CLIENTE</span>
                <span className="uppercase">{entrega.razon_social}</span>
              </div>
              <table className="w-full">
                <thead>
                  <tr className="border-b border-black text-left uppercase">
                    <th className="py-1">PRODUCTO</th>
                    <th className="py-1 text-right">CARGADOS</th>
                    <th className="py-1 text-right">ENTREGADOS</th>
                    <th className="py-1 text-right">DEVOLUCIÓN</th>
                  </tr>
                </thead>
                <tbody>
                  {entrega.productos.map((prod) => {
                    clienteCargados += prod.cantidad_cargada;
                    clienteEntregados += prod.cantidad_entregada;
                    clienteDevolucion += prod.devolucion;
                    
                    totalCargados += prod.cantidad_cargada;
                    totalEntregados += prod.cantidad_entregada;
                    totalDevolucion += prod.devolucion;

                    return (
                      <tr key={prod.producto_id}>
                        <td className="py-1">{prod.nombre}</td>
                        <td className="py-1 text-right">{formatNumber(prod.cantidad_cargada)}</td>
                        <td className="py-1 text-right">{formatNumber(prod.cantidad_entregada)}</td>
                        <td className="py-1 text-right">{formatNumber(prod.devolucion)}</td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          );
        })}

        <div className="mt-8">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-black text-left font-bold uppercase">
                <th className="py-1">TOTALES</th>
                <th className="py-1 text-right">CARGADOS</th>
                <th className="py-1 text-right">ENTREGADOS</th>
                <th className="py-1 text-right">DEVOLUCIÓN</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td className="py-1"></td>
                <td className="py-1 text-right">{formatNumber(totalCargados)}</td>
                <td className="py-1 text-right">{formatNumber(totalEntregados)}</td>
                <td className="py-1 text-right">{formatNumber(totalDevolucion)}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
