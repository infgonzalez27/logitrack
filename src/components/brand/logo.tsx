import Image from "next/image";
import Link from "next/link";

const IMAGE_SIZES = {
  sm: 32,
  md: 40,
  lg: 48,
  xl: 72,
} as const;

type LogoProps = {
  size?: keyof typeof IMAGE_SIZES;
  layout?: "row" | "stacked";
  showWordmark?: boolean;
  subtitle?: string;
  href?: string;
  onNavigate?: () => void;
  className?: string;
  imageClassName?: string;
};

export function Logo({
  size = "md",
  layout = "row",
  showWordmark = true,
  subtitle,
  href,
  onNavigate,
  className = "",
  imageClassName = "",
}: LogoProps) {
  const imageSize = IMAGE_SIZES[size];
  const isStacked = layout === "stacked";

  const content = (
    <div
      className={`flex ${isStacked ? "flex-col items-center text-center" : "items-center"} gap-3 ${className}`}
    >
      <Image
        src="/icons/icon-192.png"
        alt="LogiTrack"
        width={imageSize}
        height={imageSize}
        className={`shrink-0 rounded-2xl shadow-[var(--lt-shadow-soft)] ${imageClassName}`}
        priority={size === "xl"}
      />
      {showWordmark ? (
        <div className={isStacked ? "space-y-1" : undefined}>
          <p
            className={`font-display font-bold tracking-tight text-lt-text ${
              size === "xl"
                ? "text-2xl"
                : size === "lg"
                  ? "text-lg"
                  : "text-sm"
            }`}
          >
            LogiTrack
          </p>
          {subtitle ? (
            <p className="text-sm text-lt-text-muted">{subtitle}</p>
          ) : null}
        </div>
      ) : null}
    </div>
  );

  if (href) {
    return (
      <Link
        href={href}
        onClick={() => onNavigate?.()}
        className="inline-flex transition-opacity hover:opacity-90"
      >
        {content}
      </Link>
    );
  }

  return content;
}
