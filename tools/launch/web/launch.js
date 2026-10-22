const device = document.querySelector("#device");
const bundle = document.querySelector("#bundle");
const duration = document.querySelector("#duration");
const throttle = document.querySelector("#throttle");
const dataport = document.querySelector("#dataport");
const shots = document.querySelector("#shots");
const perf = document.querySelector("#perf");
const start = document.querySelector("#start");
const stop = document.querySelector("#stop");
const check = document.querySelector("#check");
const stubCheck = document.querySelector("#stub-check");
const dataportNote = document.querySelector("#dataport-note");
const refresh = document.querySelector("#refresh");
const status = document.querySelector("#status");
const statusRow = document.querySelector("#status-row");
const log = document.querySelector("#log");
const logPane = document.querySelector(".log-pane");
const copyLog = document.querySelector("#copy-log");
const exportLog = document.querySelector("#export-log");
const exportRun = document.querySelector("#export-run");
const deviceMeta = document.querySelector("#device-meta");

const LIMITS = {
  duration: [1, 10080],
  throttle: [1, 60000],
  dataport: [0, 65535]
};

let savedBundle = "";
let savedUdid = "";
let prefsLoaded = false;
let shownExit = null;
let appsRequest = 0;
let statusKind = "idle";

function setStatus(text, kind) {
  status.textContent = text || "等待开始";
  statusKind = kind || "idle";
  statusRow.className = "status-row " + statusKind;
}

function setLog(text) {
  const content = text || "";
  log.textContent = content;
  logPane.classList.toggle("has-log", content.length > 0);
}

function setFieldError(id, message) {
  const control = document.querySelector("#" + id);
  const error = document.querySelector("#" + id + "-error");
  error.textContent = message || "";
  control.classList.toggle("invalid", Boolean(message));
  control.setAttribute("aria-invalid", message ? "true" : "false");
}

function setNote(text, kind) {
  dataportNote.textContent = text || "";
  dataportNote.className = "field-note" + (kind ? " " + kind : "");
}

function integerInRange(raw, low, high) {
  const text = String(raw == null ? "" : raw).trim();
  if (!/^\d+$/.test(text)) {
    return null;
  }
  const value = Number(text);
  if (!Number.isSafeInteger(value) || value < low || value > high) {
    return null;
  }
  return value;
}

function problems() {
  const errors = {};
  if (!device.value) {
    errors.device = "先选择一台设备";
  }
  if (!bundle.value) {
    errors.bundle = "先选择一个 Bundle ID";
  }
  if (integerInRange(duration.value, LIMITS.duration[0], LIMITS.duration[1]) == null) {
    errors.duration = "需要是 1 到 10080 的整数分钟";
  }
  if (integerInRange(throttle.value, LIMITS.throttle[0], LIMITS.throttle[1]) == null) {
    errors.throttle = "需要是 1 到 60000 的整数毫秒";
  }
  // 留空表示不用 stub。填了就必须是端口号。
  if (String(dataport.value).trim() !== "" &&
      integerInRange(dataport.value, LIMITS.dataport[0], LIMITS.dataport[1]) == null) {
    errors.dataport = "需要是 0 到 65535 的整数，留空则不用 stub";
  }
  return errors;
}

function showProblems(errors) {
  setFieldError("device", errors.device || "");
  setFieldError("bundle", errors.bundle || "");
  setFieldError("duration", errors.duration || "");
  setFieldError("throttle", errors.throttle || "");
  setFieldError("dataport", errors.dataport || "");
}

async function readJson(url, options) {
  const response = await fetch(url, options);
  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    const error = new Error(body.error || "请求失败");
    error.field = body.field || "";
    throw error;
  }
  return body;
}

function fillSelect(select, items, placeholder) {
  select.replaceChildren();
  if (items.length === 0) {
    const option = document.createElement("option");
    option.value = "";
    option.textContent = placeholder;
    select.appendChild(option);
    select.disabled = true;
    return;
  }
  select.disabled = false;
  for (const item of items) {
    const option = document.createElement("option");
    option.value = item.value;
    option.textContent = item.label;
    select.appendChild(option);
  }
}

function fillDevices(devices) {
  device.replaceChildren();
  deviceMeta.textContent = devices.length === 0 ? "未连接设备" : "已连接 " + devices.length + " 台设备";
  if (devices.length === 0) {
    fillSelect(device, [], "没有连接的设备");
    setFieldError("device", "没有连接的设备");
    return;
  }
  const known = devices.some((item) => item.udid === savedUdid);
  if (devices.length > 1 && !known) {
    const prompt = document.createElement("option");
    prompt.value = "";
    prompt.textContent = "选择设备";
    device.appendChild(prompt);
  }
    for (const item of devices) {
    const option = document.createElement("option");
    option.value = item.udid;
    option.textContent = item.label;
    option.dataset.kind = item.kind || "device";
    device.appendChild(option);
  }
  device.disabled = false;
  if (known) {
    device.value = savedUdid;
  }
  setFieldError("device", "");
}

async function loadApps() {
  const request = ++appsRequest;
  const udid = device.value;
  if (!udid) {
    fillSelect(bundle, [], "先选择设备");
    setFieldError("bundle", "");
    return;
  }
  fillSelect(bundle, [], "正在读取应用");
  bundle.disabled = true;
  setFieldError("bundle", "");
  try {
    const data = await readJson("/api/apps?udid=" + encodeURIComponent(udid));
    if (request !== appsRequest) {
      return;
    }
    const items = (data.apps || []).map((app) => ({ value: app.bundleId, label: app.label }));
    fillSelect(bundle, items, "这台设备上没有读到用户应用");
    if (savedBundle && [...bundle.options].some((option) => option.value === savedBundle)) {
      bundle.value = savedBundle;
    }
    setFieldError("bundle", bundle.value ? "" : "这台设备上没有读到用户应用");
  } catch (error) {
    if (request !== appsRequest) {
      return;
    }
    fillSelect(bundle, [], "应用列表读取失败");
    setFieldError("bundle", error.message);
  }
}

async function loadDevices() {
  const data = await readJson("/api/devices");
  if (!prefsLoaded) {
    duration.value = data.duration || 1;
    throttle.value = data.throttle || 300;
    dataport.value = data.dataport > 0 ? data.dataport : "";
    shots.value = data.shots || "off";
    perf.value = data.perf ? "on" : "off";
    savedBundle = data.bundleId || "";
    savedUdid = data.udid || "";
    prefsLoaded = true;
  }
  fillDevices(data.devices || []);
  await loadApps();
}

function selectedSimulator() {
  const option = device.selectedOptions[0];
  return Boolean(option && option.dataset.kind === "simulator");
}

function syncTargetLimits() {
  const sim = selectedSimulator();
  stubCheck.disabled = start.disabled || !device.value || !bundle.value || sim;
  stubCheck.title = sim
    ? "模拟器无法从电脑探测插桩，开跑后由 Runner 自行探测"
    : "在手机上启动被测应用，确认它接入了插桩并在这个端口应答";
  perf.title = sim
    ? "模拟器没有电脑端 Instruments。开启后仅在插桩模式下由 Runner 采集内存、CPU、主线程卡顿、内存警告"
    : "电脑端每秒采一次被测应用的内存、CPU、线程数、磁盘读写、文件与端口数、唤醒次数和屏幕帧率，并记录前后台切换；插桩模式下另外每步向插桩读一次内存、CPU、主线程卡顿、内存警告和设备温度。结果和采样报告随设备结果一起导出";
}

function applyStatus(data) {
  const collecting = Boolean(data.collecting);
  const running = Boolean(data.running) || collecting;
  const checking = data.test === "check";
  start.disabled = running;
  check.disabled = running || !device.value;
  if (data.backend) {
    document.querySelector(".brand .sub").textContent = "本地启动 · " + (data.backend === "goios" ? "go-ios" : "Xcode");
  }
  stubCheck.disabled = running || !device.value || !bundle.value;
  syncTargetLimits();
  if (data.running && data.stubCheck) {
    setNote(data.stubCheck, /success/.test(data.stubCheck) ? "ok" : "warn");
  }
  stop.disabled = !data.running;
  device.disabled = running || device.options.length === 0;
  bundle.disabled = running || !device.value || !bundle.value;
  showChoice(device);
  showChoice(bundle);
  refresh.disabled = running || !device.value;
  duration.disabled = running;
  throttle.disabled = running;
  dataport.disabled = running;
  shots.disabled = running;
  perf.disabled = running;
  const hasLog = Boolean(data.hasLog) || Boolean(data.log);
  copyLog.disabled = !hasLog;
  exportLog.disabled = !hasLog;
  exportRun.disabled = !data.hasExport;
  const nearBottom = log.scrollHeight - log.scrollTop - log.clientHeight < 24;
  setLog(data.log || "");
  if (nearBottom) {
    log.scrollTop = log.scrollHeight;
  }
  if (collecting) {
    shownExit = null;
    setStatus(data.simulator || selectedSimulator() ? "正在拉回结果" : "正在收集设备结果和崩溃日志", "running");
  } else if (running) {
    shownExit = null;
    setStatus(checking ? "通信检查进行中" : "测试进行中", "running");
  } else if (data.exitCode != null && data.exitCode !== shownExit) {
    shownExit = data.exitCode;
    if (checking) {
      setStatus(data.exitCode === 0 ? "通信检查通过" : "通信检查未通过，退出码 " + data.exitCode, data.exitCode === 0 ? "done" : "error");
    } else if (data.exitCode === 0) {
      setStatus("这一轮已结束", "done");
    } else {
      setStatus("这一轮已停止，退出码 " + data.exitCode, "error");
    }
  } else if (!running && statusKind === "running") {
    setStatus("等待开始", "idle");
  }
}

async function refreshStatus() {
  const data = await readJson("/api/status");
  applyStatus(data);
  return data;
}

// The closed select cuts long labels; the tooltip shows the whole choice.
function showChoice(select) {
  const chosen = select.selectedOptions[0];
  select.title = chosen ? chosen.textContent : "";
}

function showField(id) {
  const current = problems();
  setFieldError(id, current[id] || "");
}

device.addEventListener("change", () => {
  showChoice(device);
  savedBundle = "";
  setNote(selectedSimulator() ? "模拟器开跑后由 Runner 探测插桩；电脑端不采帧率、不拉崩溃日志" : "");
  setFieldError("device", device.value ? "" : "先选择一台设备");
  syncTargetLimits();
  loadApps().then(refreshStatus).catch((error) => setStatus(error.message, "error"));
});

refresh.addEventListener("click", () => {
  loadApps().then(refreshStatus).catch((error) => setFieldError("bundle", error.message));
});

duration.addEventListener("input", () => showField("duration"));
duration.addEventListener("change", () => showField("duration"));
throttle.addEventListener("input", () => showField("throttle"));
throttle.addEventListener("change", () => showField("throttle"));
dataport.addEventListener("input", () => {
  showField("dataport");
  setNote("");
});
dataport.addEventListener("change", () => showField("dataport"));
bundle.addEventListener("change", () => {
  showChoice(bundle);
  setNote("");
  stubCheck.disabled = !device.value || !bundle.value || start.disabled;
});

stubCheck.addEventListener("click", async () => {
  const all = problems();
  const port = integerInRange(dataport.value, LIMITS.dataport[0], LIMITS.dataport[1]) || 0;
  const errors = {};
  for (const key of ["device", "bundle"]) {
    if (all[key]) {
      errors[key] = all[key];
    }
  }
  if (all.dataport) {
    errors.dataport = all.dataport;
  } else if (port === 0) {
    errors.dataport = "先填写数据端口";
  }
  showProblems(errors);
  if (Object.keys(errors).length > 0) {
    return;
  }
  stubCheck.disabled = true;
  setNote("正在手机上重启被测应用并探测端口，约需 10 秒");
  try {
    const query = new URLSearchParams({ udid: device.value, bundleId: bundle.value, dataport: String(port) });
    const data = await readJson("/api/stub?" + query.toString());
    setNote(data.message, data.state === "ok" ? "ok" : "warn");
  } catch (error) {
    if (error.field) {
      setFieldError(error.field, error.message);
    }
    setNote(error.message, "warn");
  } finally {
    stubCheck.disabled = !device.value || !bundle.value || start.disabled;
  }
});

document.querySelector("#launch-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const errors = problems();
  showProblems(errors);
  if (Object.keys(errors).length > 0) {
    setStatus("先改掉标红的输入", "warn");
    return;
  }
  start.disabled = true;
  const port = integerInRange(dataport.value, LIMITS.dataport[0], LIMITS.dataport[1]) || 0;
  setStatus(port > 0 ? "正在检测插桩并启动" : "正在启动", "running");
  try {
    const data = await readJson("/api/start", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        udid: device.value,
        bundleId: bundle.value,
        duration: integerInRange(duration.value, LIMITS.duration[0], LIMITS.duration[1]),
        throttle: integerInRange(throttle.value, LIMITS.throttle[0], LIMITS.throttle[1]),
        dataport: integerInRange(dataport.value, LIMITS.dataport[0], LIMITS.dataport[1]) || 0,
        shots: shots.value,
        perf: perf.value === "on"
      })
    });
    showProblems({});
    applyStatus(data);
  } catch (error) {
    if (error.field) {
      setFieldError(error.field, error.message);
    }
    setStatus(error.message, "error");
    start.disabled = false;
  }
});

check.addEventListener("click", async () => {
  const all = problems();
  const port = integerInRange(dataport.value, LIMITS.dataport[0], LIMITS.dataport[1]) || 0;
  const errors = {};
  for (const key of ["device", "dataport"]) {
    if (all[key]) {
      errors[key] = all[key];
    }
  }
  if (port > 0 && all.bundle) {
    errors.bundle = "检查插桩时需要选择被测应用";
  }
  showProblems(errors);
  if (Object.keys(errors).length > 0) {
    setStatus("先改掉标红的输入", "warn");
    return;
  }
  check.disabled = true;
  start.disabled = true;
  setStatus("正在启动通信检查", "running");
  try {
    const data = await readJson("/api/start", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        test: "check",
        udid: device.value,
        bundleId: port > 0 ? bundle.value : "",
        dataport: port
      })
    });
    applyStatus(data);
  } catch (error) {
    if (error.field) {
      setFieldError(error.field, error.message);
    }
    setStatus(error.message, "error");
    check.disabled = false;
    start.disabled = false;
  }
});

async function fetchLogText() {
  const response = await fetch("/api/log");
  if (!response.ok) {
    throw new Error("日志读取失败");
  }
  return response.text();
}

copyLog.addEventListener("click", async () => {
  try {
    const text = await fetchLogText();
    if (!text) {
      copyLog.textContent = "空";
      return;
    }
    await navigator.clipboard.writeText(text);
    copyLog.textContent = "已复制";
  } catch (error) {
    copyLog.textContent = "失败";
    setStatus(error.message, "error");
  }
  setTimeout(() => {
    copyLog.textContent = "复制";
  }, 1600);
});

function download(href) {
  const link = document.createElement("a");
  link.href = href;
  document.body.appendChild(link);
  link.click();
  link.remove();
}

exportLog.addEventListener("click", () => download("/api/log?download=1"));

exportRun.addEventListener("click", () => download("/api/export"));

stop.addEventListener("click", async () => {
  stop.disabled = true;
  setStatus("正在终止", "warn");
  try {
    applyStatus(await readJson("/api/stop", { method: "POST" }));
  } catch (error) {
    setStatus(error.message, "error");
    stop.disabled = false;
  }
});

loadDevices()
  .then(refreshStatus)
  .catch((error) => {
    setFieldError("device", error.message);
    setStatus(error.message, "error");
  });

setInterval(() => {
  refreshStatus().catch((error) => setStatus(error.message, "error"));
}, 1000);
