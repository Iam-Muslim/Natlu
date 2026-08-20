// PWA Installation & Offline Service Worker Manager for Recite Quran (اتلو القران)
(function() {
  let deferredInstallPrompt = null;
  const isStandalone = window.matchMedia('(display-mode: standalone)').matches || window.navigator.standalone === true;

  // 1. Register custom Service Worker for full offline caching and COOP/COEP support
  if ('serviceWorker' in navigator) {
    window.addEventListener('load', () => {
      navigator.serviceWorker.register('sw.js').then((reg) => {
        console.log('[PWA] Offline ServiceWorker active with scope:', reg.scope);
      }).catch((err) => {
        console.warn('[PWA] Offline ServiceWorker failed to register:', err);
      });
    });
  }

  // If already installed and running as standalone app, do not show prompts
  if (isStandalone) {
    console.log('[PWA] Running in installed standalone mode.');
    return;
  }

  // Detect iOS devices (including modern iPadOS which mimics MacIntel)
  const isIos = /iphone|ipad|ipod/.test(navigator.userAgent.toLowerCase()) || 
                (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);

  const isInAppBrowser = /(FBAN|FBAV|Instagram|Twitter|Line|WhatsApp|Snapchat|Telegram)/i.test(navigator.userAgent);

  // Listen for successful installation by the browser
  window.addEventListener('appinstalled', () => {
    console.log('[PWA] Application successfully installed.');
    deferredInstallPrompt = null;
    const banner = document.getElementById('pwa-install-banner');
    const iosBanner = document.getElementById('pwa-ios-banner');
    if (banner) banner.style.display = 'none';
    if (iosBanner) iosBanner.style.display = 'none';
  });

  // 2. Android / Chromium / Desktop Install Prompt
  window.addEventListener('beforeinstallprompt', (e) => {
    e.preventDefault();
    deferredInstallPrompt = e;
    console.log('[PWA] beforeinstallprompt captured (app is not installed).');
    showInstallBanner();
  });

  function showInstallBanner() {
    if (isStandalone) return;
    const banner = document.getElementById('pwa-install-banner');
    const installBtn = document.getElementById('pwa-install-btn');
    const closeBtn = document.getElementById('pwa-close-btn');

    if (!banner || !installBtn) return;
    banner.style.display = 'block';

    installBtn.onclick = async () => {
      if (deferredInstallPrompt) {
        deferredInstallPrompt.prompt();
        const choiceResult = await deferredInstallPrompt.userChoice;
        console.log(`[PWA] User install choice: ${choiceResult.outcome}`);
        deferredInstallPrompt = null;
        banner.style.display = 'none';
      } else {
        // If Chrome hasn't fired beforeinstallprompt yet or browser requires manual add:
        const sub = banner.querySelector('.pwa-subtitle');
        const subEn = banner.querySelector('.pwa-subtitle-en');
        if (sub) sub.innerHTML = 'اضغط على قائمة المتصفح <strong>(⋮)</strong> ثم اختر <strong>"تثبيت التطبيق"</strong> أو <strong>"إضافة للشاشة الرئيسية"</strong>';
        if (subEn) subEn.innerHTML = 'Tap browser menu <strong>(⋮)</strong> then select <strong>"Install app"</strong> or <strong>"Add to Home screen"</strong>';
        installBtn.style.display = 'none';
      }
    };

    if (closeBtn) {
      closeBtn.onclick = () => {
        banner.style.display = 'none';
      };
    }
  }

  // Proactively trigger banner after brief delay on Android / Desktop if not standalone
  if (!isIos && !isStandalone && !isInAppBrowser) {
    setTimeout(showInstallBanner, 2500);
  }

  // 3. iOS Safari Custom Add to Home Screen Prompt
  if (isIos && !isStandalone && !isInAppBrowser) {
    const isSafari = /safari/.test(navigator.userAgent.toLowerCase()) && 
                     !/crios|fxios|opios|mercury|edgios/i.test(navigator.userAgent);
    if (isSafari) {
      setTimeout(() => {
        if (isStandalone) return;
        const iosBanner = document.getElementById('pwa-ios-banner');
        const iosCloseBtn = document.getElementById('pwa-ios-close-btn');
        if (iosBanner) {
          iosBanner.style.display = 'block';
          if (iosCloseBtn) {
            iosCloseBtn.onclick = () => {
              iosBanner.style.display = 'none';
            };
          }
        }
      }, 3000);
    }
  }
})();
