/** @type {import('tailwindcss').Config} */
export default {
  darkMode: 'class', // .darkクラスベースのダークモードを有効化
  content: [
    './src/**/*.{astro,html,js,jsx,md,mdx,svelte,ts,tsx,vue}'
  ],
  theme: {
    extend: {
      fontSize: {
        // Base font size is 14px, so adjust Tailwind's default text sizes accordingly
        xs: '0.714rem',    // 10px
        sm: '0.857rem',    // 12px
        base: '1rem',      // 14px
        lg: '1.143rem',    // 16px
        xl: '1.286rem',    // 18px
        '2xl': '1.429rem', // 20px
        '3xl': '1.714rem', // 24px
        '4xl': '2rem',     // 28px
        '5xl': '2.286rem', // 32px
        '6xl': '2.857rem', // 40px
      }
    }
  }
}
