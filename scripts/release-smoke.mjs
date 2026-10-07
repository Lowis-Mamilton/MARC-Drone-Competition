import {spawn} from 'node:child_process';
import {mkdir} from 'node:fs/promises';
import path from 'node:path';
const root=path.resolve(import.meta.dirname,'..');
const runtime=path.join(root,'.runtime');
await mkdir(path.join(runtime,'release-user'),{recursive:true});
const app=spawn(path.join(root,'dist/MARCDroneSimulator.exe'),['--headless','--max-fps','120','--log-file',path.join(runtime,'logs/release-smoke.log')],{
    cwd:path.join(root,'dist'),windowsHide:true,stdio:['ignore','pipe','pipe'],env:{...process.env,APPDATA:path.join(runtime,'release-user'),LOCALAPPDATA:path.join(runtime,'release-user')}
});
let output='';
const ready=new Promise((resolve,reject)=>{
    const timer=setTimeout(()=>reject(new Error('Exported app did not start: '+output)),20000);
    app.stdout.on('data',chunk=>{
        const text=chunk.toString();output+=text;process.stdout.write(text);
        const match=output.match(/MARC_SCRATCH_URL=(http:\/\/127\.0\.0\.1:\d+)\/scratch\//);
        if(match){clearTimeout(timer);resolve(match[1]);}
    });
    app.stderr.on('data',chunk=>{output+=chunk;process.stderr.write(chunk);});
    app.on('error',error=>{clearTimeout(timer);reject(error);});
    app.on('exit',code=>{clearTimeout(timer);reject(new Error(`Exported app exited (${code}): ${output}`));});
});
function run(script,base){return new Promise((resolve,reject)=>{
    const test=spawn(process.execPath,[path.join(root,'scripts',script)],{cwd:root,stdio:'inherit',windowsHide:true,env:{...process.env,MARC_URL:base}});
    test.on('exit',code=>code===0?resolve():reject(new Error(`${script} failed (${code})`)));
    test.on('error',reject);
});}
try{
    const base=await ready;
    await run('integration-test.mjs',base);
    await run('browser-test.mjs',base);
    if(/SCRIPT ERROR|Failed to load script/.test(output)) throw new Error('Exported runtime reported script errors');
    console.log('MARC_RELEASE_SMOKE passed');
}finally{
    app.kill();
}
