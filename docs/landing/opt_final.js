const fs = require('fs');
let html = fs.readFileSync('index.html', 'utf8');

// 1. Button Micro-interactions & Shimmer
html = html.replace(
    /\.btn-primary \{\s*/,
    '.btn-primary { position: relative; overflow: hidden; '
);
const btnCss = `
        /* Button Micro-interactions */
        .btn-primary svg { transition: transform 0.3s cubic-bezier(0.16, 1, 0.3, 1); }
        .btn-primary:hover svg { transform: translateX(3px); }
        
        .link-text svg { transition: transform 0.3s cubic-bezier(0.16, 1, 0.3, 1); }
        .link-text:hover svg { transform: translateX(3px); }

        .btn-primary::after {
            content: ''; position: absolute; top: 0; left: -100%;
            width: 50%; height: 100%;
            background: linear-gradient(90deg, transparent, rgba(255,255,255,0.4), transparent);
            animation: buttonShimmer 3s infinite;
        }
        @keyframes buttonShimmer { 0%, 50%, 100% { left: -100%; } 20% { left: 200%; } }
`;
html = html.replace('</style>', btnCss + '\n    </style>');


// 2. Scan Laser Effect
html = html.replace(
    '<div class="scan-logo">',
    '<div class="scan-logo">\n                    <div class="scan-laser"></div>'
);
const laserCss = `
        .scan-laser {
            position: absolute; width: 140px; height: 2px;
            background: var(--teal-bright);
            box-shadow: 0 0 12px var(--teal-bright), 0 0 24px var(--teal-main);
            top: 0; left: 50%; transform: translateX(-50%);
            animation: scanLaser 2s ease-in-out infinite alternate;
            z-index: 100;
        }
        @keyframes scanLaser {
            0% { top: 10%; opacity: 0; }
            15% { opacity: 1; }
            85% { opacity: 1; }
            100% { top: 90%; opacity: 0; }
        }
`;
html = html.replace('</style>', laserCss + '\n    </style>');


// 3. Folder Breathing
const folderCss = `
        @keyframes folderBreathe { 0%, 100% { transform: translateY(0); } 50% { transform: translateY(-8px); } }
        .stage-view.active .h-folder { animation: folderBreathe 4s infinite ease-in-out; }
`;
html = html.replace('</style>', folderCss + '\n    </style>');


// 4. Grand Finale Checkmark
html = html.replace(
    '<div class="app-ready-msg">AreaMatrix 引擎已就绪</div>',
    `<div class="app-ready-msg">
        <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="color: var(--teal-main); margin-bottom: 16px;">
            <path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"></path>
            <polyline points="22 4 12 14.01 9 11.01"></polyline>
        </svg>
        <div>AreaMatrix 引擎已就绪</div>
    </div>`
);
const msgCss = `
        .app-ready-msg {
            display: flex; flex-direction: column; align-items: center;
        }
        .app-ready-msg svg path, .app-ready-msg svg polyline {
            stroke-dasharray: 100; stroke-dashoffset: 100;
        }
        body.is-entering .app-ready-msg svg path, 
        body.is-entering .app-ready-msg svg polyline {
            animation: drawCheck 1s ease forwards 1s;
        }
        @keyframes drawCheck { to { stroke-dashoffset: 0; } }
`;
html = html.replace('</style>', msgCss + '\n    </style>');

fs.writeFileSync('index.html', html);
console.log('Final polish applied!');
