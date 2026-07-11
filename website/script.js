// ── Hamburger ─────────────────────────────────
const ham = document.getElementById('ham');
const mobMenu = document.getElementById('mob-menu');

ham.addEventListener('click', () => {
    mobMenu.classList.toggle('open');
});

mobMenu.querySelectorAll('a').forEach(a => {
    a.addEventListener('click', () => mobMenu.classList.remove('open'));
});

// ── Scroll reveal (non-hero sections only) ───
const targets = document.querySelectorAll('.features, .how, .cta-section, footer, .feat-card, .step-card');

const io = new IntersectionObserver((entries) => {
    entries.forEach(e => {
        if (e.isIntersecting) {
            e.target.style.opacity = '1';
            e.target.style.transform = 'translateY(0)';
            io.unobserve(e.target);
        }
    });
}, { threshold: 0.08 });

targets.forEach(el => {
    el.style.opacity = '0';
    el.style.transform = 'translateY(20px)';
    el.style.transition = 'opacity 0.6s ease, transform 0.6s ease';
    io.observe(el);
});

// ── Smooth nav on scroll ─────────────────────
const navbar = document.getElementById('navbar');
window.addEventListener('scroll', () => {
    if (window.scrollY > 20) {
        navbar.style.background = 'rgba(12,12,14,0.95)';
    } else {
        navbar.style.background = 'rgba(20,20,22,0.8)';
    }
}, { passive: true });

// ── Smooth anchor scroll ─────────────────────
document.querySelectorAll('a[href^="#"]').forEach(a => {
    a.addEventListener('click', e => {
        const id = a.getAttribute('href');
        if (id === '#') return;
        const el = document.querySelector(id);
        if (el) {
            e.preventDefault();
            el.scrollIntoView({ behavior: 'smooth', block: 'start' });
        }
    });
});
