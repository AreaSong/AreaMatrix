const fs = require('fs');
let content = fs.readFileSync('index.html', 'utf8');

// Replace the placeholder triggerStage(targetId) with glare and click
content = content.replace(/triggers\.forEach\(trigger => \{([\s\S]*?)\}\);/g, `triggers.forEach(trigger => {
            // Glare effect logic
            trigger.addEventListener('mousemove', (e) => {
                const rect = trigger.getBoundingClientRect();
                const x = e.clientX - rect.left;
                const y = e.clientY - rect.top;
                trigger.style.setProperty('--gx', x + 'px');
                trigger.style.setProperty('--gy', y + 'px');
            });

            trigger.addEventListener('mouseenter', () => {
                clearTimeout(resetTimeout);
                triggers.forEach(t => t.classList.remove('is-hovered'));
                trigger.classList.add('is-hovered');
                switchStage(trigger.getAttribute('data-target'));
            });

            trigger.addEventListener('mouseleave', () => {
                resetTimeout = setTimeout(() => {
                    trigger.classList.remove('is-hovered');
                    switchStage('stage-default');
                }, 100);
            });
            
            trigger.addEventListener('click', () => {
                trigger.classList.add('is-hovered');
                switchStage(trigger.getAttribute('data-target'));
                trigger.style.transform = 'scale(0.95)';
                setTimeout(() => trigger.style.transform = '', 150);
            });
        });`);

// Update .feature-card CSS for glare
content = content.replace('.feature-card {', '.feature-card { overflow: hidden;');
let glareCss = `
        .feature-card::after {
            content: '';
            position: absolute;
            top: 0; left: 0; right: 0; bottom: 0;
            background: radial-gradient(circle 100px at var(--gx, 50%) var(--gy, 50%), rgba(255,255,255,0.1) 0%, transparent 100%);
            opacity: 0;
            transition: opacity 0.3s;
            pointer-events: none;
            mix-blend-mode: overlay;
            z-index: 10;
        }
        .feature-card.is-hovered::after {
            opacity: 1;
        }
`;
content = content.replace('.feature-card::before {', glareCss + '\n        .feature-card::before {');

fs.writeFileSync('index.html', content);
