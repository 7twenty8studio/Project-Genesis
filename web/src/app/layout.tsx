import type { Metadata, Viewport } from "next";
import { Poppins, Source_Serif_4 } from "next/font/google";
import { requestLang, requestTheme } from "@/lib/prefs.server";
import "./globals.css";

const poppins = Poppins({ subsets: ["latin", "latin-ext"], weight: ["400", "500", "600", "700"], variable: "--font-poppins" });
const serif = Source_Serif_4({ subsets: ["latin", "latin-ext"], variable: "--font-serif-body" });

export const metadata: Metadata = {
  title: { default: "Versely", template: "%s · Versely" },
  description: "Versely: a Bible study app. Church Studio and sermon outlines.",
  icons: {
    icon: [{ url: "/brand/favicon.svg", type: "image/svg+xml" }, { url: "/brand/favicon-32.png", sizes: "32x32" }],
    apple: "/brand/apple-touch-icon-180.png",
  },
};

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#f9ebd7" },
    { media: "(prefers-color-scheme: dark)", color: "#30251f" },
  ],
};

export default async function RootLayout({ children }: { children: React.ReactNode }) {
  // The visitor's language; a sermon page also marks its outline with the sermon's own language.
  const [lang, theme] = await Promise.all([requestLang(), requestTheme()]);
  return (
    <html lang={lang === "pt" ? "pt-BR" : lang} data-theme={theme} className={`${poppins.variable} ${serif.variable}`}>
      <body className="min-h-screen antialiased">{children}</body>
    </html>
  );
}
