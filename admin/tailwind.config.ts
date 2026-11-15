import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        bg: "#0A0A14",
        surface: "#13131F",
        border: "#24243A",
        muted: "#9A9AB5",
        primary: "#7C5CFF",
        accent: "#FF5CA8",
        gold: "#FFC94D",
        success: "#35D07F",
        warning: "#FFB020",
        danger: "#FF4D5E",
      },
      fontFamily: { sans: ["Poppins", "system-ui", "sans-serif"] },
      backgroundImage: {
        brand: "linear-gradient(135deg,#6A5CFF,#9B5CFF,#FF5CA8)",
      },
    },
  },
  plugins: [],
};
export default config;
