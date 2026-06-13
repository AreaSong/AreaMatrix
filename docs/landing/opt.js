const fs = require('fs');
let html = fs.readFileSync('index.html', 'utf8');

// --- 1. Grand Finale Flash ---
// Add success-flash div
html = html.replace('<div class="mac-window">', '<div class="success-flash"></div>\n    <div class="mac-window">');

// Add success-flash CSS
const finaleCss = `
        /* Grand Finale Flash */
        .success-flash {
            position: fixed;
            inset: 0;
            background: #fff;
            z-index: 9999;
            opacity: 0;
            pointer-events: none;
            transition: opacity 2s cubic-bezier(0.16, 1, 0.3, 1);
        }
        :root[data-theme="dark"] .success-flash {
            background: radial-gradient(circle at center, rgba(21, 180, 159, 1) 0%, rgba(255, 255, 255, 1) 100%);
        }
        body.is-entering .success-flash {
            opacity: 1;
        }
        .app-ready-msg {
            position: fixed;
            top: 50%; left: 50%;
            transform: translate(-50%, -50%);
            color: #000;
            font-size: 28px;
            font-weight: 600;
            z-index: 10000;
            opacity: 0;
            pointer-events: none;
            transition: opacity 1s 1s;
        }
        body.is-entering .app-ready-msg {
            opacity: 1;
        }
`;
html = html.replace('</style>', finaleCss + '\n    </style>');
html = html.replace('<div class="success-flash"></div>', '<div class="success-flash"></div>\n    <div class="app-ready-msg">AreaMatrix 引擎已就绪</div>');

// Update JS for finale
html = html.replace(
    /else \{ clearInterval\(scanInterval\); terminal\.textContent = ">>> 进入控制台 <<<"; terminal\.style\.color = "#F1B84E"; setTimeout\(\(\) => \{ document\.body\.classList\.remove\('is-scanning'\); terminal\.style\.color = "var\(--teal-bright\)"; \}, 2000\); \}/,
    `else { 
                    clearInterval(scanInterval); 
                    terminal.textContent = ">>> 授权通过，正在进入 <<<"; 
                    terminal.style.color = "#F1B84E"; 
                    setTimeout(() => { 
                        document.body.classList.add('is-entering'); 
                    }, 1000); 
                }`
);

// --- 2. Focus Dimming ---
const dimmingCss = `
        /* Focus Dimming */
        .features-grid:hover .feature-card:not(:hover) {
            opacity: 0.4 !important;
            filter: grayscale(60%);
        }
        .feature-card {
            transition: opacity 0.4s, filter 0.4s, transform 0.4s, background 0.4s !important;
        }
`;
html = html.replace('</style>', dimmingCss + '\n    </style>');

// --- 3. Diorama Enhancements ---
// 3.1 Feature 1: Multiple files
html = html.replace('<div class="h-file"></div>', '<div class="h-file f-1"></div>\n                            <div class="h-file f-2"></div>\n                            <div class="h-file f-3"></div>');
const f1Css = `
        .visual-classify .h-file.f-1 { animation-delay: 0s; left: -10px; }
        .visual-classify .h-file.f-2 { animation-delay: 1.2s; left: 20px; transform: scale(0.9); }
        .visual-classify .h-file.f-3 { animation-delay: 2.4s; left: 50px; transform: scale(0.8); }
`;
html = html.replace('</style>', f1Css + '\n    </style>');

// 3.2 Feature 2: Finder mock
html = html.replace('<div class="h-dome"></div>', '<div class="h-dome"></div>\n                            <div class="h-finder-mock"></div>');
const f2Css = `
        .h-finder-mock {
            position: absolute;
            bottom: -20px;
            width: 240px;
            height: 140px;
            border: 1px solid rgba(255,255,255,0.1);
            border-radius: 8px;
            background: rgba(0,0,0,0.3);
            box-shadow: 0 12px 32px rgba(0,0,0,0.6);
            z-index: 1;
        }
        .h-finder-mock::before {
            content: '';
            position: absolute;
            top: 0; left: 0; right: 0; height: 24px;
            border-bottom: 1px solid rgba(255,255,255,0.05);
            background: rgba(255,255,255,0.05);
            border-radius: 8px 8px 0 0;
        }
        .visual-security .h-shield { z-index: 10; }
        .visual-security .h-dome { z-index: 5; }
`;
html = html.replace('</style>', f2Css + '\n    </style>');

fs.writeFileSync('index.html', html);
console.log('Optimizations applied!');
