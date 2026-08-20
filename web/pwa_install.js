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

  // Check if dismissed in this browser session
  if (sessionStorage.getItem('pwa_prompt_dismissed') === 'true') {
    return;
  }

  const isInAppBrowser = /(FBAN|FBAV|Instagram|Twitter|Line|WhatsApp|Snapchat)/i.test(navigator.userAgent);
  const isIos = /iphone|ipad|ipod/.test(navigator.userAgent.toLowerCase()) && !window.MSStream;

  // Listen for successful installation by the browser
  window.addEventListener('appinstalled', () => {
    console.log('[PWA] Application successfully installed.');
    deferredInstallPrompt = null;
    const banner = document.getElementById('pwa-install-banner');
    const iosBanner = document.getElementById('pwa-ios-banner');
    if (banner) banner.style.display = 'none';
    if (iosBanner) iosBanner.style.display = 'none';
    sessionStorage.setItem('pwa_prompt_dismissed', 'true');
  });

  // 2. Android / Chromium / Desktop Install Prompt (Only fires if NOT already installed)
  window.addEventListener('beforeinstallprompt', (e) => {
    e.preventDefault();
    deferredInstallPrompt = e;
    console.log('[PWA] beforeinstallprompt captured (app is not installed).');
    
    setTimeout(showInstallBanner, 2000);
  });

  function showInstallBanner() {
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
        if (choiceResult.outcome === 'accepted') {
          sessionStorage.setItem('pwa_prompt_dismissed', 'true');
        }
      }
    };

    if (closeBtn) {
      closeBtn.onclick = () => {
        banner.style.display = 'none';
        sessionStorage.setItem('pwa_prompt_dismissed', 'true');
      };
    }
  }

  // 3. iOS Safari Custom Add to Home Screen Prompt
  if (isIos && !isStandalone && !isInAppBrowser) {
    const isSafari = /safari/.test(navigator.userAgent.toLowerCase()) && !/crios|fxios/.test(navigator.userAgent.toLowerCase());
    if (isSafari) {
      setTimeout(() => {
        const iosBanner = document.getElementById('pwa-ios-banner');
        const iosCloseBtn = document.getElementById('pwa-ios-close-btn');
        if (iosBanner) {
          iosBanner.style.display = 'block';
          if (iosCloseBtn) {
            iosCloseBtn.onclick = () => {
              iosBanner.style.display = 'none';
              sessionStorage.setItem('pwa_prompt_dismissed', 'true');
            };
          }
        }
      }, 3000);
    }
  }
})();
