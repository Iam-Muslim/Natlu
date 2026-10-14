# The Great Quran — On-Device Recitation AI & Developer Portal
### القرآن العظيم — محرك تتبع التلاوة والذكاء الاصطناعي الصوتي

The official landing page and developer documentation portal for `recite_quran` Flutter/Dart package and Natlu Mus'haf application.

---

## 📸 How to Change App Screenshots Later

All screenshots displayed on the landing page are located in the `public/screenshots/` directory:

```
public/screenshots/
├── fatiha.png       # Screenshot 1: Real-Time Word Tracking (1080 x 2340)
├── qamar.png        # Screenshot 2: 15-Line Madani Mus'haf Layout (1080 x 2340)
├── search.png       # Screenshot 3: "Recite to Navigate" Voice Search (1080 x 2340)
├── yusuf.png        # Screenshot 4: Surah View & Navigation (1080 x 2340)
└── og-preview.png   # Social Share Card for WhatsApp, X/Twitter, Discord (1200 x 630)
```

### Method 1: Replace Images (Zero Code Changes)
1. Export your new app screenshots in PNG format (recommended standard phone resolution: `1080 x 2340` or standard 19.5:9 aspect ratio).
2. Save them with the exact names above (`fatiha.png`, `qamar.png`, `search.png`, `yusuf.png`).
3. Overwrite the files inside `public/screenshots/`.
4. Rebuild or push to GitHub — your new screenshots will appear immediately!

### Method 2: Add or Rename Screenshots & Edit Text
If you want to add more screenshots or change titles and descriptions:
1. Put the new images into `public/screenshots/your_new_image.png`.
2. Open `src/data/recitationData.ts` and locate the `APP_SCREENSHOTS` array.
3. Edit or add an entry:
```typescript
{
  id: 'new_feature',
  title: 'Your English Title',
  titleAr: 'عنوان الميزة بالعربية',
  tagline: 'Short English tagline',
  taglineAr: 'وصف موجز بالعربية',
  image: '/screenshots/your_new_image.png',
  featureKey: 'Feature Category',
  highlights: ['Feature bullet 1', 'Feature bullet 2'],
  highlightsAr: ['نقطة تفصيلية 1', 'نقطة تفصيلية 2']
}
```

---

## 🎨 How to Change the Site Favicon / App Icon

The browser tab icon is stored as an SVG in:
`public/favicon.svg`

It matches the 5-bar voice waveform logo of the app. You can replace `public/favicon.svg` with any custom SVG or PNG icon.

---

## 🚀 Quick Start (Local Development)

```bash
# 1. Install dependencies
npm install

# 2. Start the local Vite development server
npm run dev
```

Visit `http://localhost:3000` in your browser.

---

## 📦 Production Build

```bash
# Build the optimized production bundle
npm run build
```

This compiles all TypeScript and Tailwind CSS assets into the `dist/` directory.

---

## 🌐 Deploying to Cloudflare Pages via GitHub

### Step 1: Push to your GitHub Repository

```bash
git init
git add .
git commit -m "feat: The Great Quran landing page"
git branch -M main
git remote add origin https://github.com/<your-username>/<your-repo-name>.git
git push -u origin main
```

*(Note: `node_modules` and `dist` are already in `.gitignore`)*

### Step 2: Connect to Cloudflare Pages

1. Log into your **Cloudflare Dashboard** (`https://dash.cloudflare.com`).
2. Navigate to **Workers & Pages** > **Create application** > **Pages** > **Connect to Git**.
3. Select your GitHub repository (`<your-repo-name>`).
4. In the **Build configuration** section, enter the following settings:
   - **Framework preset**: `Vite`
   - **Build command**: `npm run build`
   - **Build output directory**: `dist`
   - **Root directory**: `/` (leave empty)
5. Under **Environment variables** (Recommended):
   - Variable name: `NODE_VERSION`
   - Value: `20` (or `22`)
6. Click **Save and Deploy**.

Cloudflare will automatically build and publish your landing page worldwide on Cloudflare's ultra-fast global edge network with free automated SSL certificates.

---

## 🛠️ Stack & Architecture

- **React 19** + **TypeScript**
- **Vite 8** (Ultra-fast build and HMR)
- **Tailwind CSS v4** + `@tailwindcss/vite`
- **Lucide Icons**
- **Arabic Quranic Typography**: `Amiri Quran`, `Amiri`, `Tajawal`, `Cairo`, `IBM Plex Sans Arabic`, `Scheherazade New`
