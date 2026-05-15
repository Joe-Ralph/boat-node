/** @type {import('tailwindcss').Config} */
export default {
  darkMode: 'class',
  content: [
    './index.html',
    './index.tsx',
    './App.tsx',
    './components/**/*.{ts,tsx}',
    './engine/**/*.{ts,tsx}',
    './scenes/**/*.{ts,tsx}',
    './ui/**/*.{ts,tsx}',
    './audio/**/*.{ts,tsx}',
    './interaction/**/*.{ts,tsx}',
  ],
  theme: {
    extend: {
      colors: {
        amber: {
          500: '#FFB347',
        },
      },
      fontFamily: {
        display: ['Rajdhani', 'sans-serif'],
        mono: ['"JetBrains Mono"', 'monospace'],
      },
    },
  },
  plugins: [],
};
