"use client";

import { useEffect } from "react";
import { applyLocale } from "../lib/i18n";

/** Monté une fois dans le layout : applique <html lang> + dir (RTL) au montage. */
export default function LocaleSetup() {
  useEffect(() => {
    applyLocale();
  }, []);
  return null;
}
