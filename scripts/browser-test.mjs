import {createRequire} from 'node:module';
import {mkdir,readFile,writeFile} from 'node:fs/promises';
import path from 'node:path';
const root=path.resolve(import.meta.dirname,'..');
const require=createRequire(path.join(root,'scratch/package.json'));
const {chromium}=require('playwright');
const JSZip=require('jszip');
const browser=await chromium.launch({channel:'msedge',headless:true});
const watchdog=setTimeout(()=>browser.close(),120000);
const page=await browser.newPage({viewport:{width:1440,height:960},locale:'zh-TW'});
const errors=[];
try {
page.on('pageerror',error=>{errors.push(error.message);console.log('PAGE_ERROR',error.stack);});
page.on('console',message=>{if(message.type()==='error') console.log('BROWSER_ERROR',message.text().slice(0,250));});
await page.goto(`${process.env.MARC_URL||'http://127.0.0.1:41830'}/scratch/?locale=zh-tw`,{waitUntil:'domcontentloaded',timeout:60000});
await page.waitForTimeout(8000);
await page.waitForFunction(()=>window.marcVM?.runtime.targets.length > 0,null,{timeout:20000});
page.on('dialog',dialog=>dialog.accept());
console.log('OPTIONS',await page.locator('#example').innerHTML());
console.log('TARGETS',await page.evaluate(()=>window.marcVM.runtime.targets.length));
await page.locator('#example').selectOption('takeoff');
await page.waitForFunction(()=>window.marcVM?.runtime.targets.some(target=>Object.values(target.blocks._blocks).some(block=>block.opcode==='marc_takeoff')),null,{timeout:20000});
console.log('EXAMPLE_LOADED',await page.evaluate(()=>JSON.parse(window.marcVM.toJSON()).extensions));
await page.evaluate(()=>window.marcVM.greenFlag());
await page.waitForTimeout(2500);
console.log('AFTER_GREEN',await page.evaluate(()=>({state:window.marcConnection.state,pending:[...window.marcConnection.pending.keys()],error:document.querySelector('#error').innerText,threads:window.marcVM.runtime.threads.map(t=>({stack:t.stack,status:t.status})),blocks:JSON.parse(window.marcVM.toJSON()).targets.map(t=>t.blocks)})));
await page.waitForFunction(()=>window.marcConnection.state.h>25,null,{timeout:20000});
console.log('SCRATCH_PHYSICAL_LIFT',await page.evaluate(()=>window.marcConnection.state.h));
for(let i=0;i<8;i++) {
    await page.waitForTimeout(3000);
    console.log('RUN_STATE',await page.evaluate(()=>({h:window.marcConnection.state.h,armed:window.marcConnection.state.armed,error:document.querySelector('#error').innerText,pending:[...window.marcConnection.pending.keys()],threads:window.marcVM.runtime.threads.map(t=>({stack:t.stack,status:t.status}))})));
    if(await page.evaluate(()=>window.marcConnection.state.armed===false)) break;
}
await page.waitForFunction(()=>window.marcConnection.state.armed===false,null,{timeout:10000});
const roundtrip=await page.evaluate(async()=>{
    const project=await window.marcVM.saveProjectSb3();
    await window.marcVM.loadProject(await project.arrayBuffer());
    return Object.values(window.marcVM.runtime.targets[0].blocks._blocks).filter(block=>block.opcode.startsWith('marc_')).length;
});
console.log('SB3_ROUNDTRIP',roundtrip);
if(roundtrip!==3) throw new Error('MARC blocks missing after .sb3 reload');
const nestedProject=await page.evaluate(async()=>{
    const vm=window.marcVM;
    const project=JSON.parse(vm.toJSON());
    const base=(opcode,parent,next=null,inputs={})=>({opcode,parent,next,inputs,fields:{},shadow:false,topLevel:false});
    project.targets[0].blocks={
        green:{...base('event_whenflagclicked',null,'repeat'),topLevel:true,x:60,y:60},
        repeat:base('control_repeat','green','if',{TIMES:[1,[4,'2']],SUBSTACK:[2,'white']}),
        white:base('marc_led','repeat',null,{COLOR:[1,[10,'white']]}),
        if:base('control_if','repeat',null,{CONDITION:[2,'equal'],SUBSTACK:[2,'blue']}),
        equal:base('operator_equals','if',null,{OPERAND1:[3,'color',[10,'']],OPERAND2:[1,[10,'none']]}),
        color:base('marc_color','equal'),
        blue:base('marc_led','if',null,{COLOR:[1,[10,'blue']]})
    };
    const saved=await vm.saveProjectSb3();
    return {project,bytes:Array.from(new Uint8Array(await saved.arrayBuffer()))};
});
const nestedZip=await JSZip.loadAsync(new Uint8Array(nestedProject.bytes));
nestedZip.file('project.json',JSON.stringify(nestedProject.project));
const nestedBytes=Array.from(await nestedZip.generateAsync({type:'uint8array'}));
await page.evaluate(async bytes=>{
    const vm=window.marcVM;
    await vm.loadProject(new Uint8Array(bytes).buffer);
    const original=window.marcConnection.command.bind(window.marcConnection);
    window.marcCommands=[];
    window.marcConnection.command=(op,args)=>{window.marcCommands.push({op,args});return original(op,args);};
    vm.greenFlag();
},nestedBytes);
await page.waitForFunction(()=>window.marcConnection.state.led==='blue',null,{timeout:10000});
const nested=await page.evaluate(()=>window.marcCommands);
if(nested.length!==3) throw new Error('Scratch repeat/condition did not execute exactly three commands');
console.log('SCRATCH_REPEAT_CONDITION',nested);
console.log('STATUS',await page.locator('#status').innerText());
console.log('BODY', (await page.locator('body').innerText()).slice(0,2200));
console.log('VM',await page.evaluate(()=>({exists:!!window.marcVM,targets:window.marcVM?.runtime.targets.length,extensions:window.marcVM?._loadedExtensions,marc:window.marcVM?.extensionManager.isExtensionLoaded('marc')})));
await mkdir(path.join(root,'.runtime/previews'),{recursive:true});
await page.screenshot({path:path.join(root,'.runtime/previews/scratch.png')});
if(errors.length) process.exitCode=1;
} finally {
    clearTimeout(watchdog);
    await page.screenshot({path:path.join(root,'.runtime/previews/scratch.png')}).catch(()=>{});
    await browser.close();
}
