const {JSDOM,VirtualConsole}=require(process.env.JSDOM_PATH||'../../qa/node_modules/jsdom');
const fs=require('fs'),path=require('path'),assert=require('node:assert/strict');
const errors=[],vc=new VirtualConsole();vc.on('jsdomError',e=>errors.push(e.message));
const w=new JSDOM(fs.readFileSync(path.join(__dirname,'../assets/reward-frame.html'),'utf8'),{runScripts:'dangerously',url:'https://pkuai.github.io/enemizadesorbit/assets/reward-frame.html',virtualConsole:vc}).window;
const receipt={mode:'session',title:'ATIVIDADE CONCLUÍDA',light:true,reduced:true,summary:'2 acertos',values:[12.5,30,2,null],calcs:[['<img src=x onerror=alert(1)>','12,5 PR']],note:'Recibo real'};
w.dispatchEvent(new w.MessageEvent('message',{source:w,origin:w.location.origin,data:{type:'orbit-receipt',receipt}}));
assert.equal(w.document.querySelector('#vPR').textContent,'+12,5');assert.equal(w.document.querySelector('#vORB').textContent,'—');assert(w.document.body.classList.contains('light'));assert(w.document.body.classList.contains('reduced'));assert(!w.document.querySelector('#calc img'));assert(w.document.querySelector('#calc').textContent.includes('<img'));
w.document.querySelector('#prExpand').click();assert.equal(w.document.querySelector('#prExpand').getAttribute('aria-expanded'),'true');assert(w.document.querySelector('#details').classList.contains('open'));
w.document.querySelector('#again').click();assert.equal(w.document.querySelector('#vPR').textContent,'+12,5');assert(!w.document.querySelector('#details').classList.contains('open'));assert.deepEqual(errors,[]);w.close();console.log('PASS: reward values, unknown Orbes, light/reduced modes, PR disclosure, replay and XSS protection');
