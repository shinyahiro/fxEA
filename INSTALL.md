# fxEA インストール手順

## 前提条件

- MetaTrader 4 がインストールされていること
- 自動売買が有効なブローカー口座

---

## インストール手順

### 1. MT4データフォルダを開く

1. MT4を起動
2. メニューから「ファイル」→「データフォルダを開く」
3. `MQL4`フォルダが表示される

### 2. ファイルをコピー

#### includeファイル
以下のファイルを `MQL4/Include/fxEA/` にコピー:

```
src/include/Utils.mqh           → MQL4/Include/fxEA/Utils.mqh
src/include/RiskManager.mqh     → MQL4/Include/fxEA/RiskManager.mqh
src/include/PositionManager.mqh → MQL4/Include/fxEA/PositionManager.mqh
src/include/Strategy_Base.mqh   → MQL4/Include/fxEA/Strategy_Base.mqh
src/include/Strategy_MACross.mqh→ MQL4/Include/fxEA/Strategy_MACross.mqh
```

#### EAファイル
以下のファイルを `MQL4/Experts/fxEA/` にコピー:

```
src/experts/fxEA.mq4 → MQL4/Experts/fxEA/fxEA.mq4
```

### 3. includeパスを修正

`fxEA.mq4`の冒頭にある#include文を修正:

```mql4
// 変更前
#include "../include/Utils.mqh"

// 変更後
#include <fxEA/Utils.mqh>
```

すべてのinclude文を同様に修正してください。

### 4. コンパイル

1. MetaEditorを開く（MT4でF4キー）
2. `MQL4/Experts/fxEA/fxEA.mq4`を開く
3. F7キーでコンパイル
4. エラーが0であることを確認

### 5. EAをチャートに配置

1. MT4に戻る
2. ナビゲーターを右クリック →「更新」
3. 「エキスパートアドバイザ」→「fxEA」→「fxEA」
4. USDJPYのH1チャートにドラッグ&ドロップ

### 6. 設定確認

1. 「全般」タブで「自動売買を許可する」にチェック
2. 「パラメーターの入力」タブでパラメータを確認
3. 「OK」をクリック

### 7. 自動売買を有効化

- ツールバーの「自動売買」ボタンが**緑色**になっていることを確認
- 赤色の場合はクリックして有効化

---

## RiskGuardとの併用

fxEAはRiskGuardと連携するよう設計されています。

1. autoEAリポジトリから`RiskGuard.mq4`を取得
2. 任意のチャート（メインチャートでなくてOK）にRiskGuardをアタッチ
3. fxEAの`RespectRiskGuard`パラメータを`true`に設定

これにより、日次/週次損失上限や連敗検知が有効になります。

---

## トラブルシューティング

### コンパイルエラー
- includeパスが正しいか確認
- すべてのファイルがコピーされているか確認

### 取引が行われない
- 自動売買が有効か確認（緑色のボタン）
- 時間フィルターの時間内か確認
- スプレッドが最大値を超えていないか確認
- チャートの時間足がH1か確認

### 「Trading is disabled」エラー
- ブローカーの自動売買が許可されているか確認
- デモ口座で試す

---

## 推奨テスト手順

1. **バックテスト**: ストラテジーテスターでUSDJPY H1、直近2-3年をテスト
2. **デモテスト**: デモ口座で1-3ヶ月のフォワードテスト
3. **小ロット本番**: 0.01ロットで本番開始
4. **段階的増額**: 結果を見ながらロットを増やす

---

## パラメータ調整のヒント

| シーン | 調整 |
|--------|------|
| シグナルが少ない | UseTrendFilter=false, 時間帯を広げる |
| 損切りが多い | SLAtrMultiplier を増やす (2.5-3.0) |
| 利益が伸びない | TPAtrMultiplier を増やす |
| BE移動が遅い | BreakEvenATRMult を下げる (1.0-1.2) |
