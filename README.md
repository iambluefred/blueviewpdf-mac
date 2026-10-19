# BlueViewPDF

快速看 PDF 的 Mac App（BlueView 系列）。用 macOS 內建的 PDFKit，只看不改：不會寫回任何檔案。

## 功能

| 功能 | 說明 |
| --- | --- |
| 開檔 | ⌘O、把 PDF 拖進視窗或 Dock 圖示、Finder「打開檔案的應用程式」；「檔案 → 最近開啟」及歡迎畫面列出最近 10 個檔案 |
| 記住位置 | 每個檔案記住上次看到第幾頁，下次開啟直接回到那頁 |
| 側邊欄 | 縮圖／目錄（書籤，可展開，粗體標示目前章節）／搜尋結果；拖曳分隔線調整寬度（雙擊恢復），縮圖跟著變大 |
| 頁面排列 | 單頁、連續捲動、雙頁、雙頁連續捲動；書本模式（封面單獨一頁） |
| 縮放 | ⌘0 符合視窗、⌘1 100%、⌘＋／⌘－、觸控板捏合；底部列顯示百分比 |
| 翻頁 | ⌥⌘↑／⌥⌘↓ 上一頁／下一頁、Home／End 第一頁／最後一頁、⌥⌘G 跳到頁碼、⌘[ ／ ⌘] 返回／向前（點目錄或連結後可回來） |
| 搜尋 | ⌘F；Return 或 ⌘G 下一個、⇧⌘G 上一個、Esc 清除；從目前這頁開始找；所有結果標黃色，側邊欄列出頁碼與前後文。中文 PDF 也找得到：自動忽略空白，並把 macOS 產生的 PDF 裡的康熙部首字（例如「⾴」）當成一般字（「頁」） |
| 資訊 | ⌥⌘I：標題、作者、頁數、頁面尺寸（mm 與紙張名稱 A4／Letter…）、檔案大小、PDF 版本、日期、建立程式、加密與權限 |
| 密碼 | 有密碼的 PDF 會出現解鎖畫面 |
| 其他 | ⌘P 列印、⌘C 複製選取的文字、⇧⌘R 在 Finder 中顯示、⇧⌘W 關閉 PDF |
| 介面 | 繁體中文／English（顯示方式 → 語言） |

## 建置

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project BlueViewPDF.xcodeproj -scheme BlueViewPDF -configuration Release -derivedDataPath build.noindex build
ditto build.noindex/Build/Products/Release/BlueViewPDF.app /Applications/BlueViewPDF.app
```

測試：

```bash
xcodebuild -project BlueViewPDF.xcodeproj -scheme BlueViewPDF -configuration Release ENABLE_TESTABILITY=YES \
  -derivedDataPath build.noindex test
```

## 提交前檢查

每次提交前會自動檢查有沒有金鑰、密碼或敏感檔案（`.githooks/pre-commit`）。重新 clone 之後要先執行一次：

```bash
git config core.hooksPath .githooks
```
