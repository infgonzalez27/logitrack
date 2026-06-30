import { ImageResponse } from "next/og";

export const size = { width: 180, height: 180 };
export const contentType = "image/png";

export default function AppleIcon() {
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
          borderRadius: 32,
        }}
      >
        <svg width="96" height="96" viewBox="0 0 24 24" fill="none">
          <path
            d="M3 7h11v8H3V7zm11 2h4l3 3v3h-7V9z"
            stroke="white"
            strokeWidth="1.75"
            strokeLinejoin="round"
          />
          <circle cx="7" cy="17" r="2" fill="white" />
          <circle cx="17" cy="17" r="2" fill="white" />
        </svg>
      </div>
    ),
    { width: 180, height: 180 },
  );
}
