const fs = require('fs');
let html = fs.readFileSync('index.html', 'utf8');

// 1. Connecting Lines HTML
html = html.replace(
    '<div class="pulse-in-1 data-pulse"></div>',
    '<div class="circuit-path path-in-1"></div>\n                            <div class="circuit-path path-in-2"></div>\n                            <div class="circuit-path path-out"></div>\n                            <div class="pulse-in-1 data-pulse"></div>'
);

// 2. Fix pulse-out position
html = html.replace(
    /\.pulse-out \{\s*top: 106px;\s*right: 140px;\s*\}/,
    '.pulse-out { top: 106px; left: 280px; }'
);

// 3. New CSS
const extraCss = `
        /* Feature 4 Enhancements */
        .circuit-path {
            position: absolute;
            border-top: 2px dashed rgba(255, 255, 255, 0.1);
            z-index: 1;
        }
        .path-in-1 { top: 84px; left: 140px; width: 60px; border-top-color: rgba(147, 51, 234, 0.3); }
        .path-in-2 { top: 134px; left: 140px; width: 60px; border-top-color: rgba(147, 51, 234, 0.3); }
        .path-out { top: 110px; left: 280px; width: 60px; border-top-color: rgba(52, 211, 153, 0.3); }

        @keyframes dbReception {
            0%, 80% { box-shadow: 0 0 0 rgba(52, 211, 153, 0); border-color: rgba(52, 211, 153, 0.4); background: rgba(52, 211, 153, 0.05); }
            90% { box-shadow: 0 0 40px rgba(52, 211, 153, 0.6); border-color: rgba(52, 211, 153, 1); background: rgba(52, 211, 153, 0.2); }
            100% { box-shadow: 0 0 0 rgba(52, 211, 153, 0); border-color: rgba(52, 211, 153, 0.4); background: rgba(52, 211, 153, 0.05); }
        }
        .stage-view.active .db-target {
            animation: dbReception 1.5s infinite 0.4s;
        }

        @keyframes engineSpin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
        }
        .stage-view.active .engine-core svg {
            animation: engineSpin 12s linear infinite;
        }
`;
html = html.replace('</style>', extraCss + '\n    </style>');

fs.writeFileSync('index.html', html);
console.log('Opt2 applied!');
