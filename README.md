# TaiwanStockTracker (台股績效與配股監控 iOS App)

專為台股投資人設計之績效監控應用，支援：
- **持股損益試算**：手續費折讓、證交稅（個股 0.3% / ETF 0.1%）、未實現損益與報酬率。
- **每月配股配息追蹤**：現金股利入帳試算、配股新增股數試算、二代健保補充保費（2 萬以上 2.11%）試算。
- **iOS 鎖定畫面小工具 (WidgetKit)**：支援 `accessoryInline`、`accessoryCircular`、`accessoryRectangular` 鎖定畫面即時顯示總市值、未實現損益與本月配股。
- **免 Mac 雲端打包**：透過 XcodeGen 與 GitHub Actions，在 Windows 也能自動產生 `.ipa` 檔。

## 快速推送到 GitHub 自動打包 IPA

1. 在 GitHub 上建立一個新的儲存庫（建議設為 Private），例如 `TaiwanStockTracker`。
2. 在本地專案目錄執行：
   ```powershell
   cd C:\Users\Edision\TaiwanStockTracker
   git init
   git add .
   git commit -m "Initial commit"
   git branch -M main
   git remote add origin https://github.com/<你的GitHub帳號>/TaiwanStockTracker.git
   git push -u origin main
   ```
3. 前往 GitHub 倉庫的 **Actions** 頁面，`Build TaiwanStockTracker IPA` 工作流將自動啟動。
4. 建置完成後，在 **Artifacts** 區塊下載 `TaiwanStockTracker-IPA` 解壓縮即可取得 `TaiwanStockTracker.ipa`。

## 側載安裝至 iPhone

- **TrollStore**（iOS 14.0 - 16.6.1 / 17.0 特定支援）：直接開啟 IPA 安裝，Widget 與 App Group 完美運作。
- **Sideloadly / AltStore**：使用個人 Apple ID 免費自簽安裝，請確保在進階設定保留 App Extension。
