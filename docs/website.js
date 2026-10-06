(() => {
  'use strict';
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  const download = document.querySelector('#download-link');
  if (download) {
    download.addEventListener('click', event => {
      if (download.getAttribute('aria-disabled') === 'true') event.preventDefault();
    });
    fetch(download.dataset.manifest, { cache: 'no-store' }).then(response => {
      if (!response.ok) throw new Error('Release not published');
      return response.json();
    }).then(release => {
      const url = new URL(release.apk_url);
      if (url.protocol !== 'https:' || url.username || url.password ||
          !/^\d+\.\d+\.\d+$/.test(release.version) ||
          !Number.isSafeInteger(release.build_number) || release.build_number < 1 ||
          !Number.isSafeInteger(release.size_bytes) || release.size_bytes < 1) return;
      download.href = url.href;
      download.setAttribute('aria-disabled', 'false');
      const detail = download.querySelector('small');
      detail.removeAttribute('data-en');
      detail.removeAttribute('data-bn');
      detail.textContent = `v${release.version} · APK · ${(release.size_bytes / 1048576).toFixed(1)} MB`;
    }).catch(() => { /* Keep an honest unavailable state until publication. */ });
  }
  if ('IntersectionObserver' in window && !reducedMotion.matches) {
    const observer = new IntersectionObserver(entries => {
      entries.forEach(entry => {
        if (!entry.isIntersecting) return;
        entry.target.classList.add('is-visible');
        observer.unobserve(entry.target);
      });
    }, { threshold: 0.08 });
    document.querySelectorAll('.reveal').forEach(element => {
      element.classList.add('will-reveal');
      observer.observe(element);
    });
  }
  const card = document.querySelector('.demo-card');
  const button = document.querySelector('#play-demo');
  const title = document.querySelector('#demo-title');
  const description = document.querySelector('#demo-description');
  const stages = [...document.querySelectorAll('.demo-stages span')];
  const icon = document.querySelector('.demo-status-icon use');
  const englishFrames = [
    ['Watching for an open seat', 'A quiet check. A little less refreshing.', '#i-radar'],
    ['A seat just opened!', 'One clear alert. Tap to start your booking.', '#i-bell'],
    ['OTP verified', 'With your SMS consent, verification is handled.', '#i-shield'],
    ['Your seats are held', 'Complete payment on the Railway portal to confirm.', '#i-check'],
  ];
  const bengaliFrames = [
    ['আসনের খোঁজ চলছে', 'বারবার নিজে চেক করার প্রয়োজন নেই।', '#i-radar'],
    ['আসন পাওয়া গেছে!', 'স্বয়ংক্রিয় বুকিং চালু থাকলে রিজার্ভেশন শুরু হবে।', '#i-bell'],
    ['OTP যাচাই হয়েছে', 'আপনার অনুমতি নিয়ে কোড যাচাই করা হয়েছে।', '#i-shield'],
    ['আসন রিজার্ভ হয়েছে', 'টিকিট নিশ্চিত করতে রেলওয়ে পোর্টালে পেমেন্ট করুন।', '#i-check'],
  ];
  let locale = 'bn';
  let stage = 0;
  let timer = null;
  let playing = false;
  const buttonLabels = {
    en: ['Show me the journey ', 'Journey in progress ', 'Replay the journey '],
    bn: ['ডেমো দেখুন ', 'ডেমো চলছে ', 'আবার দেখুন '],
  };
  function updateButton() {
    button.firstChild.textContent = buttonLabels[locale][playing ? 1 : stage ? 2 : 0];
  }
  function render() {
    const frames = locale === 'bn' ? bengaliFrames : englishFrames;
    card.dataset.stage = String(stage);
    title.textContent = frames[stage][0];
    description.textContent = frames[stage][1];
    icon.setAttribute('href', frames[stage][2]);
    stages.forEach((item, index) => {
      item.classList.toggle('active', index === stage);
      item.classList.toggle('complete', index < stage);
    });
    updateButton();
  }
  function setLanguage(language) {
    locale = language === 'en' ? 'en' : 'bn';
    document.documentElement.lang = locale;
    document.body.dataset.locale = locale;
    document.querySelector('.nav').setAttribute('aria-label',
      locale === 'bn' ? 'প্রধান মেনু' : 'Main navigation');
    document.querySelector('.language-toggle').setAttribute('aria-label',
      locale === 'bn' ? 'ওয়েবসাইটের ভাষা' : 'Website language');
    document.querySelector('.journey-art').setAttribute('aria-label',
      locale === 'bn' ? 'ঢাকা থেকে চট্টগ্রাম যাত্রার আসন মনিটরের নমুনা' :
        'Illustration of a monitored journey from Dhaka to Chattogram');
    const imageLabels = locale === 'bn'
      ? ['Rail Pro রুট সার্চ', 'Rail Pro বুকিংয়ের অগ্রগতি', 'Rail Pro আসন নির্বাচন']
      : ['Rail Pro route search', 'Rail Pro booking progress', 'Rail Pro seat selection'];
    document.querySelectorAll('.screenshots img').forEach((image, index) => {
      image.alt = imageLabels[index];
    });
    document.title = locale === 'bn'
      ? 'Rail Pro — আসনের খোঁজ রাখুন, যাত্রার প্রস্তুতি নিন'
      : 'Rail Pro — Stop refreshing. Start your journey.';
    document.querySelectorAll('[data-en][data-bn]').forEach(element => {
      element.textContent = element.dataset[locale];
    });
    document.querySelectorAll('[data-language]').forEach(element => {
      element.setAttribute('aria-pressed', String(element.dataset.language === locale));
    });
    render();
    try { localStorage.setItem('rail-pro-language', locale); } catch (_) {}
  }
  document.querySelectorAll('[data-language]').forEach(element => {
    element.addEventListener('click', () => setLanguage(element.dataset.language));
  });
  let savedLanguage = 'bn';
  try { savedLanguage = localStorage.getItem('rail-pro-language') || 'bn'; } catch (_) {}
  setLanguage(savedLanguage);
  function advance() {
    stage++;
    render();
    if (stage === englishFrames.length - 1) {
      playing = false;
      button.disabled = false;
      updateButton();
      timer = null;
      return;
    }
    timer = window.setTimeout(advance, 1700);
  }
  button.addEventListener('click', () => {
    if (playing) return;
    window.clearTimeout(timer);
    playing = true;
    stage = 0;
    render();
    button.disabled = true;
    updateButton();
    timer = window.setTimeout(advance, 900);
  });
  document.addEventListener('visibilitychange', () => {
    document.body.classList.toggle('paused', document.hidden);
    if (document.hidden && playing) {
      window.clearTimeout(timer);
      playing = false;
      button.disabled = false;
      updateButton();
    }
  });
})();
