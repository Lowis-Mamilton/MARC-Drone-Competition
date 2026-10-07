import assert from 'node:assert/strict';
const base=process.env.MARC_URL||'http://127.0.0.1:41830';
const config=await fetch(`${base}/scratch/config.json`).then(r=>r.json());
let sequence=0;
function connect(){
    const ws=new WebSocket(`ws://127.0.0.1:${config.ws_port}`),pending=new Map();
    let state={};
    ws.onmessage=event=>{
        const message=JSON.parse(event.data);
        if(message.type==='status') state=message.state;
        const waiter=pending.get(message.id);
        if(waiter){clearTimeout(waiter.timer);pending.delete(message.id);waiter.resolve(message);}
    };
    return {ws,get state(){return state;},opened:new Promise((resolve,reject)=>{ws.onopen=resolve;ws.onerror=reject;}),send(type,fields={}){
        const id=`integration-${++sequence}`;
        return new Promise((resolve,reject)=>{
            const timer=setTimeout(()=>reject(new Error('reply timeout')),35000);
            pending.set(id,{resolve,reject,timer});
            ws.send(JSON.stringify({type,id,...fields}));
        });
    },close(){for(const p of pending.values())clearTimeout(p.timer);ws.close();}};
}
const a=connect();await a.opened;
const ping=setInterval(()=>{if(a.ws.readyState===1)a.ws.send(JSON.stringify({type:'ping'}));},500);
let b;
try{
    assert.equal((await a.send('hello',{token:'wrong'})).ok,false);
    assert.equal((await a.send('hello',{token:config.token})).ok,true);
    b=connect();await b.opened;
    assert.equal((await b.send('hello',{token:config.token})).ok,false);
    assert.equal((await a.send('command',{op:'takeoff',args:{h:50}})).ok,false);
    assert.equal((await a.send('start')).ok,true);
    assert.equal((await a.send('command',{op:'goto',args:{x:999,y:160,h:50}})).ok,false);
    const lift=await a.send('command',{op:'takeoff',args:{h:50}});
    assert.equal(lift.ok,true,lift.message);
    assert.ok(a.state.h>40,'actual lift');
    const active=a.send('command',{op:'wait',args:{seconds:60},timeout:65});
    const queued=a.send('command',{op:'goto',args:{x:100,y:160,h:50}});
    assert.equal((await a.send('stop')).ok,true);
    assert.equal((await active).ok,false,'active command cancelled');
    assert.equal((await queued).ok,false,'queued command cancelled');
    assert.equal((await a.send('start')).ok,true);
    assert.equal((await a.send('command',{op:'land',args:{}})).ok,true);
    console.log('MARC_PROTOCOL_TESTS passed: authentication, ownership, gates, validation, lift, cancellation, landing');
}finally{
    clearInterval(ping);a.close();b?.close();
}
