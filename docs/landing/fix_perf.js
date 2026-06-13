const fs = require('fs');
let html = fs.readFileSync('index.html', 'utf8');

// 1. Throttle the mousemove with requestAnimationFrame
html = html.replace(
    /document\.addEventListener\('mousemove', \(e\) => \{[\s\S]*?\}\);/m,
    `let mouseX = 0;
        let mouseY = 0;
        let ticking = false;

        document.addEventListener('mousemove', (e) => {
            mouseX = e.clientX / window.innerWidth;
            mouseY = e.clientY / window.innerHeight;
            
            if (!ticking) {
                window.requestAnimationFrame(() => {
                    document.documentElement.style.setProperty('--mouse-x', (mouseX - 0.5) * 2);
                    document.documentElement.style.setProperty('--mouse-y', (mouseY - 0.5) * 2);
                    ticking = false;
                });
                ticking = true;
            }
        });`
);

// 2. Hardware acceleration for box-shadow and blobs
// Adding will-change: transform, box-shadow where appropriate
html = html.replace(
    /\.mac-window \{([\s\S]*?)animation: appLaunch/m,
    '.mac-window {$1will-change: transform, box-shadow;\n            animation: appLaunch'
);
html = html.replace(
    /\.g-blob \{([\s\S]*?)transition: all/m,
    '.g-blob {$1will-change: transform;\n            transition: transform'
);

fs.writeFileSync('index.html', html);
console.log('Performance optimized!');
