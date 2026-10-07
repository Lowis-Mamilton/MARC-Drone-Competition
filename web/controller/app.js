(() => {
  'use strict';
  const PROTOCOL_VERSION = 1;
  const SEND_INTERVAL_MS = 1000 / 60;
  const params = new URLSearchParams(location.search);
  const token = params.get('token') || '';
  const state = {
    socket: null, sessionId: '', sequence: 0, flightMode: 'angle', armed: false,
    axes: { throttle: 0, yaw: 0, pitch: 0, roll: 0 },
    physical: { left_x: 0, left_y: 1, right_x: 0, right_y: 0 },
    inputConfig: { mode: 2, mapping: { throttle: 'left_y', yaw: 'left_x', pitch: 'right_y', roll: 'right_x' } },
    inputConfigSignature: '',
    buttons: { arm: false, reset: false, turtle: false }, reconnectMs: 500,
    lastPing: 0, latency: null, ready: false, terminalError: false, lastStatus: 0,
    modePendingUntil: 0, feedbackUntil: 0, canControl:true, resetAllowed:true, positionHold:false
  };
  const $ = id => document.getElementById(id);
  const connection = $('connection');
  const message = $('message');
  const landscape = matchMedia('(orientation: landscape)');
  const actionButtons = ['armButton', 'modeButton', 'resetButton', 'turtleButton'];

  class VirtualStick {
    constructor(zoneId, knobId, onValue, holdX = false, holdY = false) {
      this.zone = $(zoneId); this.knob = $(knobId); this.onValue = onValue;
      this.holdX = holdX; this.holdY = holdY; this.pointerId = null; this.x = holdX ? 1 : 0; this.y = holdY ? 1 : 0;
      this.zone.addEventListener('pointerdown', event => this.start(event));
      this.zone.addEventListener('pointermove', event => this.move(event));
      this.zone.addEventListener('pointerup', event => this.end(event));
      this.zone.addEventListener('pointercancel', event => this.end(event));
      this.zone.addEventListener('lostpointercapture', event => this.end(event));
      this.render();
    }
    start(event) { if (this.pointerId !== null || (!state.ready || !state.canControl)) return; this.pointerId = event.pointerId; this.zone.classList.add('active'); this.zone.setPointerCapture(event.pointerId); this.update(event); }
    move(event) { if (event.pointerId === this.pointerId) this.update(event); }
    end(event) { if (event.pointerId !== this.pointerId) return; this.pointerId = null; this.zone.classList.remove('active'); if (!this.holdX) this.x = 0; if (!this.holdY) this.y = 0; this.emit(); }
    update(event) {
      const base = this.knob.parentElement.getBoundingClientRect();
      const radius = base.width / 2; let x = (event.clientX - (base.left + radius)) / radius; let y = (event.clientY - (base.top + radius)) / radius;
      const magnitude = Math.hypot(x, y); if (magnitude > 1) { x /= magnitude; y /= magnitude; }
      this.x = x; this.y = y; this.emit();
    }
    emit() { this.render(); this.onValue(this.x, this.y); }
    render() { const travel = Math.max(0, (this.knob.parentElement.clientWidth - this.knob.offsetWidth) / 2); this.knob.style.transform = `translate(${this.x * travel}px,${this.y * travel}px)`; }
  }

  const leftStick = new VirtualStick('leftZone', 'leftStick', (x, y) => { state.physical.left_x = x; state.physical.left_y = y; mapSticks(); }, false, true);
  const rightStick = new VirtualStick('rightZone', 'rightStick', (x, y) => { state.physical.right_x = x; state.physical.right_y = y; mapSticks(); });

  $('armButton').addEventListener('click', () => {
    const throttle = state.inputConfig.reverse?.throttle ? 1 - state.axes.throttle : state.axes.throttle;
    if (!state.armed && throttle > .05) { feedback('請先將升降搖桿降到底，再起飛。'); return; }
    pulse('arm');
  });
  $('resetButton').addEventListener('click', () => { resetSticks(); pulse('reset'); feedback('已送出重置指令。'); });
  $('turtleButton').addEventListener('click', () => pulse('turtle'));
  $('modeButton').addEventListener('click', () => {
    state.flightMode = state.flightMode === 'angle' ? 'acro' : 'angle';
    state.modePendingUntil = performance.now() + 1000;
    updateMode();
    feedback(state.flightMode === 'angle' ? '自動平衡模式。' : '手動姿態模式。');
  });
  $('fullscreenButton').hidden = !document.fullscreenEnabled;
  $('fullscreenButton').addEventListener('click', async () => {
    try { if (document.fullscreenElement) await document.exitFullscreen(); else await document.documentElement.requestFullscreen(); }
    catch { feedback('此瀏覽器不支援全螢幕。'); }
  });
  document.addEventListener('fullscreenchange', () => { $('fullscreenButton').textContent = document.fullscreenElement ? '離開全螢幕' : '全螢幕'; });

  function updateMode() {
    $('modeReadout').textContent = state.positionHold ? '定位懸停' : state.flightMode.toUpperCase();
    $('modeButton').textContent = state.flightMode === 'angle' ? '切換手動姿態' : '切換自動平衡';
  }
  function feedback(text) { message.textContent = text; state.feedbackUntil = performance.now() + 3000; }
  function resetSticks() {
    state.physical = { left_x: 0, left_y: 0, right_x: 0, right_y: 0 };
    const down=state.inputConfig.mapping.throttle.endsWith('_y') ? 1 : -1;
    state.physical[state.inputConfig.mapping.throttle] = state.inputConfig.reverse?.throttle ? -down : down;
    for (const [stick, side] of [[leftStick, 'left'], [rightStick, 'right']]) {
      const pointerId = stick.pointerId; stick.pointerId = null;
      if (pointerId !== null && stick.zone.hasPointerCapture(pointerId)) stick.zone.releasePointerCapture(pointerId);
      stick.zone.classList.remove('active');
      stick.x = state.physical[`${side}_x`]; stick.y = state.physical[`${side}_y`]; stick.render();
    }
    state.buttons = { arm: false, reset: false, turtle: false };
    mapSticks();
  }

  function centerThrottle() {
    const axis=state.inputConfig.mapping.throttle;state.physical[axis]=0;
    const stick=axis.startsWith('left') ? leftStick : rightStick;
    if(axis.endsWith('_x')) stick.x=0; else stick.y=0;
    stick.render();mapSticks();
  }

  function pulse(button) { if (!state.ready) return; state.buttons[button] = true; setTimeout(() => { state.buttons[button] = false; }, 100); if (navigator.vibrate) navigator.vibrate(25); }
  function mapSticks() {
    const mapping = state.inputConfig.mapping || { throttle: 'left_y', yaw: 'left_x', pitch: 'right_y', roll: 'right_x' };
    for (const channel of ['throttle', 'yaw', 'pitch', 'roll']) {
      const source = mapping[channel]; const raw = state.physical[source] ?? 0;
      state.axes[channel] = channel === 'throttle' ? clamp((source.endsWith('_y') ? 1 - raw : 1 + raw) / 2, 0, 1) : (source.endsWith('_y') ? -raw : raw);
    }
    const power = Math.round((state.inputConfig.reverse?.throttle ? 1 - state.axes.throttle : state.axes.throttle) * 100);
    $('throttleMeter').value = power; $('throttleValue').textContent = `${power}%`;
  }
  function applyInputConfig(config) {
    if (!config) return;
    const signature = JSON.stringify(config);
    if (signature === state.inputConfigSignature) return;
    state.inputConfigSignature = signature;
    state.inputConfig = config;
    const mapping = config.mode === 1
      ? { throttle: 'right_y', yaw: 'left_x', pitch: 'left_y', roll: 'right_x' }
      : config.mode === 3 ? config.mapping : { throttle: 'left_y', yaw: 'left_x', pitch: 'right_y', roll: 'right_x' };
    state.inputConfig.mapping = mapping;
    leftStick.holdX = mapping.throttle === 'left_x'; leftStick.holdY = mapping.throttle === 'left_y';
    rightStick.holdX = mapping.throttle === 'right_x'; rightStick.holdY = mapping.throttle === 'right_y';
    resetSticks();
    document.querySelector('#leftZone .axis-label.top').textContent = channelFor('left_y').toUpperCase();
    document.querySelector('#leftZone .axis-label.side').textContent = channelFor('left_x').toUpperCase();
    document.querySelector('#rightZone .axis-label.top').textContent = channelFor('right_y').toUpperCase();
    document.querySelector('#rightZone .axis-label.side').textContent = channelFor('right_x').toUpperCase();
    $('leftZone').setAttribute('aria-label', `${channelFor('left_y')} and ${channelFor('left_x')} stick`);
    $('rightZone').setAttribute('aria-label', `${channelFor('right_y')} and ${channelFor('right_x')} stick`);
    $('stickMode').textContent = `${config.mode === 3 ? '自訂' : `Mode ${config.mode}`} · 升降置中為懸停`;
    mapSticks();
  }
  function channelFor(source) { const channel=Object.entries(state.inputConfig.mapping).find(([, value]) => value === source)?.[0];return ({throttle:'升降',yaw:'轉向',pitch:'前後',roll:'左右'})[channel] || source; }
  function clamp(value, low, high) { return Math.max(low, Math.min(high, value)); }
  function setConnection(ok, text) {
    connection.classList.toggle('connected', ok); connection.classList.toggle('disconnected', !ok); connection.querySelector('span').textContent = text;
    for (const id of actionButtons) $(id).disabled = !ok || !state.ready || !landscape.matches || (id === 'resetButton' ? !state.resetAllowed : !state.canControl);
    $('portraitMessage').textContent = ok ? '手機已連線，請橫放手機並將升降搖桿降到底。' : text;
  }

  async function connect() {
    if (!token) { setConnection(false, '請掃描 QR Code'); message.textContent = '請在電腦按「手機遙控」並掃描 QR Code。'; return; }
    if (state.terminalError) return;
    try {
      const config = await fetch('/config.json', { cache: 'no-store', signal: AbortSignal.timeout(5000) }).then(response => response.json());
      const socket = new WebSocket(`ws://${location.hostname}:${config.ws_port}`);
      state.socket = socket;
      socket.addEventListener('open', () => socket.send(JSON.stringify({ type: 'hello', protocol_version: PROTOCOL_VERSION, token })));
      socket.addEventListener('message', event => receive(JSON.parse(event.data)));
      socket.addEventListener('close', () => {
        state.ready = false; state.armed = false; state.sessionId = ''; resetSticks();
        $('armButton').classList.remove('armed'); $('armButton').textContent = '起飛';
        $('flightState').textContent = '已降落'; $('latency').textContent = '— ms'; $('altitude').textContent = '高度 — 公分';
        if (state.terminalError) return;
        setConnection(false, '正在重新連線…'); feedback('連線中斷，請保持模擬器開啟；正在自動重連。');
        setTimeout(connect, state.reconnectMs); state.reconnectMs = Math.min(5000, state.reconnectMs * 1.5);
      });
      socket.addEventListener('error', () => setConnection(false, '連線失敗'));
    } catch { setConnection(false, '正在重新連線…'); message.textContent = '無法連接模擬器，請確認手機與電腦使用同一個 Wi-Fi。'; setTimeout(connect, state.reconnectMs); state.reconnectMs = Math.min(5000, state.reconnectMs * 1.5); }
  }

  function receive(data) {
    if (data.type === 'hello_ack') { state.sessionId = data.session_id; state.reconnectMs = 500; state.lastStatus = performance.now(); resetSticks(); setConnection(true, '已連線'); syncVisibility(); message.textContent = 'Lower throttle, then tap 起飛.'; }
    if (data.type === 'status') {
      state.ready = true; state.lastStatus = performance.now();
      const wasArmed=state.armed, wasAllowed=state.canControl;
      state.positionHold=Boolean(data.position_hold);state.canControl=data.manual_allowed !== false;state.resetAllowed=data.reset_allowed !== false;
      state.armed = Boolean(data.armed); $('armButton').classList.toggle('armed', state.armed); $('armButton').textContent = state.armed ? '降落' : '起飛';
      if (data.flight_mode === state.flightMode || performance.now() > state.modePendingUntil) { state.flightMode = data.flight_mode || state.flightMode; state.modePendingUntil = 0; }
      updateMode(); setConnection(true, data.failsafe ? '已暫停' : '已連線');
      applyInputConfig(data.input_config);
      if(state.positionHold && state.armed && (!wasArmed || (!wasAllowed && state.canControl))) centerThrottle();
      if(state.positionHold && !state.armed && wasArmed) resetSticks();
      if(!state.canControl && wasAllowed) resetSticks();
      if(data.supported_modes?.length === 1) {$('modeButton').hidden=true;state.flightMode=data.supported_modes[0];}
      if(data.supports_turtle === false) $('turtleButton').hidden=true;
      $('altitude').textContent = `高度 ${(Number(data.altitude_m || 0)*100).toFixed(0)} 公分`;
      $('flightState').textContent = state.armed ? '飛行中' : '已降落';
      if (data.pause_reason) feedback(data.pause_reason);
      else if (data.setup_open) message.textContent='請在電腦按「完成／關閉」，再使用手機起飛。';
      else if (!state.canControl) message.textContent=data.input_source !== 'phone' ? '請在電腦選擇「自動選擇」或「手機」控制。' : '目前由積木程式控制；手機遙控已暫停。';
      else if (performance.now() > state.feedbackUntil) message.textContent = state.armed ? '升降置中為懸停；右搖桿控制前後左右。' : '將升降搖桿降到底，再按「起飛」。';
    }
    if (data.type === 'pong') { state.latency = Math.round(performance.now() - data.client_time_ms); $('latency').textContent = `${state.latency} ms`; $('latency').classList.toggle('slow', state.latency > 100); }
    if (data.type === 'error') {
      feedback(data.message);
      if (['invalid_token', 'invalid_session', 'controller_in_use', 'protocol_mismatch', 'non_private_network'].includes(data.code)) {
        state.terminalError = true; state.ready = false; setConnection(false, data.code === 'controller_in_use' ? '已有其他手機連線' : '請重新配對');
        $('portraitMessage').textContent = data.message; state.socket.close();
      }
    }
  }

  function sendInput() {
    if (!state.socket || state.socket.readyState !== WebSocket.OPEN || !state.sessionId) return;
    if (performance.now() - state.lastStatus > 1500) { state.socket.close(); return; }
    if (document.hidden || !landscape.matches) return;
    state.socket.send(JSON.stringify({ type: 'input', protocol_version: PROTOCOL_VERSION, session_id: state.sessionId, sequence: state.sequence++, client_time_ms: Math.round(performance.now()), axes: state.axes, buttons: state.buttons, flight_mode: state.flightMode }));
    if (performance.now() - state.lastPing > 1000) { state.lastPing = performance.now(); state.socket.send(JSON.stringify({ type: 'ping', client_time_ms: state.lastPing })); }
  }

  function syncVisibility() {
    resetSticks();
    if (state.socket?.readyState !== WebSocket.OPEN) return;
    state.socket.send(JSON.stringify({ type: document.hidden || !landscape.matches ? 'background' : 'foreground' }));
  }
  document.addEventListener('visibilitychange', syncVisibility);
  landscape.addEventListener('change', syncVisibility);
  window.addEventListener('resize', () => { leftStick.render(); rightStick.render(); });
  window.addEventListener('pagehide', () => { if (state.socket?.readyState === WebSocket.OPEN) state.socket.send(JSON.stringify({ type: 'background' })); });
  setInterval(sendInput, SEND_INTERVAL_MS);
  connect();
})();
