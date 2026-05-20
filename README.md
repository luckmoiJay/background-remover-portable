# 本機去背工具

這是一個可攜式 Windows 本機去背網站。解壓縮後執行 `run.ps1`，它會自動建立虛擬環境、安裝套件、預熱模型，最後開啟網站。

## 啟動

最簡單方式：直接雙擊

```text
啟動去背工具.bat
```

如果想用 PowerShell 手動啟動：

如果 PowerShell 允許直接執行腳本：

```powershell
.\run.ps1
```

如果被 Execution Policy 擋住，改用：

```powershell
powershell -ExecutionPolicy Bypass -File .\run.ps1
```

## 本機使用

啟動後用：

```text
http://127.0.0.1:5000
```

## 同網路使用

現在網站會綁定 `0.0.0.0:5000`，同一個 Wi-Fi 或區網的人可以用你的電腦 IP 連線。

`run.ps1` 啟動時會顯示類似：

```text
LAN URL for other devices on the same network:
  http://192.168.1.23:5000
```

把這個網址傳給同網路的人即可。

如果連不上，通常是 Windows 防火牆擋住。腳本會嘗試自動新增防火牆規則；如果失敗，請手動允許 TCP port `5000` 的私人網路連線。

## 打包搬家

在原電腦執行：

```powershell
powershell -ExecutionPolicy Bypass -File .\make_zip.ps1
```

把產生的 `background-remover-portable.zip` 複製到新電腦，解壓縮後執行 `run.ps1`。

## 注意

- 新電腦第一次需要網路，會下載 Python 套件與 `rembg` 模型。
- 如果新電腦沒有 Python，腳本會先嘗試用 `winget` 自動安裝 Python 3.11。
- 不需要搬 `.venv`，新電腦會自己建立。
