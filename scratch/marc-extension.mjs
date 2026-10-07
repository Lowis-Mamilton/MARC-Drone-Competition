export class MARCConnection {
    constructor(onStatus = () => {}) {
        this.onStatus = onStatus;
        this.state = {};
        this.pending = new Map();
        this.sequence = 0;
        this.session = Math.random().toString(36).slice(2);
        this.connected = false;
        this.startPromise = Promise.resolve();
    }
    async connect() {
        clearInterval(this.heartbeat);
        this.connected=false;
        this.abort("正在重新連線");
        this.socket?.close();
        const config = await fetch('config.json').then(r => r.json());
        await new Promise((resolve, reject) => {
            const socket = this.socket = new WebSocket(`ws://127.0.0.1:${config.ws_port}`);
            this.socket.onopen = async () => {
                for(let attempt=0;attempt<10;attempt++){
                    try {await this.request('hello',{token:config.token});resolve();return;}
                    catch(error){
                        if(!error.message.includes('已有其他') || attempt===9){reject(error);return;}
                        await new Promise(done=>setTimeout(done,350));
                    }
                }
            };
            this.socket.onmessage = event => {
                if(this.socket !== socket) return;
                const message = JSON.parse(event.data);
                if (message.type === 'status') {this.state = message.state; this.onStatus(this.state);}
                const pending = this.pending.get(message.id);
                if (message.type === 'result' && pending) {
                    clearTimeout(pending.timer);
                    this.pending.delete(message.id);
                    if (message.ok) pending.resolve(message); else pending.reject(new Error(message.message));
                }
            };
            this.socket.onerror = () => reject(new Error('無法連接模擬器'));
            this.socket.onclose = () => {if(this.socket !== socket) return; this.connected = false; this.abort('模擬器連線中斷'); this.onStatus({error:'模擬器連線中斷'});};
        });
        this.connected = true;
        clearInterval(this.heartbeat);
        this.heartbeat = setInterval(() => {
            if (this.socket.readyState === 1) this.socket.send(JSON.stringify({type:'ping'}));
        }, 500);
    }
    request(type, fields = {}) {
        if (this.socket?.readyState !== 1) return Promise.reject(new Error('請先連接模擬器'));
        const id = `${this.session}-${++this.sequence}`;
        return new Promise((resolve, reject) => {
            const timer = setTimeout(() => {this.pending.delete(id); reject(new Error('模擬器指令回覆逾時'));}, type === 'command' ? 190000 : 5000);
            this.pending.set(id, {resolve, reject, timer});
            this.socket.send(JSON.stringify({type, id, ...fields}));
        });
    }
    abort(reason) {
        for (const pending of this.pending.values()) {clearTimeout(pending.timer); pending.reject(new Error(reason));}
        this.pending.clear();
    }
    start() {this.startPromise = this.request('start'); return this.startPromise;}
    async command(op, args = {}) {
        await this.startPromise;
        return this.request('command', {op, args, timeout: op === 'wait' ? Number(args.seconds) + 5 : 30});
    }
    async reset() {
        await this.stop();
        const result = await this.request('reset');
        this.startPromise = Promise.resolve();
        return result;
    }
    async stop() {
        this.abort('程式已停止');
        if (this.socket?.readyState === 1) await this.request('stop');
    }
}

export class MARCExtension {
    constructor(connection, onError = () => {}) {this.connection = connection; this.onError = onError;}
    getInfo() {
        const number = (defaultValue = 0) => ({type:'number', defaultValue});
        return {
            id:'marc', name:'MARC 無人機', color1:'#167a91', color2:'#0f6075', color3:'#0d4d61',
            blocks:[
                {opcode:'takeoff', blockType:'command', text:'起飛至 [H] 公分', arguments:{H:number(50)}},
                {opcode:'goto', blockType:'command', text:'飛至 x [X] y [Y] 高度 [H] 公分', arguments:{X:number(40),Y:number(160),H:number(50)}},
                {opcode:'move', blockType:'command', text:'沿場地移動 x [X] y [Y] 高度 [H] 公分', arguments:{X:number(40),Y:number(),H:number()}},
                {opcode:'turn', blockType:'command', text:'逆時針轉向 [D] 度', arguments:{D:number(90)}},
                {opcode:'land', blockType:'command', text:'降落'},
                {opcode:'wait', blockType:'command', text:'懸停 [S] 秒', arguments:{S:number(2)}},
                {opcode:'led', blockType:'command', text:'設定 LED [COLOR]', arguments:{COLOR:{type:'string',menu:'colors',defaultValue:'white'}}},
                {opcode:'match', blockType:'command', text:'LED 同步底部感測顏色'},
                {opcode:'color', blockType:'reporter', text:'底部感測顏色'},
                {opcode:'coordinate', blockType:'reporter', text:'無人機 [AXIS]', arguments:{AXIS:{type:'string',menu:'axes',defaultValue:'h'}}},
                {opcode:'connected', blockType:'Boolean', text:'模擬器已連線？'},
                {opcode:'finish', blockType:'command', text:'結束比賽'},
                {opcode:'stop', blockType:'command', text:'停止飛行程式'}
            ],
            menus:{
                colors:{acceptReporters:true,items:[{text:'紅',value:'red'},{text:'黃',value:'yellow'},{text:'綠',value:'green'},{text:'藍',value:'blue'},{text:'白',value:'white'},{text:'關閉',value:'off'}]},
                axes:{acceptReporters:true,items:[{text:'x 座標（公分）',value:'x'},{text:'y 座標（公分）',value:'y'},{text:'底部高度（公分）',value:'h'},{text:'航向（度）',value:'heading'},{text:'速度（公分／秒）',value:'speed'}]}
            }
        };
    }
    async run(op, args) {try {await this.connection.command(op,args);} catch(error) {if(!error.message.includes('程式已停止')) this.onError(error); throw error;}}
    takeoff(a) {return this.run('takeoff',{h:Number(a.H)});}
    goto(a) {return this.run('goto',{x:Number(a.X),y:Number(a.Y),h:Number(a.H)});}
    move(a) {return this.run('move',{x:Number(a.X),y:Number(a.Y),h:Number(a.H)});}
    turn(a) {return this.run('turn',{degrees:Number(a.D)});}
    land() {return this.run('land');}
    wait(a) {return this.run('wait',{seconds:Number(a.S)});}
    led(a) {return this.run('led',{color:String(a.COLOR)});}
    match() {return this.run('match');}
    color() {return this.connection.state.color || 'none';}
    coordinate(a) {return this.connection.state[a.AXIS] || 0;}
    connected() {return this.connection.connected;}
    finish() {return this.run('finish');}
    stop() {return this.connection.stop().catch(this.onError);}
}
