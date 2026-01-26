#!/bin/bash
set -e

# ==============================================================================
# 1. 變數與路徑設定
# ==============================================================================
MODEL_DIR="${MINERU_MODEL_DIR:-/app/data/mineru_models}"
REPO_ID="${MINERU_REPO_ID:-opendatalab/PDF-Extract-Kit}"

CONFIG_FILE_ROOT="/root/magic-pdf.json"
CONFIG_FILE_APP="/app/magic-pdf.json"
CONFIG_FILE_DATA="/app/data/magic-pdf.json"

echo "🚀 [MinerU-Init] 初始化環境..."

# ==============================================================================
# 2. 智能 GPU 偵測
# ==============================================================================
if [ -z "$MINERU_DEVICE_MODE" ]; then
    echo "🔍 [MinerU-Init] 未設定運行模式，正在自動偵測 GPU..."
    if python -c "import torch; exit(0 if torch.cuda.is_available() else 1)"; then
        export DEVICE_MODE="cuda"
    else
        export DEVICE_MODE="cpu"
    fi
    echo "💡 [MinerU-Init] 自動偵測結果: $DEVICE_MODE"
else
    export DEVICE_MODE="$MINERU_DEVICE_MODE"
    echo "⚙️ [MinerU-Init] 使用環境變數設定: $DEVICE_MODE"
fi

# ==============================================================================
# 3. 檢查並下載模型
# ==============================================================================
if [ ! -d "$MODEL_DIR/models" ]; then
    echo "⚠️ [MinerU-Init] 未偵測到模型，準備自動下載..."
    mkdir -p "$MODEL_DIR"
    python -c "
import os
from huggingface_hub import snapshot_download
try:
    print('⬇️ 開始下載模型 (約 5GB+)...')
    snapshot_download(repo_id='$REPO_ID', local_dir='$MODEL_DIR', resume_download=True)
    print('✅ 模型下載完成！')
except Exception as e:
    print(f'❌ 下載失敗: {e}')
    exit(1)
"
else
    echo "✅ [MinerU-Init] 模型已存在，跳過下載。"
fi

# ==============================================================================
# 4. 生成並分發 Config
# ==============================================================================
echo "⚙️ [MinerU-Init] 生成設定檔內容..."
CONFIG_CONTENT=$(cat <<EOF
{
  "bucket_info": { "bucket-name-1": ["ak", "sk", "endpoint"], "bucket-name-2": ["ak", "sk", "endpoint"] },
  "models-dir": "$MODEL_DIR/models",
  "device-mode": "$DEVICE_MODE",
  "layout-config": { "model": "doclayout_yolo" },
  "formula-config": { "mfd_model": "yolo_v8", "mfr_model": "unimernet_small" },
  "table-config": { "model": "rapid_table", "model_dir": "$MODEL_DIR/models/Table/RapidTable" }
}
EOF
)
echo "$CONFIG_CONTENT" > "$CONFIG_FILE_ROOT"
echo "$CONFIG_CONTENT" > "$CONFIG_FILE_APP"
echo "$CONFIG_CONTENT" > "$CONFIG_FILE_DATA"
echo "✅ [MinerU-Init] 設定檔已寫入: /root, /app, /app/data"

# ==============================================================================
# 5. [HOTFIX] 地毯式修復 (Recursive Patching)
# ==============================================================================
echo "🔧 [Code-Fix] 執行地毯式代碼修復..."

# 找出 raganything 包的安裝路徑
PKG_DIR=$(find /app/.venv -type d -name "raganything" | head -n 1)

if [ -d "$PKG_DIR" ]; then
    echo "📂 找到目標目錄: $PKG_DIR"
    
    # 使用 Python 遞歸掃描並修改所有 .py 檔案
    python -c "
import os
import re

target_dir = '$PKG_DIR'
count_formula = 0
count_table = 0

print(f'🔍 開始掃描目錄: {target_dir}')

for root, dirs, files in os.walk(target_dir):
    for file in files:
        if file.endswith('.py'):
            file_path = os.path.join(root, file)
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()
            
            new_content = content
            
            # 1. 修復 Import (如果存在)
            new_content = new_content.replace('from lightrag.mineru_parser import MineruParser', 'from .mineru_parser import MineruParser')
            
            # 2. 強力關閉 Formula (處理各種寫法: =, :, 空格)
            # 匹配 apply_formula=True 或 'apply_formula': True
            new_content = re.sub(r'([\"\']?apply_formula[\"\']?)\s*[:=]\s*True', r'\1=False', new_content)
            
            # 3. 強力開啟 Table
            # 匹配 apply_table=False 或 'apply_table': False
            new_content = re.sub(r'([\"\']?apply_table[\"\']?)\s*[:=]\s*False', r'\1=True', new_content)

            if new_content != content:
                print(f'✏️ 修復檔案: {file}')
                if 'apply_formula=False' in new_content: count_formula += 1
                if 'apply_table=True' in new_content: count_table += 1
                with open(file_path, 'w', encoding='utf-8') as f:
                    f.write(new_content)

print(f'✅ 修復完成! 共修改 Formula 處: {count_formula}, Table 處: {count_table}')
"
else
    echo "⚠️ [Code-Fix] 未找到 raganything 目錄，跳過修復。"
fi

echo "🔍 [Dep-Check] 確認環境完整性..."
python -c "import magic_pdf, cv2, ultralytics, paddle, rapid_table; print('✅ 所有引擎檢測通過！Ready to launch.')"

# ==============================================================================
# 6. 啟動 LightRAG Server
# ==============================================================================
echo "✨ [LightRAG] 啟動主程式..."
exec python -m lightrag.api.lightrag_server