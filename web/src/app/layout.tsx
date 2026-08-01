import type { Metadata } from "next";
import { Inter } from "next/font/google";
import "./globals.css";

const inter = Inter({
  subsets: ["latin"],
  display: "swap",
  variable: "--font-inter",
});

export const metadata: Metadata = {
  title: "OpenClip — macOS Clipboard Action Engine",
  description:
    "Highlight text anywhere on macOS and run instant JavaScript, AppleScript, Shell, or URL actions. Open source, native Swift.",
  openGraph: {
    title: "OpenClip — macOS Clipboard Action Engine",
    description:
      "Highlight text anywhere on macOS and run instant actions. Open source, native Swift.",
    type: "website",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className={`${inter.variable} h-full`}>
      <body className="min-h-full flex flex-col antialiased">{children}</body>
    </html>
  );
}
