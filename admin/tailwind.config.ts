import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        bg: "#090F1E",
        surface: "#141D32",
        border: "#293956",
        muted: "#AFC0D9",
        primary: "#3478F6",
        accent: "#FF8A65",
        gold: "#FFC94D",
        success: "#35D07F",
        warning: "#FFB020",
        danger: "#FF4D5E",
      },
      fontFamily: { sans: ["Inter", "system-ui", "sans-serif"] },
      backgroundImage: {
        brand: "linear-gradient(135deg,#3478F6,#245ED1)",
      },
    },
  },
  plugins: [],
};
export default config;
