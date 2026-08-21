// PWA Installation & Offline Service Worker Manager for Recite Quran (اتلو القران)
(function() {
  let deferredInstallPrompt = null;

  // 1. Check if the app is already installed or running as a standalone PWA
  const isStandalone = window.matchMedia('(display-mode: standalone)').matches || 
                       window.navigator.standalone === true ||
                       window.location.search.includes('source=pwa') ||
                       localStorage.getItem('pwa_installed') === 'true';

  // 2. Register Service Worker for offline functionality, background updates & COOP/COEP support
  if ('serviceWorker' in navigator) {
    window.addEventListener('load', () => {
      navigator.serviceWorker.register('sw.js').then((reg) => {
        console.log('[PWA] ServiceWorker registered with scope:', reg.scope);
        // Automatically check for new versions on launch when online
        if (navigator.onLine) {
          reg.update().catch(console.warn);
        }
      }).catch((err) => {
        console.warn('[PWA] ServiceWorker registration failed:', err);
      });
    });
  }

  // If already installed, NEVER show any install banner or prompt
  if (isStandalone) {
    console.log('[PWA] Running in standalone/installed mode. Suppressing install prompts.');
    return;
  }

  // Listen for successful installation from browser
  window.addEventListener('appinstalled', () => {
    console.log('[PWA] Application successfully installed to home screen.');
    deferredInstallPrompt = null;
    localStorage.setItem('pwa_installed', 'true');
    const banner = document.getElementById('pwa-install-banner');
    const iosBanner = document.getElementById('pwa-ios-banner');
    if (banner) banner.style.display = 'none';
    if (iosBanner) iosBanner.style.display = 'none';
  });

  // 3. Android / Windows / Chromium Automatic Install Prompt
  // Only shows when the browser confirms the app is installable and not installed
  window.addEventListener('beforeinstallprompt', (e) => {
    e.preventDefault();
    deferredInstallPrompt = e;
    console.log('[PWA] beforeinstallprompt captured.');
    
    // Show banner after brief delay
    setTimeout(showInstallBanner, 2000);
  });

  function showInstallBanner() {
    if (localStorage.getItem('pwa_installed') === 'true' || isStandalone) return;
    const banner = document.getElementById('pwa-install-banner');
    const installBtn = document.getElementById('pwa-install-btn');
    const closeBtn = document.getElementById('pwa-close-btn');

    if (!banner || !installBtn) return;
    banner.style.display = 'block';

    installBtn.onclick = async () => {
      if (deferredInstallPrompt) {
        deferredInstallPrompt.prompt();
        const choiceResult = await deferredInstallPrompt.userChoice;
        console.log(`[PWA] Install prompt outcome: ${choiceResult.outcome}`);
        if (choiceResult.outcome === 'accepted') {
          localStorage.setItem('pwa_installed', 'true');
        }
        deferredInstallPrompt = null;
        banner.style.display = 'none';
      }
    };

    if (closeBtn) {
      closeBtn.onclick = () => {
        banner.style.display = 'none';
      };
    }
  }

  // 4. iOS Safari Guided Install Prompt
  const isIos = /iphone|ipad|ipod/.test(navigator.userAgent.toLowerCase()) || 
                (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);

  const isInAppBrowser = /(FBAN|FBAV|Instagram|Twitter|Line|WhatsApp|Snapchat|Telegram)/i.test(navigator.userAgent);

  if (isIos && !isStandalone && !isInAppBrowser) {
    const isSafari = /safari/.test(navigator.userAgent.toLowerCase()) && 
                     !/crios|fxios|opios|mercury|edgios/i.test(navigator.userAgent);
    if (isSafari) {
      setTimeout(() => {
        if (localStorage.getItem('pwa_installed') === 'true' || isStandalone) return;
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
