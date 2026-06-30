import type { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "LogiTrack",
    short_name: "LogiTrack",
    description:
      "Sistema de distribución, inventario y despacho logístico",
    start_url: "/ordenes",
    scope: "/",
    display: "standalone",
    orientation: "portrait-primary",
    background_color: "#f5faff",
    theme_color: "#5b9bd5",
    lang: "es",
    categories: ["business", "productivity", "logistics"],
    icons: [
      {
        src: "/icon/192",
        sizes: "192x192",
        type: "image/png",
        purpose: "any",
      },
      {
        src: "/icon/512",
        sizes: "512x512",
        type: "image/png",
        purpose: "any",
      },
      {
        src: "/icon/512",
        sizes: "512x512",
        type: "image/png",
        purpose: "maskable",
      },
    ],
  };
}
