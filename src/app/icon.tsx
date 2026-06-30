import { ImageResponse } from "next/og";

export const contentType = "image/png";

export function generateImageMetadata() {
  return [
    {
      id: "default",
      size: { width: 32, height: 32 },
      contentType: "image/png",
    },
    {
      id: "192",
      size: { width: 192, height: 192 },
      contentType: "image/png",
    },
    {
      id: "512",
      size: { width: 512, height: 512 },
      contentType: "image/png",
    },
  ];
}

function iconSize(id: string) {
  if (id === "512") return 512;
  if (id === "192") return 192;
  return 32;
}

export default function Icon({ id }: { id: string }) {
  const size = iconSize(id);
  const truckScale = size / 32;

  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          background: "linear-gradient(145deg, #5b9bd5 0%, #b8d4f0 100%)",
          borderRadius: size >= 192 ? size * 0.18 : size * 0.22,
        }}
      >
        <svg
          width={size * 0.55}
          height={size * 0.55}
          viewBox="0 0 24 24"
          fill="none"
        >
          <path
            d="M3 7h11v8H3V7zm11 2h4l3 3v3h-7V9z"
            stroke="white"
            strokeWidth={1.75 * truckScale}
            strokeLinejoin="round"
          />
          <circle cx="7" cy="17" r="2" fill="white" />
          <circle cx="17" cy="17" r="2" fill="white" />
        </svg>
      </div>
    ),
    { width: size, height: size },
  );
}
