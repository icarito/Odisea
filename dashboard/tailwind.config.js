/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        'bg-primary': '#0c0e12',
        'bg-card': '#13161c',
        'border-custom': '#232833',
        'text-primary': '#d7dbe0',
        'text-muted': '#6b7280',
        'accent': '#7fd1ff',
        'success': '#3fb950',
        'warning': '#d29922',
        'danger': '#f85149',
      },
      fontFamily: {
        mono: ['ui-monospace', 'SFMono-Regular', 'Menlo', 'Consolas', 'monospace'],
      },
    },
  },
  plugins: [],
}
