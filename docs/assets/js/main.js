/* ============================================================
   Agentic AI Insights — main.js
   Hash-based routing, mobile nav, filters, form handling
   ============================================================ */

(function () {
  'use strict';

  /* ── Section routing ── */
  const SECTIONS = {
    home:       document.getElementById('section-home'),
    about:      document.getElementById('section-about'),
    latest:     document.getElementById('section-latest'),
    editions:   document.getElementById('section-editions'),
    blog:       document.getElementById('section-blog'),
    videos:     document.getElementById('section-videos'),
    opensource: document.getElementById('section-opensource'),
    community:  document.getElementById('section-community'),
    contribute: document.getElementById('section-contribute'),
  };

  const NAV_LINKS = document.querySelectorAll('[data-section]');

  function getHashSection() {
    const hash = window.location.hash.replace('#', '').toLowerCase();
    return SECTIONS[hash] ? hash : 'home';
  }

  function navigateTo(name, pushState) {
    const key = name.toLowerCase();
    if (!SECTIONS[key]) return;

    // Hide all, show target
    Object.values(SECTIONS).forEach(s => { if (s) s.classList.remove('active'); });
    SECTIONS[key].classList.add('active');

    // Highlight nav
    NAV_LINKS.forEach(link => {
      link.classList.toggle('active', link.dataset.section === key);
    });

    // Update hash
    if (pushState !== false) {
      history.pushState({ section: key }, '', key === 'home' ? '#' : '#' + key);
    }

    // Scroll to top of section
    window.scrollTo({ top: 0, behavior: 'smooth' });

    // Close mobile nav
    closeMobileNav();
  }

  // Attach click handlers to all nav links
  NAV_LINKS.forEach(link => {
    link.addEventListener('click', e => {
      e.preventDefault();
      navigateTo(link.dataset.section);
    });
  });

  // Handle browser back/forward
  window.addEventListener('popstate', () => {
    navigateTo(getHashSection(), false);
  });

  // Initial load
  navigateTo(getHashSection(), false);

  /* ── Mobile nav ── */
  const hamburger   = document.getElementById('hamburger');
  const mobileNav   = document.getElementById('mobile-nav');

  function closeMobileNav() {
    if (hamburger) hamburger.classList.remove('open');
    if (mobileNav) mobileNav.classList.remove('open');
  }

  if (hamburger) {
    hamburger.addEventListener('click', () => {
      hamburger.classList.toggle('open');
      mobileNav.classList.toggle('open');
    });
  }

  // Close mobile nav on outside click
  document.addEventListener('click', e => {
    if (
      mobileNav && mobileNav.classList.contains('open') &&
      !mobileNav.contains(e.target) &&
      !hamburger.contains(e.target)
    ) {
      closeMobileNav();
    }
  });

  /* ── Navbar scroll shadow ── */
  const navbar = document.getElementById('navbar');
  window.addEventListener('scroll', () => {
    if (navbar) {
      navbar.style.background = window.scrollY > 10
        ? 'rgba(18,18,26,0.97)'
        : 'rgba(18,18,26,0.88)';
    }
  }, { passive: true });

  /* ── Filter buttons ── */
  document.querySelectorAll('.filter-group').forEach(group => {
    const btns  = group.querySelectorAll('.filter-btn');
    const items = group.closest('section,div').querySelectorAll('[data-filter]');

    btns.forEach(btn => {
      btn.addEventListener('click', () => {
        btns.forEach(b => b.classList.remove('active'));
        btn.classList.add('active');

        const val = btn.dataset.filter;
        items.forEach(item => {
          const matches = val === 'all' || item.dataset.filter === val;
          item.style.display = matches ? '' : 'none';
        });
      });
    });
  });

  /* ── Contribute form ── */
  const form = document.getElementById('contribute-form');
  if (form) {
    form.addEventListener('submit', e => {
      e.preventDefault();
      showToast('🎉 Thank you! Your submission has been received. We\'ll be in touch soon.');
      form.reset();
    });
  }

  /* ── Toast notification ── */
  function showToast(msg) {
    let toast = document.getElementById('toast');
    if (!toast) {
      toast = document.createElement('div');
      toast.id = 'toast';
      toast.className = 'toast';
      document.body.appendChild(toast);
    }
    toast.textContent = msg;
    toast.classList.add('show');
    setTimeout(() => toast.classList.remove('show'), 4000);
  }

  /* ── Animated counters (Home stats) ── */
  function animateCounters() {
    document.querySelectorAll('[data-count]').forEach(el => {
      const target = parseInt(el.dataset.count, 10);
      const suffix = el.dataset.suffix || '';
      let current = 0;
      const step = Math.ceil(target / 40);
      const timer = setInterval(() => {
        current = Math.min(current + step, target);
        el.textContent = current.toLocaleString() + suffix;
        if (current >= target) clearInterval(timer);
      }, 30);
    });
  }

  // Run counters when Home section becomes visible
  const homeSection = SECTIONS['home'];
  if (homeSection) {
    const observer = new IntersectionObserver(entries => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          animateCounters();
          observer.disconnect();
        }
      });
    }, { threshold: 0.1 });
    observer.observe(homeSection);
  }

  /* ── Edition archive expand ── */
  document.querySelectorAll('[data-edition-toggle]').forEach(btn => {
    btn.addEventListener('click', () => {
      const target = document.getElementById(btn.dataset.editionToggle);
      if (target) {
        const isOpen = target.style.display !== 'none';
        target.style.display = isOpen ? 'none' : 'block';
        btn.textContent = isOpen ? 'View Schedule ↓' : 'Hide Schedule ↑';
      }
    });
  });

  /* ── Expose navigateTo globally for inline onclick ── */
  window.navigateTo = navigateTo;
})();
