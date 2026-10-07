import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {readFile} from 'node:fs/promises';
import {MARCConnection,MARCExtension} from '../scratch/marc-extension.mjs';
const require=createRequire(new URL('../scratch/package.json',import.meta.url));
const JSZip=require('jszip');

test('all example .sb3 projects contain complete MARC chains and assets',async()=>{
    for(const name of ['takeoff','forward','led','color','shortcut']) {
        const zip=await JSZip.loadAsync(await readFile(new URL(`../examples/${name}.sb3`,import.meta.url)));
        const project=JSON.parse(await zip.file('project.json').async('string'));
        assert.deepEqual(project.extensions,['marc']);
        const target=project.targets[0];
        assert.ok(zip.file(target.costumes[0].md5ext));
        let id=target.blocks.green.next,previous='green',visited=new Set();
        while(id){
            assert.ok(!visited.has(id));visited.add(id);
            assert.equal(target.blocks[id].parent,previous);
            assert.ok(target.blocks[id].opcode.startsWith('marc_'));
            previous=id;id=target.blocks[id].next;
        }
        assert.equal(visited.size,Object.keys(target.blocks).length-1);
    }
});

test('extension exposes live sensor reporters and passes commands as numbers',async()=>{
    const received=[];
    const extension=new MARCExtension({connected:true,state:{color:'green',x:140},command:async(op,args)=>received.push({op,args})});
    await extension.goto({X:'140',Y:'200',H:'90'});
    assert.deepEqual(received,[{op:'goto',args:{x:140,y:200,h:90}}]);
    assert.equal(extension.color(),'green');
    assert.equal(extension.coordinate({AXIS:'x'}),140);
    assert.equal(extension.connected(),true);
    const info=extension.getInfo();
    assert.equal(new Set(info.blocks.map(b=>b.opcode)).size,info.blocks.length);
});

test('commands wait for the program-start acknowledgement',async()=>{
    let release;
    const connection=new MARCConnection();
    connection.startPromise=new Promise(resolve=>{release=resolve;});
    let sent=false;
    connection.request=async()=>{sent=true;};
    const command=connection.command('takeoff',{h:50});
    await Promise.resolve();
    assert.equal(sent,false);
    release();await command;
    assert.equal(sent,true);
});

test('cancellation rejects pending work and clears timeouts',async()=>{
    const connection=new MARCConnection();
    connection.socket={readyState:1,send:()=>{}};
    const pending=connection.request('command',{op:'wait'});
    connection.abort('cancelled');
    await assert.rejects(pending,/cancelled/);
    assert.equal(connection.pending.size,0);
});

test('all course objects are inside the competition volume',async()=>{
    const course=JSON.parse(await readFile(new URL('../config/course.json',import.meta.url),'utf8'));
    assert.equal(course.width_cm/course.cell_cm,10);
    assert.equal(course.depth_cm/course.cell_cm,8);
    for(const prop of [...course.rings,...course.cards,course.pole,course.bridge,course.report_card]) {
        assert.ok(prop.x>=0&&prop.x<=course.width_cm);
        assert.ok(prop.y>=0&&prop.y<=course.depth_cm);
        if(prop.h) assert.ok(prop.h<course.ceiling_cm);
    }
});
