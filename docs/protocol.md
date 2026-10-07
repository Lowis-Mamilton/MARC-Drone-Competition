# MARC 本機控制協定 1

瀏覽器先從 `/scratch/config.json` 取得 `ws_port` 與當次啟動的 `token`，再連接 `ws://127.0.0.1:ws_port`。此設定端點及 Scratch 控制權僅接受本機連線；手機四軸控制使用另一組原有通道。

每個請求帶唯一字串 `id`。回覆為 `{"type":"result","id":"...","ok":true,"message":"..."}`；錯誤 `ok:false`，飛行指令失敗會取消其餘佇列並懸停。

```json
{"type":"hello","id":"1","token":"啟動時配對碼"}
{"type":"start","id":"2"}
{"type":"command","id":"3","op":"takeoff","args":{"h":50},"timeout":30}
{"type":"command","id":"4","op":"goto","args":{"x":100,"y":200,"h":90},"timeout":30}
{"type":"stop","id":"5"}
{"type":"ping"}
```

同時只有一個編輯器能取得控制權。每 0.5 秒送出 `ping`，三秒未收到心跳即取消指令並降落。`start` 必須位於自由練習或正式自主控制時段；重新 `start` 會取消舊程式。`stop` 可在任何階段取消待執行及執行中的指令。

`command` 支援 `takeoff(h)`、`goto(x,y,h)`、`move(x,y,h)`、`turn(degrees)`、`land()`、`wait(seconds)`、`led(color)`、`match()`、`finish()`。同一程式指令依接收順序處理，最多排隊 128 筆。飛行回覆在實際動作完成後送出；燈號動作立即回覆。

距離均為公分，h 為機身底部距地面；x/y 為場地軸，turn 正值為俯視逆時針。LED 為 `red/yellow/green/blue/white/off`。目標範圍保留 10 公分機身半徑，x 10–390、y 10–310、h 0–220；起飛 h 最低 10。相對移動在真正執行時再檢查目的地。

伺服器每 0.1 秒推送 `{"type":"status","state":{...}}`。state 包含 `x,y,h,heading,speed,armed,led,color,card,state,stage,remaining,score,running`；速度為公分／秒，時間為秒，沒有色卡時 `color:"none"`。state 的 `score` 是即時累計，重大違規後最終成績以保存的比賽紀錄為準。
