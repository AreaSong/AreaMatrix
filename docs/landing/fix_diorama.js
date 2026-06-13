const fs = require('fs');
let html = fs.readFileSync('index.html', 'utf8');

// 1. Widen the diorama
html = html.replace(
    /\.visual-help-diorama \{\s*position: relative;\s*width: 480px;/g,
    '.visual-help-diorama { position: relative; width: 600px;'
);

// 2. Adjust fs-event-source and db-target
html = html.replace(
    /\.fs-event-source \{\s*position: absolute;\s*left: 40px;/g,
    '.fs-event-source { position: absolute; left: 20px;'
);
html = html.replace(
    /\.db-target \{\s*position: absolute;\s*right: 40px;/g,
    '.db-target { position: absolute; right: 70px;'
);

// 3. Update paths and pulses CSS
const pathsCssRegex = /\.circuit-path \{[\s\S]*?\.path-out \{.*?\}/;
const newPathsCss = `
        .circuit-path {
            position: absolute;
            border-top: 2px dashed rgba(255, 255, 255, 0.1);
            z-index: 1;
        }
        .path-in-1 { top: 84px; left: 190px; width: 65px; border-top-color: rgba(147, 51, 234, 0.3); transform: rotate(15deg); transform-origin: left center; }
        .path-in-2 { top: 134px; left: 190px; width: 65px; border-top-color: rgba(147, 51, 234, 0.3); transform: rotate(-15deg); transform-origin: left center; }
        .path-out { top: 110px; left: 345px; width: 85px; border-top-color: rgba(52, 211, 153, 0.3); }
`;
html = html.replace(pathsCssRegex, newPathsCss);

html = html.replace(
    /\.pulse-in-1 \{\s*top: 80px;\s*left: 140px;\s*\}/g,
    '.pulse-in-1 { top: 80px; left: 190px; }'
);
html = html.replace(
    /\.pulse-in-2 \{\s*top: 130px;\s*left: 140px;\s*\}/g,
    '.pulse-in-2 { top: 130px; left: 190px; }'
);
html = html.replace(
    /\.pulse-out \{\s*top: 106px;\s*left: 280px;\s*\}/g,
    '.pulse-out { top: 106px; left: 345px; }'
);

// 4. Update the keyframes for movement distance
html = html.replace(
    /@keyframes e-pulseIn \{[\s\S]*?100% \{\s*transform: translateX\(60px\);\s*opacity: 0;\s*\}\s*\}/,
    `@keyframes e-pulseIn {
            0% { transform: translate(0, 0); opacity: 0; }
            20% { opacity: 1; }
            80% { opacity: 1; }
            100% { transform: translate(65px, 0px); opacity: 0; }
        }`
);
html = html.replace(
    /@keyframes e-pulseOut \{[\s\S]*?100% \{\s*transform: translateX\(60px\);\s*opacity: 0;\s*\}\s*\}/,
    `@keyframes e-pulseOut {
            0% { transform: translateX(0); opacity: 0; }
            20% { opacity: 1; }
            80% { opacity: 1; }
            100% { transform: translateX(85px); opacity: 0; }
        }`
);

fs.writeFileSync('index.html', html);
console.log('Spacing fixed!');
