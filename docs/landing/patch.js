const fs = require('fs');
let html = fs.readFileSync('index.html', 'utf8');

// 1. Add CTA CSS
const ctaCss = `
        /* CTA Glow Animation */
        @keyframes ctaPulseGlow {
            0% { box-shadow: 0 0 0 0 rgba(21, 180, 159, 0.6); }
            70% { box-shadow: 0 0 0 12px rgba(21, 180, 159, 0); }
            100% { box-shadow: 0 0 0 0 rgba(21, 180, 159, 0); }
        }

        #start-btn {
            animation: ctaPulseGlow 2.5s infinite;
        }
`;
html = html.replace(/\.btn-primary:active\s*\{\s*transform:\s*scale\(0\.95\);\s*\}/, match => match + '\n' + ctaCss);

// 2. Add Auto-play JS
const autoPlayJs = `
        // Auto-play Logic
        let autoPlayTimer;
        let currentAutoPlayIndex = 0;
        const autoPlayStages = ['stage-default', 'stage-feat-1', 'stage-feat-2', 'stage-feat-3'];
        let hasUserInteracted = false;

        function startAutoPlay() {
            autoPlayTimer = setInterval(() => {
                if(hasUserInteracted) return;
                currentAutoPlayIndex = (currentAutoPlayIndex + 1) % autoPlayStages.length;
                const nextStage = autoPlayStages[currentAutoPlayIndex];
                
                triggers.forEach(t => t.classList.remove('is-hovered'));
                if (nextStage !== 'stage-default') {
                    const activeTrigger = document.querySelector(\`.trigger-stage[data-target="\${nextStage}"]\`);
                    if(activeTrigger) activeTrigger.classList.add('is-hovered');
                }
                switchStage(nextStage);
            }, 4000);
        }
        
        startAutoPlay();
`;

// Inject variables at the start of stage controller
html = html.replace(/const triggers = document\.querySelectorAll\('\.trigger-stage'\);/, match => autoPlayJs + '\n        ' + match);

// Set hasUserInteracted to true on mouseenter
html = html.replace(/trigger\.addEventListener\('mouseenter', \(\) => \{/g, match => match + '\n                hasUserInteracted = true;\n                clearInterval(autoPlayTimer);');

fs.writeFileSync('index.html', html);
console.log('Patched auto-play and CTA glow');
