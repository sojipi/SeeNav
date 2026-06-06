<page>
  <view class="page">
    <view class="card">
      <view class="topbar">
        <view class="brand">
          <text class="eyebrow">SeeNav</text>
          <text class="title">看见式导航</text>
        </view>
        <view class="{{ routeClass }}">
          <text>{{ routeState }}</text>
        </view>
      </view>

      <view class="destination-row">
        <text class="field-label">目的地</text>
        <view class="destination-value">
          <text>{{ destination }}</text>
        </view>
        <view class="{{ listenClass }}">
          <text>{{ voiceLabel }}</text>
        </view>
      </view>

      <view class="vision-panel">
        <view class="vision-header">
          <text class="mini-label">眼镜视野</text>
          <text class="frame-meta">{{ modelStatus }} · {{ frameMeta }}</text>
        </view>
        <view class="vision-box">
          <image
            ink:if="{{ hasCameraFrame }}"
            class="camera-frame"
            src="{{ cameraImageSrc }}"
            mode="scaleToFill"
          ></image>
          <view class="reticle">
            <view class="reticle-line"></view>
            <view class="reticle-dot"></view>
          </view>
          <text class="place">{{ currentPlace }}</text>
          <text class="orientation">{{ orientation }}</text>
        </view>
      </view>

      <view class="landmark-row">
        <text class="mini-label">识别地标</text>
        <view class="chips">
          <view class="chip" ink:for="{{ landmarks }}" ink:key="id">
            <text>{{ item.label }}</text>
          </view>
        </view>
      </view>

      <view class="guidance">
        <text class="mini-label">下一步</text>
        <text class="action">{{ nextAction }}</text>
      </view>

      <view class="metrics">
        <view class="metric">
          <view class="metric-head">
            <text>定位置信度</text>
            <text>{{ confidence }}%</text>
          </view>
          <view class="bar">
            <view class="bar-fill confidence-fill" style="width: {{ confidence }}%;"></view>
          </view>
        </view>
        <view class="metric">
          <view class="metric-head">
            <text>路线进度</text>
            <text>{{ progress }}%</text>
          </view>
          <view class="bar">
            <view class="bar-fill progress-fill" style="width: {{ progress }}%;"></view>
          </view>
        </view>
      </view>

      <view class="trace-row">
        <view class="{{ item.className }}" ink:for="{{ steps }}" ink:key="id">
          <text class="step-index">{{ item.id }}</text>
          <text class="step-label">{{ item.label }}</text>
        </view>
      </view>

      <view class="voice-panel">
        <text class="voice-command">{{ voiceCommand }}</text>
        <text class="voice-hint">{{ voiceHint }}</text>
      </view>

      <error-state
        ink:if="{{ errorText }}"
        text="{{ errorText }}"
        class="error"
      />
    </view>
  </view>
</page>

<script setup>
import wx from "wx";

const DEFAULT_API_BASE = "https://web-production-68af3.up.railway.app";

export default {
  data: {
    destination: "待确认",
    routeState: "待定位",
    routeClass: "route-state",
    frameMeta: "等待目标车位",
    currentPlace: "未知位置",
    orientation: "先确认目标车位和停车场地图",
    landmarks: [
      { id: "0-停车场地图", label: "停车场地图" },
      { id: "1-目标车位", label: "目标车位" },
      { id: "2-分区颜色", label: "分区颜色" },
      { id: "3-当前位置", label: "当前位置" }
    ],
    nextAction: "说开始导航后，先告诉我目标车位。",
    confidence: 0,
    progress: 0,
    steps: [
      { id: "1", label: "定位", className: "step" },
      { id: "2", label: "直行", className: "step" },
      { id: "3", label: "右转", className: "step" },
      { id: "4", label: "到达", className: "step" }
    ],
    scanButtonText: "拍照定位",
    voiceLabel: "待唤醒",
    listenClass: "listen-state",
    voiceCommand: "等待语音命令",
    voiceHint: "说 leqi 后接：开始导航、带我去 L104、停止导航、重置",
    errorText: "",
    frameIndex: 0,
    isScanning: false,
    isListening: false,
    lastWakeWord: "",
    lastVoiceText: "",
    hasCameraFrame: false,
    cameraImageSrc: "",
    navigationActive: false,
    navigationPhase: "idle",
    mapImageBase64: "",
    mapMimeType: "",
    mapSize: 0,
    mapCapturedAt: 0,
    mapIMU: null,
    autoCaptureMs: 10000,
    modelStatus: "Railway 后端",
    sessionId: "",
    apiBase: DEFAULT_API_BASE,
    imuData: {
      accelerometer: { x: null, y: null, z: null, timestamp: 0, hasReading: false },
      gyroscope: { x: null, y: null, z: null, timestamp: 0, hasReading: false },
      orientation: {
        quaternion: null,
        euler: { yawDegrees: null, pitchDegrees: null, rollDegrees: null },
        timestamp: 0,
        hasReading: false
      },
      timestamp: 0,
      startedAt: 0
    },
    imuListening: false
  },

  onLoad(options = {}) {
    this.setData({
      sessionId: options.sessionId ? decodeURIComponent(options.sessionId) : this.createSessionId()
    });
    if (options.destination) {
      this.setData({
        destination: decodeURIComponent(options.destination)
      });
    }
    if (options.apiBase) {
      this.setData({
        apiBase: decodeURIComponent(options.apiBase),
        modelStatus: "后端模型"
      });
    }
    console.log("SeeNav apiBase:", this.data.apiBase || "local-demo", "session:", this.data.sessionId);
    this.checkLanguageModel();
    this.startIMUListeners();
  },

  onShow() {
    this.startIMUListeners();
  },

  onHide() {
    this.stopNavigationLoop("页面已隐藏，自动校准已停止。");
    this.stopIMUListeners();
  },

  onUnload() {
    this.stopNavigationLoop("页面已关闭，自动校准已停止。");
    this.stopIMUListeners();
  },

  onDestinationInput(event) {
    this.setData({
      destination: event.detail.value,
      errorText: ""
    });
  },

  onVoiceTap() {
    this.startAsr("tap", "");
  },

  onVoiceWakeup(event) {
    this.startAsr("wake", this.getWakeWord(event));
  },

  onVoiceWakeUp(event) {
    this.startAsr("wake", this.getWakeWord(event));
  },

  onVoiceWake(event) {
    this.startAsr("wake", this.getWakeWord(event));
  },

  onWake(event) {
    this.startAsr("wake", this.getWakeWord(event));
  },

  onWakeup(event) {
    this.startAsr("wake", this.getWakeWord(event));
  },

  onWakeUp(event) {
    this.startAsr("wake", this.getWakeWord(event));
  },

  onWakeWord(event) {
    this.startAsr("wake", this.getWakeWord(event));
  },

  onSpeechWakeup(event) {
    this.startAsr("wake", this.getWakeWord(event));
  },

  onSpeechWakeUp(event) {
    this.startAsr("wake", this.getWakeWord(event));
  },

  onASRWakeup(event) {
    this.startAsr("wake", this.getWakeWord(event));
  },

  onVoiceCommand(event) {
    const text = this.getVoiceText(event);
    if (text) {
      this.handleVoiceCommand(text);
      return;
    }
    this.startAsr("wake", this.getWakeWord(event));
  },

  startAsr(source, wakeWord) {
    if (this.data.isListening) {
      return;
    }

    this.setData({
      isListening: true,
      voiceLabel: "听取中",
      listenClass: "listen-state listen-active",
      lastWakeWord: wakeWord || this.data.lastWakeWord,
      voiceCommand: wakeWord ? "唤醒词：" + wakeWord : "正在听取",
      errorText: source === "wake" ? "已听到唤醒词，正在听目的地。" : ""
    });

    try {
      if (source === "wake" && wx.speech && wx.speech.startRecognition) {
        wx.speech.startRecognition();
      }

      const recognition = new SpeechRecognition();
      recognition.lang = "zh-CN";
      recognition.interimResults = false;
      recognition.maxAlternatives = 1;

      recognition.onresult = (event) => {
        const transcript = this.pickTranscript(event).trim();
        this.handleVoiceCommand(transcript);
      };

      recognition.onerror = () => {
        this.useVoiceFallback();
      };

      recognition.onend = () => {
        this.setData({
          voiceLabel: "待唤醒",
          listenClass: "listen-state",
          isListening: false
        });
      };

      recognition.start();
    } catch (error) {
      this.useVoiceFallback();
    }
  },

  useVoiceFallback() {
    this.setData({
      destination: "待确认",
      voiceLabel: "待唤醒",
      listenClass: "listen-state",
      isListening: false,
      errorText: "语音能力不可用，请用调试输入提供目标车位。"
    });
  },

  async onScanTap(options = {}) {
    if (this.data.isScanning) {
      return;
    }

    if (this.data.navigationPhase === "awaitingMap") {
      await this.captureParkingMap();
      return;
    }

    if (this.data.navigationPhase !== "navigating") {
      this.promptForDestination();
      return;
    }

    this.clearAutoScanTimer();
    this.setData({
      isScanning: true,
      scanButtonText: "分析中",
      voiceHint: options.source === "auto"
        ? "自动校准中：正在拍照判断位置和方向"
        : "正在拍照判断位置和方向",
      errorText: ""
    });

    const photoMeta = await this.capturePhotoMeta();
    if (photoMeta) {
      photoMeta.imu = this.captureIMUSnapshot();
    }
    const result = await this.resolveNavigation(photoMeta);

    this.applyNavigationFrame(result, photoMeta);
  },

  async captureParkingMap() {
    if (this.data.isScanning) {
      return;
    }

    this.clearAutoScanTimer();
    this.setData({
      isScanning: true,
      scanButtonText: "读取地图",
      frameMeta: "等待停车场地图",
      currentPlace: "正在读取地图当前位置",
      orientation: "请让地图完整进入眼镜视野",
      voiceHint: "请把停车场地图放到镜头前，确认后等待开始导航",
      errorText: ""
    });

    const mapMeta = await this.capturePhotoMeta();
    if (!mapMeta || !mapMeta.imageBase64) {
      this.setData({
        isScanning: false,
        scanButtonText: "拍地图",
        voiceHint: "没有收到地图画面，请重新拍停车场地图。",
        errorText: "停车场地图未捕获。"
      });
      this.speak("没有收到地图画面，请重新拍停车场地图。");
      return;
    }

    const mapIMU = this.captureIMUSnapshot();
    this.setData({
      mapImageBase64: mapMeta.imageBase64,
      mapMimeType: mapMeta.mimeType,
      mapSize: mapMeta.size,
      mapCapturedAt: mapMeta.capturedAt || Date.now(),
      mapIMU,
      cameraImageSrc: mapMeta.imageSrc,
      hasCameraFrame: true,
      navigationPhase: "navigating",
      navigationActive: true,
      isScanning: false,
      routeState: "地图已读取",
      routeClass: "route-state route-ok",
      frameMeta: "停车场地图 · " + Math.round(mapMeta.size / 1024) + "KB",
      currentPlace: "地图当前位置已作为起点",
      orientation: "后续根据分区颜色和眼镜视野校准方向",
      landmarks: this.toLandmarks(["地图当前位置", "目标 " + this.data.destination, "分区颜色", "停车区域"]),
      nextAction: "地图已收到，现在拍摄前方停车区域开始导航。",
      scanButtonText: "开始校准",
      voiceHint: "地图已读取，正在拍摄前方停车区域开始导航。"
    });
    this.speak("地图已收到，现在拍摄前方停车区域开始导航。");
    await this.onScanTap({ source: "map" });
  },

  async capturePhotoMeta() {
    try {
      const camera = wx.media.createCameraContext();
      if (!camera) {
        return null;
      }

      const photo = await camera.takePhoto({ quality: "high" });
      const capturedAt = Date.now();
      const size = photo && photo.data ? photo.data.byteLength : 0;
      const imageBase64 = photo && photo.data ? wx.arrayBufferToBase64(photo.data) : "";
      const mimeType = photo && photo.mimeType ? photo.mimeType : "image/jpeg";
      console.log("SeeNav photo captured:", {
        size,
        mimeType,
        hasImage: Boolean(imageBase64)
      });
      return {
        mimeType,
        size,
        capturedAt,
        imageBase64,
        imageSrc: imageBase64 ? "data:" + mimeType + ";base64," + imageBase64 : ""
      };
    } catch (error) {
      return null;
    }
  },

  async resolveNavigation(photoMeta) {
    if (this.data.apiBase) {
      try {
        console.log("SeeNav calling backend:", this.data.apiBase);
        return await this.requestBackend(photoMeta);
      } catch (error) {
        console.log("SeeNav backend unavailable:", error);
        this.setData({
          modelStatus: "本地演示",
          errorText: "后端请求失败，已切换为本地演示：" + this.formatError(error)
        });
      }
    }

    await new Promise((resolve) => setTimeout(resolve, 520));
    const index = this.data.frameIndex % 4;
    return this.getDemoFrame(index);
  },

  requestBackend(photoMeta) {
    const frameIMU = photoMeta && photoMeta.imu ? photoMeta.imu : this.captureIMUSnapshot();
    return new Promise((resolve, reject) => {
      const apiBase = (this.data.apiBase || "").replace(/\/+$/, "");
      const url = apiBase + "/api/visual-nav/locate";
      console.log("SeeNav wx.request:", url);
      wx.request({
        url,
        method: "POST",
        dataType: "json",
        header: {
          "Content-Type": "application/json"
        },
        data: {
          destination: this.data.destination,
          sessionId: this.data.sessionId,
          imageBase64: photoMeta && photoMeta.imageBase64 ? photoMeta.imageBase64 : "",
          mimeType: photoMeta && photoMeta.mimeType ? photoMeta.mimeType : "image/jpeg",
          size: photoMeta && photoMeta.size ? photoMeta.size : 0,
          capturedAt: photoMeta && photoMeta.capturedAt ? photoMeta.capturedAt : Date.now(),
          mapBase64: this.data.mapImageBase64,
          mapMimeType: this.data.mapMimeType || "image/jpeg",
          mapSize: this.data.mapSize,
          mapCapturedAt: this.data.mapCapturedAt,
          mapIMU: this.data.mapIMU,
          imu: frameIMU,
          imuListening: this.data.imuListening,
          routeContext: {
            phase: this.data.navigationPhase,
            startSource: "parking_map",
            visualFocus: "parking_area_color",
            orientationReference: "map_capture_imu"
          },
          scenario: "parking"
        },
        success: (response) => {
          console.log("SeeNav backend response:", response.statusCode, response.data);
          if (response.statusCode >= 200 && response.statusCode < 300) {
            const data = this.parseBackendResponse(response.data);
            console.log("SeeNav backend parsed:", data);
            this.setData({
              modelStatus: "Railway 后端"
            });
            resolve(data);
          } else {
            reject(new Error("Backend status " + response.statusCode));
          }
        },
        fail: (error) => {
          console.log("SeeNav backend request failed:", error);
          reject(error);
        }
      });
    });
  },

  parseBackendResponse(data) {
    if (!data) {
      throw new Error("Empty backend response");
    }
    if (typeof data === "string") {
      return JSON.parse(data);
    }
    if (this.isArrayBuffer(data)) {
      return JSON.parse(this.arrayBufferToText(data));
    }
    if (typeof ArrayBuffer !== "undefined" && ArrayBuffer.isView && ArrayBuffer.isView(data)) {
      return JSON.parse(this.bytesToText(new Uint8Array(data.buffer, data.byteOffset, data.byteLength)));
    }
    if (typeof data === "object") {
      return data;
    }
    throw new Error("Unsupported backend response");
  },

  isArrayBuffer(value) {
    return value &&
      typeof value === "object" &&
      typeof value.byteLength === "number" &&
      typeof value.slice === "function" &&
      typeof value.BYTES_PER_ELEMENT === "undefined";
  },

  arrayBufferToText(buffer) {
    if (typeof TextDecoder !== "undefined") {
      return new TextDecoder("utf-8").decode(buffer);
    }
    return this.bytesToText(new Uint8Array(buffer));
  },

  bytesToText(bytes) {
    let binary = "";
    for (let i = 0; i < bytes.length; i += 4096) {
      const end = Math.min(i + 4096, bytes.length);
      let chunk = "";
      for (let j = i; j < end; j += 1) {
        chunk += String.fromCharCode(bytes[j]);
      }
      binary += chunk;
    }
    try {
      return decodeURIComponent(escape(binary));
    } catch (error) {
      return binary;
    }
  },

  formatError(error) {
    if (!error) {
      return "unknown";
    }
    if (error.message) {
      return error.message;
    }
    if (error.errMsg) {
      return error.errMsg;
    }
    return String(error);
  },

  createSessionId() {
    return "seenav-" + Date.now() + "-" + Math.floor(Math.random() * 1000000);
  },

  applyNavigationFrame(frame, photoMeta) {
    const metaPrefix = photoMeta
      ? "实拍 · " + Math.round(photoMeta.size / 1024) + "KB"
      : frame.frameMeta;

    this.setData({
      routeState: frame.routeState,
      routeClass: frame.routeClass,
      frameMeta: photoMeta ? metaPrefix + " · " + photoMeta.mimeType : frame.frameMeta,
      currentPlace: frame.currentPlace,
      orientation: frame.orientation,
      landmarks: this.toLandmarks(frame.landmarks),
      nextAction: frame.nextAction,
      confidence: frame.confidence,
      progress: frame.progress,
      steps: this.toSteps(frame.activeStep),
      scanButtonText: frame.scanButtonText,
      cameraImageSrc: photoMeta && photoMeta.imageSrc ? photoMeta.imageSrc : this.data.cameraImageSrc,
      hasCameraFrame: photoMeta && photoMeta.imageSrc ? true : this.data.hasCameraFrame,
      frameIndex: this.data.frameIndex + 1,
      isScanning: false
    });

    this.speak(frame.nextAction);

    if (this.isArrived(frame)) {
      this.stopNavigationLoop("已到达目的地，自动校准已停止。");
      return;
    }

    if (this.data.navigationActive) {
      this.scheduleNextAutoScan();
    }
  },

  onDeviationTap() {
    this.applyNavigationFrame(this.getDeviationFrame(), null);
  },

  onResetTap() {
    this.stopNavigationLoop("");
    this.resetBackendSession();
    this.setData({
      sessionId: this.createSessionId(),
      destination: "待确认",
      routeState: "待定位",
      routeClass: "route-state",
      frameMeta: "等待目标车位",
      currentPlace: "未知位置",
      orientation: "先确认目标车位和停车场地图",
      landmarks: this.toLandmarks(["停车场地图", "目标车位", "分区颜色", "当前位置"]),
      nextAction: "说开始导航后，先告诉我目标车位。",
      confidence: 0,
      progress: 0,
      steps: this.toSteps(0),
      scanButtonText: "拍照定位",
      frameIndex: 0,
      isScanning: false,
      hasCameraFrame: false,
      cameraImageSrc: "",
      navigationActive: false,
      navigationPhase: "idle",
      mapImageBase64: "",
      mapMimeType: "",
      mapSize: 0,
      mapCapturedAt: 0,
      mapIMU: null,
      voiceCommand: "等待语音命令",
      voiceHint: "说 leqi 后接：带我去 L104、开始导航、停止导航、重置",
      errorText: ""
    });
  },

  resetBackendSession() {
    if (!this.data.apiBase) {
      return;
    }
    try {
      wx.request({
        url: this.data.apiBase + "/api/visual-nav/reset",
        method: "POST",
        dataType: "json",
        data: {
          sessionId: this.data.sessionId
        }
      });
    } catch (error) {
      console.log("Backend reset unavailable", error);
    }
  },

  pickTranscript(event) {
    const results = event && event.results;
    const firstResult = results && results[0];
    const firstAlternative = firstResult && firstResult[0];
    return firstAlternative && firstAlternative.transcript
      ? firstAlternative.transcript
      : "";
  },

  getWakeWord(event) {
    if (!event) {
      return "";
    }
    const detail = event.detail || {};
    return detail.wakeWord || detail.keyword || detail.text || event.wakeWord || "";
  },

  getVoiceText(event) {
    if (!event) {
      return "";
    }
    const detail = event.detail || {};
    return detail.transcript || detail.command || detail.query || detail.text || detail.value || event.transcript || event.text || "";
  },

  handleVoiceCommand(text) {
    const command = (text || "").trim();
    if (!command) {
      this.setData({
        voiceLabel: "待唤醒",
        listenClass: "listen-state",
        isListening: false
      });
      return;
    }

    const destination = this.extractDestination(command);
    const phase = this.data.navigationPhase;
    const updates = {
      voiceLabel: "待唤醒",
      listenClass: "listen-state",
      isListening: false,
      lastVoiceText: command,
      voiceCommand: "听到：" + command,
      errorText: ""
    };

    if (destination && phase !== "awaitingMap") {
      updates.destination = destination;
    }

    this.setData(updates);

    if (command.indexOf("重置") >= 0 || command.indexOf("重新开始") >= 0) {
      this.onResetTap();
      return;
    }

    if (command.indexOf("停止") >= 0 || command.indexOf("暂停") >= 0 || command.indexOf("结束导航") >= 0) {
      this.stopNavigationLoop("自动校准已停止。");
      this.setData({
        navigationPhase: "idle"
      });
      return;
    }

    if (command.indexOf("偏航") >= 0 || command.indexOf("走错") >= 0 || command.indexOf("走偏") >= 0) {
      this.onDeviationTap();
      return;
    }

    if (phase === "awaitingDestination") {
      this.acceptDestination(destination || this.normalizeDestination(command));
      return;
    }

    if (phase === "awaitingMap") {
      if (this.isMapCaptureCommand(command)) {
        this.captureParkingMap();
        return;
      }
      this.promptForMap();
      return;
    }

    if (this.isStartCommand(command)) {
      if (destination) {
        this.acceptDestination(destination);
        return;
      }
      this.promptForDestination();
      return;
    }

    if (destination) {
      this.acceptDestination(destination);
      return;
    }

    if (phase === "navigating" && this.isScanCommand(command)) {
      this.onScanTap({ source: "voice" });
      return;
    }

    this.setData({
      voiceHint: "未识别命令，请说：带我去 L104、开始导航、停止导航、重置"
    });
  },

  promptForDestination() {
    this.clearAutoScanTimer();
    this.setData({
      navigationPhase: "awaitingDestination",
      navigationActive: false,
      destination: "待确认",
      routeState: "待目标",
      routeClass: "route-state",
      frameMeta: "等待目标车位",
      currentPlace: "等待目标车位",
      orientation: "请说目标车位，例如 L104",
      nextAction: "请告诉我目标车位。",
      scanButtonText: "等待目标",
      voiceHint: "请说目标车位，例如 L104。",
      errorText: ""
    });
    this.speak("请告诉我目标车位，例如 L104。");
  },

  acceptDestination(destination) {
    const target = this.normalizeDestination(destination);
    if (!target || target === "待确认") {
      this.promptForDestination();
      return;
    }

    this.clearAutoScanTimer();
    this.resetBackendSession();
    this.setData({
      sessionId: this.createSessionId(),
      destination: target,
      navigationPhase: "awaitingMap",
      navigationActive: false,
      routeState: "待地图",
      routeClass: "route-state",
      frameMeta: "等待停车场地图",
      currentPlace: "等待地图当前位置",
      orientation: "地图需要包含当前位置和分区颜色",
      landmarks: this.toLandmarks(["目标 " + target, "停车场地图", "当前位置", "分区颜色"]),
      nextAction: "请提供停车场地图，地图里需要包含当前位置和停车区域颜色。",
      scanButtonText: "拍地图",
      voiceHint: "请把停车场地图放到镜头前，然后说地图好了或拍地图。",
      errorText: ""
    });
    this.speak("目标车位是" + target + "。请把停车场地图放到镜头前，地图需要包含当前位置和停车区域颜色。准备好后说地图好了。");
  },

  promptForMap() {
    this.setData({
      navigationPhase: "awaitingMap",
      routeState: "待地图",
      frameMeta: "等待停车场地图",
      currentPlace: "等待地图当前位置",
      orientation: "请提供包含当前位置和分区颜色的停车场地图",
      nextAction: "请把停车场地图放到镜头前，然后说地图好了或拍地图。",
      scanButtonText: "拍地图",
      voiceHint: "请说地图好了，或把地图对准镜头后说拍地图。"
    });
    this.speak("请提供停车场地图。地图需要包含当前位置和停车区域颜色。");
  },

  isStartCommand(command) {
    return command.indexOf("开始") >= 0 || command.indexOf("导航") >= 0 || command.indexOf("带路") >= 0;
  },

  isScanCommand(command) {
    return command.indexOf("拍照") >= 0 ||
      command.indexOf("定位") >= 0 ||
      command.indexOf("校准") >= 0 ||
      command.indexOf("继续") >= 0 ||
      command.indexOf("下一步") >= 0;
  },

  isMapCaptureCommand(command) {
    return command.indexOf("地图") >= 0 ||
      command.indexOf("拍") >= 0 ||
      command.indexOf("好了") >= 0 ||
      command.indexOf("完成") >= 0 ||
      command.indexOf("确认") >= 0 ||
      command.indexOf("提供") >= 0;
  },

  startNavigationLoop() {
    this.clearAutoScanTimer();
    this.setData({
      navigationPhase: "navigating",
      navigationActive: true,
      voiceHint: "已开始导航：每 10 秒自动拍照校准一次"
    });
  },

  stopNavigationLoop(message) {
    this.clearAutoScanTimer();
    this.setData({
      navigationActive: false,
      isScanning: false,
      voiceHint: message || this.data.voiceHint
    });
  },

  scheduleNextAutoScan() {
    this.clearAutoScanTimer();
    this.setData({
      voiceHint: "导航中：10 秒后自动拍照校准"
    });
    this.autoScanTimer = setTimeout(() => {
      if (!this.data.navigationActive) {
        return;
      }
      if (this.data.isScanning) {
        this.scheduleNextAutoScan();
        return;
      }
      this.onScanTap({ source: "auto" });
    }, this.data.autoCaptureMs);
  },

  clearAutoScanTimer() {
    if (this.autoScanTimer) {
      clearTimeout(this.autoScanTimer);
      this.autoScanTimer = null;
    }
  },

  isArrived(frame) {
    return frame && (frame.progress >= 100 || frame.routeState === "已到达");
  },

  extractDestination(command) {
    let text = command || "";
    if (
      text.indexOf("重置") >= 0 ||
      text.indexOf("停止") >= 0 ||
      text.indexOf("暂停") >= 0 ||
      text.indexOf("结束") >= 0 ||
      text.indexOf("偏航") >= 0 ||
      text.indexOf("走错") >= 0 ||
      text.indexOf("地图") >= 0 ||
      text.indexOf("拍照") >= 0 ||
      text.indexOf("定位") >= 0 ||
      text.indexOf("校准") >= 0 ||
      text.indexOf("继续") >= 0 ||
      text.indexOf("下一步") >= 0 ||
      text === "开始导航" ||
      text === "导航" ||
      text === "开始"
    ) {
      return "";
    }

    text = text.replace("我要去", "");
    text = text.replace("带我去", "");
    text = text.replace("导航到", "");
    text = text.replace("目标车位是", "");
    text = text.replace("目标车位", "");
    text = text.replace("车位是", "");
    text = text.replace("目的地是", "");
    text = text.replace("寻找", "");
    text = text.replace("找", "");
    text = text.replace("去", "");
    text = text.replace("，", "");
    text = text.replace("。", "");
    text = text.replace(",", "");
    text = text.replace(".", "");
    text = text.trim();

    if (text === "leqi" || text === "乐奇" || text === "乐琪") {
      return "";
    }
    if (text.length > 0 && text.length <= 32) {
      return text;
    }
    return "";
  },

  normalizeDestination(value) {
    let text = String(value || "");
    text = text.replace("目标车位是", "");
    text = text.replace("目标车位", "");
    text = text.replace("车位是", "");
    text = text.replace("目的地是", "");
    text = text.replace("我要去", "");
    text = text.replace("带我去", "");
    text = text.replace("导航到", "");
    text = text.replace("寻找", "");
    text = text.replace("找", "");
    text = text.replace("去", "");
    text = text.replace("，", "");
    text = text.replace("。", "");
    text = text.replace(",", "");
    text = text.replace(".", "");
    text = text.trim();
    if (text === "leqi" || text === "乐奇" || text === "乐琪") {
      return "";
    }
    return text.length <= 32 ? text : "";
  },

  async checkLanguageModel() {
    if (this.data.apiBase) {
      return;
    }
    try {
      if (typeof LanguageModel === "undefined") {
        return;
      }
      const availability = await LanguageModel.availability();
      if (availability === "available") {
        this.setData({
          modelStatus: "端侧语言模型可用"
        });
      }
    } catch (error) {
      console.log("LanguageModel unavailable", error);
    }
  },

  startIMUListeners() {
    if (this.data.imuListening || (this.imuSensors && this.imuSensors.length > 0)) {
      return;
    }

    const sensors = [];
    const startedAt = Date.now();
    const startSensor = (label, SensorCtor, onReading) => {
      if (typeof SensorCtor !== "function") {
        return;
      }
      try {
        const sensor = new SensorCtor({ frequency: 15 });
        sensor.addEventListener("reading", (event) => {
          onReading(sensor, event || {});
        });
        sensor.addEventListener("error", (event) => {
          console.log("SeeNav " + label + " sensor error:", event && (event.message || event.error || event));
        });
        sensor.start();
        sensors.push(sensor);
      } catch (error) {
        console.log("SeeNav " + label + " unavailable:", error);
      }
    };

    const AccelerometerCtor = typeof Accelerometer !== "undefined" ? Accelerometer : null;
    const GyroscopeCtor = typeof Gyroscope !== "undefined" ? Gyroscope : null;
    const OrientationCtor = typeof AbsoluteOrientationSensor !== "undefined" ? AbsoluteOrientationSensor : null;

    startSensor("accelerometer", AccelerometerCtor, (sensor, event) => {
      this.setData({
        "imuData.accelerometer": this.sensorVectorReading(sensor, event),
        "imuData.timestamp": Date.now()
      });
    });

    startSensor("gyroscope", GyroscopeCtor, (sensor, event) => {
      this.setData({
        "imuData.gyroscope": this.sensorVectorReading(sensor, event),
        "imuData.timestamp": Date.now()
      });
    });

    startSensor("orientation", OrientationCtor, (sensor, event) => {
      const quaternion = this.normalizeQuaternion(sensor.quaternion || event.quaternion || [event.x, event.y, event.z, event.w]);
      if (!quaternion) {
        return;
      }
      this.setData({
        "imuData.orientation": {
          quaternion,
          euler: this.quaternionToEuler(quaternion),
          timestamp: this.pickSensorTimestamp(sensor, event),
          hasReading: true
        },
        "imuData.timestamp": Date.now()
      });
    });

    this.imuSensors = sensors;
    this.setData({
      imuListening: sensors.length > 0,
      "imuData.startedAt": startedAt
    });
    console.log("SeeNav IMU listeners started:", sensors.length);
  },

  stopIMUListeners() {
    const sensors = this.imuSensors || [];
    for (let i = 0; i < sensors.length; i += 1) {
      try {
        sensors[i].stop();
      } catch (error) {
        console.log("SeeNav IMU stop failed:", error);
      }
    }
    this.imuSensors = [];
    this.setData({ imuListening: false });
    console.log("SeeNav IMU listeners stopped");
  },

  captureIMUSnapshot() {
    const imu = this.data.imuData || {};
    const orientation = imu.orientation || {};
    const euler = orientation.euler || {};
    const headingDegrees = typeof euler.yawDegrees === "number" ? euler.yawDegrees : null;
    const snapshot = {
      accelerometer: this.cloneIMUReading(imu.accelerometer),
      gyroscope: this.cloneIMUReading(imu.gyroscope),
      orientation: {
        quaternion: orientation.quaternion ? orientation.quaternion.slice(0, 4) : null,
        euler: {
          yawDegrees: headingDegrees,
          pitchDegrees: typeof euler.pitchDegrees === "number" ? euler.pitchDegrees : null,
          rollDegrees: typeof euler.rollDegrees === "number" ? euler.rollDegrees : null
        },
        timestamp: orientation.timestamp || 0,
        hasReading: Boolean(orientation.hasReading)
      },
      headingDegrees,
      timestamp: Date.now()
    };
    snapshot.hasReading = Boolean(
      (snapshot.accelerometer && snapshot.accelerometer.hasReading) ||
      (snapshot.gyroscope && snapshot.gyroscope.hasReading) ||
      snapshot.orientation.hasReading
    );

    const mapIMU = this.data.mapIMU;
    if (
      mapIMU &&
      typeof snapshot.headingDegrees === "number" &&
      typeof mapIMU.headingDegrees === "number"
    ) {
      snapshot.mapRelativeYawDegrees = this.normalizeSignedDegrees(snapshot.headingDegrees - mapIMU.headingDegrees);
    }
    return snapshot;
  },

  sensorVectorReading(sensor, event) {
    return {
      x: this.finiteNumber(event.x, sensor.x),
      y: this.finiteNumber(event.y, sensor.y),
      z: this.finiteNumber(event.z, sensor.z),
      timestamp: this.pickSensorTimestamp(sensor, event),
      hasReading: true
    };
  },

  cloneIMUReading(reading) {
    if (!reading || !reading.hasReading) {
      return { x: null, y: null, z: null, timestamp: 0, hasReading: false };
    }
    return {
      x: this.finiteNumber(reading.x, null),
      y: this.finiteNumber(reading.y, null),
      z: this.finiteNumber(reading.z, null),
      timestamp: reading.timestamp || 0,
      hasReading: true
    };
  },

  pickSensorTimestamp(sensor, event) {
    return this.finiteNumber(event.timestamp, sensor.timestamp) || Date.now();
  },

  finiteNumber(primary, fallback) {
    if (typeof primary === "number" && isFinite(primary)) {
      return primary;
    }
    if (typeof fallback === "number" && isFinite(fallback)) {
      return fallback;
    }
    return null;
  },

  normalizeQuaternion(value) {
    if (!value || value.length < 4) {
      return null;
    }
    const x = this.finiteNumber(value[0], null);
    const y = this.finiteNumber(value[1], null);
    const z = this.finiteNumber(value[2], null);
    const w = this.finiteNumber(value[3], null);
    if (x === null || y === null || z === null || w === null) {
      return null;
    }
    return [x, y, z, w];
  },

  quaternionToEuler(quaternion) {
    const x = quaternion[0];
    const y = quaternion[1];
    const z = quaternion[2];
    const w = quaternion[3];
    const roll = Math.atan2(
      2 * (w * x + y * z),
      1 - 2 * (x * x + y * y)
    );
    const pitchInput = Math.max(-1, Math.min(1, 2 * (w * y - z * x)));
    const pitch = Math.asin(pitchInput);
    const yaw = Math.atan2(
      2 * (w * z + x * y),
      1 - 2 * (y * y + z * z)
    );
    return {
      yawDegrees: this.normalizeDegrees(yaw * 180 / Math.PI),
      pitchDegrees: pitch * 180 / Math.PI,
      rollDegrees: roll * 180 / Math.PI
    };
  },

  normalizeDegrees(value) {
    let normalized = value % 360;
    if (normalized < 0) {
      normalized += 360;
    }
    return normalized;
  },

  normalizeSignedDegrees(value) {
    let normalized = this.normalizeDegrees(value);
    if (normalized > 180) {
      normalized -= 360;
    }
    return normalized;
  },

  toLandmarks(labels) {
    const landmarks = [];
    for (let i = 0; i < labels.length; i += 1) {
      landmarks.push({
        id: String(i) + "-" + labels[i],
        label: labels[i]
      });
    }
    return landmarks;
  },

  toSteps(activeStep) {
    const steps = [
      { id: "1", label: "定位" },
      { id: "2", label: "直行" },
      { id: "3", label: "右转" },
      { id: "4", label: "到达" }
    ];
    const result = [];
    for (let i = 0; i < steps.length; i += 1) {
      result.push({
        id: steps[i].id,
        label: steps[i].label,
        className: Number(steps[i].id) <= activeStep ? "step step-active" : "step"
      });
    }
    return result;
  },

  getDemoFrame(index) {
    const frames = [
      {
        routeState: "已定位",
        routeClass: "route-state route-ok",
        frameMeta: "实景帧 01 · B1 停车场",
        currentPlace: "B1 C区电梯口外侧",
        orientation: "面向 C12-C16 柱号方向",
        landmarks: ["C区标牌", "电梯厅", "柱号 C12", "出口箭头"],
        nextAction: "沿当前方向直行，看到 C16 柱后准备右转。",
        confidence: 82,
        progress: 25,
        activeStep: 2,
        scanButtonText: "继续校准"
      },
      {
        routeState: "方向正确",
        routeClass: "route-state route-ok",
        frameMeta: "实景帧 02 · C16 柱前",
        currentPlace: "C16 柱前主通道",
        orientation: "面对 C18 支路入口",
        landmarks: ["柱号 C16", "C18箭头", "白色车道线", "限速牌"],
        nextAction: "在 C16 柱后右转，进入右侧车位排。",
        confidence: 88,
        progress: 55,
        activeStep: 3,
        scanButtonText: "右转后校准"
      },
      {
        routeState: "接近目标",
        routeClass: "route-state route-warn",
        frameMeta: "实景帧 03 · C18 车位排",
        currentPlace: "C18 车位排前方",
        orientation: "目标在右前方第二个车位",
        landmarks: ["C18标线", "消防栓", "灰色SUV", "柱号 C18"],
        nextAction: "继续前进 8 到 12 米，C18 在右侧第二个车位。",
        confidence: 91,
        progress: 82,
        activeStep: 4,
        scanButtonText: "确认到达"
      },
      {
        routeState: "已到达",
        routeClass: "route-state route-done",
        frameMeta: "实景帧 04 · 目标车位",
        currentPlace: "B1 C区 C18",
        orientation: "目的地位于右侧",
        landmarks: ["车位 C18", "目标车辆", "柱号 C18", "C区标牌"],
        nextAction: "已到达目的地，停止导航。",
        confidence: 96,
        progress: 100,
        activeStep: 4,
        scanButtonText: "重新校准"
      }
    ];
    return frames[index];
  },

  getDeviationFrame() {
    return {
      routeState: "偏离路线",
      routeClass: "route-state route-off",
      frameMeta: "偏航帧 · D区入口",
      currentPlace: "B1 D区通道口",
      orientation: "背离 C18 方向",
      landmarks: ["D区标牌", "出口箭头", "柱号 D03", "收费处"],
      nextAction: "你已走到 D区，请向左回到 C区标牌，再寻找 C16 柱。",
      confidence: 74,
      progress: 42,
      activeStep: 2,
      scanButtonText: "重新定位"
    };
  },

  speak(text) {
    try {
      if (wx.speech && wx.speech.playTTS) {
        wx.speech.playTTS(text);
        return;
      }

      const utterance = new SpeechSynthesisUtterance(text);
      utterance.lang = "zh-CN";
      utterance.rate = 1;
      speechSynthesis.speak(utterance);
    } catch (error) {
      console.log("TTS unavailable", error);
    }
  }
};
</script>

<style>
.page {
  width: 480px;
  min-height: 380px;
  padding: 8px;
  box-sizing: border-box;
  background-color: #000000;
  color: var(--color-text-primary);
}

.card {
  height: 364px;
  padding: 12px;
  box-sizing: border-box;
  border: var(--border-width-default) solid var(--border-color-default);
  border-radius: var(--radius-md);
  background-color: var(--color-surface);
  display: flex;
  flex-direction: column;
  gap: 7px;
}

.topbar,
.destination-row,
.vision-header,
.metric-head,
.control-row {
  display: flex;
  align-items: center;
}

.topbar {
  justify-content: space-between;
  gap: 12px;
}

.brand {
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.eyebrow,
.mini-label,
.field-label {
  color: var(--color-text-secondary);
  font-size: 11px;
  line-height: 1.2;
}

.title {
  color: var(--color-text-primary);
  font-size: 22px;
  font-weight: 800;
  line-height: 1.1;
}

.route-state {
  min-width: 78px;
  padding: 7px 10px;
  box-sizing: border-box;
  border: var(--border-width-default) solid var(--border-color-muted);
  border-radius: var(--radius-sm);
  color: var(--color-text-secondary);
  background-color: var(--color-background);
  text-align: center;
  font-size: 13px;
  font-weight: 800;
}

.route-ok {
  border-color: var(--border-color-success);
  color: var(--color-primary);
  background-color: var(--color-primary-40);
}

.route-warn {
  border-color: var(--border-color-warning);
  color: var(--color-text-primary);
  background-color: var(--color-surface-highlight);
}

.route-off {
  border-color: var(--border-color-danger);
  color: var(--color-text-primary);
  background-color: var(--color-surface-highlight);
}

.route-done {
  border-color: var(--border-color-success);
  color: var(--color-background);
  background-color: var(--color-primary);
}

.destination-row {
  gap: 8px;
}

.field-label {
  width: 44px;
  flex-shrink: 0;
}

.destination-value {
  flex-grow: 1;
  min-width: 0;
  height: 34px;
  padding: 0 10px;
  box-sizing: border-box;
  border: var(--input-border-width) solid var(--input-border-color);
  border-radius: var(--input-radius);
  background-color: var(--input-background-color);
  color: var(--color-text-primary);
  font-size: 14px;
  font-weight: 800;
  display: flex;
  align-items: center;
}

.listen-state {
  width: 66px;
  height: 34px;
  box-sizing: border-box;
  border: var(--border-width-default) solid var(--border-color-muted);
  border-radius: var(--radius-sm);
  color: var(--color-text-secondary);
  background-color: var(--color-background);
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 12px;
  font-weight: 800;
}

.listen-active {
  border-color: var(--border-color-accent);
  color: var(--color-primary);
  background-color: var(--color-primary-40);
}

.voice-button,
.scan-button,
.secondary-button,
.reset-button {
  border: var(--border-width-default) solid var(--border-color-accent);
  border-radius: var(--radius-sm);
  font-size: 13px;
  font-weight: 800;
}

.voice-button {
  width: 58px;
  height: 34px;
  color: var(--color-primary);
  background-color: var(--color-background);
}

.vision-panel {
  display: flex;
  flex-direction: column;
  gap: 5px;
}

.vision-header {
  justify-content: space-between;
}

.frame-meta {
  color: var(--color-text-secondary);
  font-size: 11px;
}

.vision-box {
  position: relative;
  height: 78px;
  padding: 12px;
  box-sizing: border-box;
  overflow: hidden;
  border: var(--border-width-default) solid var(--border-color-muted);
  border-radius: var(--radius-md);
  background-color: var(--color-background);
  display: flex;
  flex-direction: column;
  justify-content: center;
  gap: 5px;
}

.camera-frame {
  position: absolute;
  inset: 0;
  width: 100%;
  height: 100%;
  opacity: 0.52;
}

.reticle {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  opacity: 0.4;
}

.reticle-line {
  width: 88%;
  height: 2px;
  background-color: var(--color-primary-60);
}

.reticle-dot {
  position: absolute;
  width: 10px;
  height: 10px;
  border: var(--border-width-default) solid var(--color-primary);
  border-radius: 10px;
  background-color: var(--color-background);
}

.place {
  position: relative;
  z-index: 1;
  color: var(--color-text-primary);
  font-size: 19px;
  font-weight: 800;
  line-height: 1.15;
}

.orientation {
  position: relative;
  z-index: 1;
  color: var(--color-text-secondary);
  font-size: 13px;
  line-height: 1.2;
}

.landmark-row {
  display: flex;
  align-items: flex-start;
  gap: 8px;
}

.chips {
  flex-grow: 1;
  display: flex;
  flex-wrap: wrap;
  gap: 5px;
}

.chip {
  padding: 4px 7px;
  border: var(--border-width-thin) solid var(--border-color-muted);
  border-radius: var(--radius-sm);
  color: var(--color-text-primary);
  background-color: var(--color-background);
  font-size: 11px;
  line-height: 1.1;
}

.guidance {
  min-height: 48px;
  padding: 8px 10px;
  box-sizing: border-box;
  border: var(--border-width-default) solid var(--border-color-accent);
  border-radius: var(--radius-md);
  background-color: var(--color-primary-40);
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.action {
  color: var(--color-text-primary);
  font-size: 16px;
  font-weight: 800;
  line-height: 1.25;
}

.metrics {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 10px;
}

.metric {
  display: flex;
  flex-direction: column;
  gap: 5px;
}

.metric-head {
  justify-content: space-between;
  color: var(--color-text-secondary);
  font-size: 11px;
}

.bar {
  height: 7px;
  overflow: hidden;
  border-radius: 7px;
  background-color: var(--color-background);
}

.bar-fill {
  height: 7px;
  border-radius: 7px;
}

.confidence-fill {
  background-color: var(--color-primary);
}

.progress-fill {
  background-color: var(--color-secondary);
}

.trace-row {
  display: grid;
  grid-template-columns: 1fr 1fr 1fr 1fr;
  gap: 6px;
}

.step {
  height: 28px;
  padding: 4px 5px;
  box-sizing: border-box;
  border: var(--border-width-thin) solid var(--border-color-muted);
  border-radius: var(--radius-sm);
  color: var(--color-text-secondary);
  background-color: var(--color-background);
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 4px;
  font-size: 11px;
  line-height: 1.1;
}

.step-active {
  border-color: var(--border-color-accent);
  color: var(--color-text-primary);
  background-color: var(--color-surface-highlight);
}

.step-index {
  font-weight: 800;
}

.step-label {
  font-weight: 700;
}

.voice-panel {
  min-height: 36px;
  padding: 6px 9px;
  box-sizing: border-box;
  border: var(--border-width-thin) solid var(--border-color-muted);
  border-radius: var(--radius-sm);
  background-color: var(--color-background);
  display: flex;
  flex-direction: column;
  justify-content: center;
  gap: 3px;
}

.voice-command {
  color: var(--color-text-primary);
  font-size: 12px;
  font-weight: 800;
  line-height: 1.1;
}

.voice-hint {
  color: var(--color-text-secondary);
  font-size: 10px;
  line-height: 1.1;
}

.control-row {
  gap: 8px;
}

.scan-button {
  flex-grow: 1;
  height: 36px;
  color: var(--color-background);
  background-color: var(--color-primary);
}

.secondary-button {
  width: 86px;
  height: 36px;
  color: var(--color-primary);
  background-color: var(--color-background);
}

.reset-button {
  width: 58px;
  height: 36px;
  color: var(--color-text-primary);
  background-color: var(--color-background);
  border-color: var(--border-color-muted);
}

.error {
  margin-top: 0;
}
</style>
