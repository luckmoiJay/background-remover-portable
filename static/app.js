const fileInput = document.querySelector("#fileInput");
const dropzone = document.querySelector("#dropzone");
const removeBtn = document.querySelector("#removeBtn");
const previewImage = document.querySelector("#previewImage");
const emptyState = document.querySelector("#emptyState");
const downloadBtn = document.querySelector("#downloadBtn");
const statusPill = document.querySelector("#statusPill");
const fileMeta = document.querySelector("#fileMeta");
const engineMeta = document.querySelector("#engineMeta");
const previewCanvas = document.querySelector("#previewCanvas");
const pasteHint = document.querySelector("#pasteHint");

let selectedFile = null;
let originalUrl = "";
let resultUrl = "";
let currentView = "transparent";

function setStatus(text, kind = "idle") {
  statusPill.textContent = text;
  statusPill.style.color = kind === "error" ? "#b42318" : "";
}

function showImage(url) {
  previewImage.src = url;
  previewImage.classList.add("visible");
  emptyState.classList.add("hidden");
}

function updateDownload(url) {
  if (!url) {
    downloadBtn.removeAttribute("href");
    downloadBtn.classList.add("disabled");
    return;
  }
  downloadBtn.href = url;
  downloadBtn.classList.remove("disabled");
}

function setResult(url, metaText) {
  resultUrl = url;
  currentView = "transparent";
  document.querySelectorAll(".view-btn").forEach((btn) => {
    btn.classList.toggle("active", btn.dataset.view === "transparent");
  });
  previewCanvas.className = "preview-canvas checker";
  showImage(resultUrl);
  updateDownload(resultUrl);
  engineMeta.textContent = metaText;
}

function loadFile(file) {
  selectedFile = file;
  originalUrl = URL.createObjectURL(file);
  resultUrl = "";
  removeBtn.disabled = false;
  fileMeta.textContent = `${file.name} - ${(file.size / 1024 / 1024).toFixed(2)} MB`;
  engineMeta.textContent = "原圖預覽";
  showImage(originalUrl);
  updateDownload("");
  setStatus("已載入");
}

function fileFromClipboard(event) {
  const items = Array.from(event.clipboardData?.items || []);
  const imageItem = items.find((item) => item.type.startsWith("image/"));
  if (!imageItem) return null;

  const blob = imageItem.getAsFile();
  if (!blob) return null;

  const extension = blob.type === "image/jpeg" ? "jpg" : "png";
  return new File([blob], `clipboard-${Date.now()}.${extension}`, { type: blob.type || "image/png" });
}

fileInput.addEventListener("change", () => {
  const file = fileInput.files[0];
  if (file) loadFile(file);
});

["dragenter", "dragover"].forEach((eventName) => {
  dropzone.addEventListener(eventName, (event) => {
    event.preventDefault();
    dropzone.classList.add("dragging");
  });
});

["dragleave", "drop"].forEach((eventName) => {
  dropzone.addEventListener(eventName, (event) => {
    event.preventDefault();
    dropzone.classList.remove("dragging");
  });
});

dropzone.addEventListener("drop", (event) => {
  const file = event.dataTransfer.files[0];
  if (file) loadFile(file);
});

document.addEventListener("paste", (event) => {
  const file = fileFromClipboard(event);
  if (!file) {
    setStatus("沒有圖片", "error");
    engineMeta.textContent = "剪貼簿裡沒有圖片";
    return;
  }

  event.preventDefault();
  loadFile(file);
  setStatus("已貼上");
  dropzone.classList.add("pasted");
  pasteHint.classList.add("active");
  window.setTimeout(() => {
    dropzone.classList.remove("pasted");
    pasteHint.classList.remove("active");
  }, 900);
});

document.querySelectorAll(".view-btn").forEach((button) => {
  button.addEventListener("click", () => {
    currentView = button.dataset.view;
    document.querySelectorAll(".view-btn").forEach((item) => {
      item.classList.toggle("active", item === button);
    });
    previewCanvas.className = `preview-canvas ${currentView === "transparent" || currentView === "checker" ? "checker" : "original"}`;
    if (currentView === "original" && originalUrl) {
      showImage(originalUrl);
    } else if (resultUrl) {
      showImage(resultUrl);
    }
  });
});

removeBtn.addEventListener("click", async () => {
  if (!selectedFile) return;
  const form = new FormData();
  form.append("image", selectedFile);
  form.append("alphaMatting", document.querySelector("#alphaMatting").checked);
  form.append("feather", document.querySelector("#feather").value);
  form.append("sharpen", document.querySelector("#sharpen").value);
  form.append("foregroundThreshold", document.querySelector("#foregroundThreshold").value);
  form.append("backgroundThreshold", document.querySelector("#backgroundThreshold").value);
  form.append("trim", document.querySelector("#trim").checked);

  removeBtn.disabled = true;
  setStatus("處理中");
  engineMeta.textContent = "正在去背";

  try {
    const response = await fetch("/api/remove", { method: "POST", body: form });
    const data = await response.json();
    if (!response.ok) throw new Error(data.error || "去背失敗。");
    setResult(data.image, `${data.engine} - ${data.width}x${data.height}`);
    setStatus("完成");
  } catch (error) {
    setStatus("錯誤", "error");
    engineMeta.textContent = error.message;
  } finally {
    removeBtn.disabled = false;
  }
});
