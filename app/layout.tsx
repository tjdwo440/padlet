import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "MINDLET · Personal note board",
  description: "개인용 포스트잇 메모 보드",
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="ko" className="h-full">
      <body className="min-h-full antialiased">{children}</body>
    </html>
  );
}
