const fs = require('fs');
let content = fs.readFileSync('index.html', 'utf8');

// 1. Remove duplicate mouseleave
const target = `            trigger.addEventListener('mouseleave', () => {
                // Return buffer to 100ms. The magic is in the CSS easing curve, 
                // not aggressively cutting the delay.
                resetTimeout = setTimeout(() => {
                    trigger.classList.remove('is-hovered');
                    switchStage('stage-default');
                }, 100);
            });
        });`;
content = content.replace(target, '');

// 2. Update Drag and Drop to capture real file
const dropLogic = `document.body.addEventListener('drop', (e) => {
            e.preventDefault(); 
            dragCounter = 0; 
            document.body.classList.remove('is-dragging'); 
            
            let droppedFilename = null;
            if (e.dataTransfer && e.dataTransfer.files.length > 0) {
                droppedFilename = e.dataTransfer.files[0].name;
            } else if (e.dataTransfer && e.dataTransfer.items.length > 0) {
                for(let i=0; i<e.dataTransfer.items.length; i++){
                    if(e.dataTransfer.items[i].kind === 'file') {
                        droppedFilename = e.dataTransfer.items[i].getAsFile().name;
                        break;
                    }
                }
            }
            startScanningSequence(droppedFilename); 
        });`;

content = content.replace(`document.body.addEventListener('drop', (e) => { e.preventDefault(); dragCounter = 0; document.body.classList.remove('is-dragging'); startScanningSequence(); });`, dropLogic);

const scanLogic = `function startScanningSequence(filename = null) {
            if (document.body.classList.contains('is-scanning')) return;
            document.body.classList.add('is-scanning');
            const terminal = document.querySelector('.scan-terminal');
            
            const logs = [
                "初始化 AreaMatrix 核心引擎...", 
                filename ? \`识别对象: [\${filename}] ...\` : "计算 SHA-256 并剔除重复项...", 
                "生成专属 AREAMATRIX.md 概览...", 
                "接管完毕，安全网罩已启动。"
            ];
            
            let i = 0; terminal.textContent = logs[0];
            const scanInterval = setInterval(() => {
                i++;
                if (i < logs.length) terminal.textContent = logs[i];
                else { clearInterval(scanInterval); terminal.textContent = ">>> 进入控制台 <<<"; terminal.style.color = "#F1B84E"; setTimeout(() => { document.body.classList.remove('is-scanning'); terminal.style.color = "var(--teal-bright)"; }, 2000); }
            }, 750);
        }`;

content = content.replace(/function startScanningSequence\(\) \{[\s\S]*?\}\s*<\/script>/, scanLogic + '\n    </script>');

// 3. Simulated Code Typing (Stage 3 & 4)
// Let's add JS for typing simulation
const typingScript = `

        // --- Simulated Typing for Dioramas ---
        const markdownLines = [
            "# AreaMatrix Index",
            "## Documents",
            "- Invoice_2026.pdf",
            "- Project_Plan.docx",
            "## Images",
            "- IMG_4921.heic"
        ];
        
        let mdIndex = 0;
        let charIndex = 0;
        const codeBody = document.querySelector('.code-body');
        
        function typeMarkdown() {
            if(!codeBody) return;
            if(charIndex === 0) {
                if(codeBody.children.length > 5) {
                    codeBody.innerHTML = ''; // reset
                }
                const div = document.createElement('div');
                div.className = 'md-item fn-new';
                div.innerHTML = \`<span class="md-bullet">*</span> <span class="text"></span>\`;
                codeBody.appendChild(div);
            }
            
            const line = markdownLines[mdIndex];
            const activeLine = codeBody.lastElementChild.querySelector('.text');
            if(activeLine && charIndex < line.length) {
                activeLine.textContent += line.charAt(charIndex);
                charIndex++;
                setTimeout(typeMarkdown, Math.random() * 50 + 30);
            } else {
                charIndex = 0;
                mdIndex = (mdIndex + 1) % markdownLines.length;
                setTimeout(typeMarkdown, 1000);
            }
        }
        
        const fsEvents = [
            "FSEventStreamCreate",
            "kFSEventStreamEventFlagItemCreated",
            "kFSEventStreamEventFlagItemRenamed",
            "kFSEventStreamEventFlagItemModified",
            "kFSEventStreamEventFlagItemRemoved"
        ];
        const fsSource = document.querySelector('.fs-event-source');
        
        function streamFSEvents() {
            if(!fsSource) return;
            const eventStr = fsEvents[Math.floor(Math.random() * fsEvents.length)];
            const div = document.createElement('div');
            div.className = 'fs-event';
            div.textContent = \`[\${new Date().toISOString().split('T')[1].slice(0,8)}] \${eventStr}\`;
            fsSource.appendChild(div);
            if(fsSource.children.length > 3) {
                fsSource.removeChild(fsSource.firstElementChild);
            }
            setTimeout(streamFSEvents, Math.random() * 1500 + 500);
        }

        // Start simulations
        setTimeout(typeMarkdown, 1000);
        setTimeout(streamFSEvents, 500);
`;

content = content.replace('// Drag / Drop / Scan logic', typingScript + '\n        // Drag / Drop / Scan logic');

fs.writeFileSync('index.html', content);
