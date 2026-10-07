import {installDroneToolbox} from './drone-toolbox.mjs';
import {MARCConnection, MARCExtension} from './marc-extension.mjs';
const status = document.querySelector('#status');
const errorBox = document.querySelector('#error');
let vm;
let halted = false;
let stopSuppressed = false;
let runGeneration = 0;
let starterLoaded = false;
let connectionReady;
const EXAMPLES = {
    takeoff:'起飛到 50 公分 → 懸停 2 秒 → 降落。按上方「執行」試飛。',
    forward:'起飛 → 向前 60 公分 → 等待 1 秒 → 返回 → 降落。',
    led:'起飛 → 紅、綠、藍燈各亮 1 秒 → 降落。',
    color:'進階：飛至色卡上方、讀色並同步 LED，最後返回停機坪。',
    shortcut:'進階：以底部高度 90 公分穿越捷徑圈，再返航降落。'
};
const showError = error => {
    notifyHost({type:'error',message:error.message || String(error)});
    document.documentElement.classList.remove('drone-loading');
    errorBox.textContent = error.message || String(error);
    errorBox.style.display = 'block';
    if (vm && !halted) {halted = true; vm.stopAll(); halted = false;}
};
const connection = new MARCConnection(state => {
    status.textContent = state.error || `已連線 · x ${Number(state.x||0).toFixed(0)} / y ${Number(state.y||0).toFixed(0)} / 高 ${Number(state.h||0).toFixed(0)} cm · ${state.color||'none'} · 剩餘 ${Number(state.remaining||0).toFixed(1)} 秒`;
});
window.marcConnection = connection;
const connect = () => {
    connectionReady=connection.connect().then(()=>{errorBox.style.display='none';}).catch(showError);
    return connectionReady;
};
const setupVM = nextVM => {
    vm = nextVM;
    window.marcVM = vm;
    vm.runtime.on('PROJECT_CHANGED',()=>notifyHost({type:'dirty'}));
    vm.runtime.on('PROJECT_LOADED',()=>{
        notifyHost({type:'loaded'});
        if(!starterLoaded) {starterLoaded=true;queueMicrotask(()=>loadPreset('takeoff').catch(showError));}
    });
    const extension = new MARCExtension(connection,showError);
    const manager = vm.extensionManager;
    const service = manager._registerInternalExtension(extension);
    manager._loadedExtensions.set('marc',service);
    // Register before deserializing .sb3 so MARC opcodes survive project loads.
    const originalGreenFlag = vm.greenFlag.bind(vm);
    vm.greenFlag = () => {
        const generation = ++runGeneration;
        stopSuppressed = true;
        vm.stopAll();
        stopSuppressed = false;
        errorBox.style.display='none';
        connection.stop().then(()=>generation === runGeneration ? connection.start() : null).then(()=>{
            if (generation !== runGeneration) return;
            stopSuppressed = true;
            originalGreenFlag();
            stopSuppressed = false;
        }).catch(showError);
    };
    vm.runtime.on('PROJECT_STOP_ALL',()=> {
        if(!stopSuppressed && connection.connected) {runGeneration++; connection.stop().catch(()=>{});}
    });
};
const loadPreset = async name => {
    await connectionReady;
    if(!connection.connected) throw new Error('模擬器尚未連線，請按重新連線後再載入範例');
    stopSuppressed=true;
    vm.stopAll();
    stopSuppressed=false;
    await connection.stop().catch(()=>{});
    const response = await fetch(`/examples/${name}.sb3`);
    if(!response.ok) throw new Error('找不到範例專案');
    await vm.loadProject(await response.arrayBuffer());
    document.querySelector('#example').value=name;
    document.querySelector('#example-hint').textContent=EXAMPLES[name];
    document.documentElement.classList.remove('drone-loading');
    window.marcReady=true;
};
const loadExample = async name => {
    if(!name || !vm) return;
    if(!confirm('載入範例將取代目前程式，請先按上方「儲存 .sb3」保留修改。')) return;
    await loadPreset(name);
};
document.querySelector('#reconnect').onclick=connect;
document.querySelector('#run').onclick=()=>vm?.greenFlag();
document.querySelector('#emergency').onclick=()=>{vm?.stopAll();connection.stop().catch(showError);};
document.querySelector('#reset').onclick=()=>window.marcStudio.reset();
document.querySelector('#example').onchange=event=>loadExample(event.target.value).catch(showError);

const embedded = new URLSearchParams(location.search).get('embedded') === '1';
if (embedded) document.documentElement.classList.add('embedded');
const notifyHost = message => window.chrome?.webview?.postMessage(message);
const toBase64 = bytes => {
    let text = '';
    for(let offset=0;offset<bytes.length;offset+=32768) text+=String.fromCharCode(...bytes.subarray(offset,offset+32768));
    return btoa(text);
};
window.marcStudio = {
    async openControllerSettings(tab = 'controller') {
        try {await connection.request('controller_settings', {tab});}
        catch(error) {showError(error);}
    },
    async reset() {
        ++runGeneration;
        stopSuppressed = true;
        try {
            vm.stopAll();
            await connection.reset();
            errorBox.style.display = 'none';
            notifyHost({type:'reset'});
            return true;
        } catch(error) {showError(error); return false;}
        finally {stopSuppressed = false;}
    },
    async save() {
        try {
            const file = await vm.saveProjectSb3();
            notifyHost({type:'saved',base64:toBase64(new Uint8Array(await file.arrayBuffer()))});
        } catch(error) {showError(error);}
    },
    async load(base64) {
        try {
            vm.stopAll();
            await connection.stop().catch(()=>{});
            const bytes=Uint8Array.from(atob(base64),character=>character.charCodeAt(0));
            await vm.loadProject(bytes.buffer);
            document.querySelector('#example').value='';
            document.querySelector('#example-hint').textContent='自訂程式：按上方「執行」控制模擬場地中的無人機。';
            notifyHost({type:'loaded'});
        } catch(error) {showError(error);}
    }
};

const GUI = window.GUI;
if (!GUI?.default || !GUI.AppStateHOC) throw new Error('Scratch 編輯器未完整建置');
GUI.setAppElement(document.querySelector('#app'));
const DroneEditor = props => {
    const store=window['react-redux'].useStore();
    installDroneToolbox(store);
    return window.react.createElement(GUI.default,props);
};
const Wrapped = GUI.AppStateHOC(DroneEditor);
const root = window.MARCRoot.createRoot(document.querySelector('#app'));
root.render(window.react.createElement(Wrapped, {
    canSave:false, canEditTitle:true, backpackVisible:false, showComingSoon:false,
    onVmInit:setupVM, onProjectLoaded:()=>{},
    onClickLogo:()=>{},
    basePath:'editor/',
    projectId:'0',
    assetHost:location.origin,
    projectHost:location.origin,
    intl:undefined
}));
connect();
