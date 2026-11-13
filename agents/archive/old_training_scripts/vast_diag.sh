#!/bin/bash
echo "=== GODOT BINARIES ==="
which godot3-server 2>/dev/null && echo "godot3-server: OK" || echo "godot3-server: NO"
which godot3 2>/dev/null && echo "godot3: OK" || echo "godot3: NO"
ls /usr/local/bin/godot* 2>/dev/null || echo "No godot in /usr/local/bin"

echo ""
echo "=== GPU STATUS ==="
nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total --format=csv,noheader 2>/dev/null || echo "nvidia-smi failed"

echo ""
echo "=== DISPLAY / RENDERING ==="
echo "DISPLAY=$DISPLAY"
glxinfo 2>/dev/null | grep "OpenGL renderer" || echo "glxinfo not available"

echo ""
echo "=== TRAINING PROCESS ==="
ps aux | grep -E "train_anna|godot" | grep -v grep || echo "No training process found"

echo ""
echo "=== ANNA PORT STATUS ==="
ss -tlnp | grep -E "500[0-9]" || echo "No ports in 5000-5009 range"

echo ""
echo "=== PYTHON / PYTORCH ==="
python --version 2>&1
python -c "import torch; print('CUDA available:', torch.cuda.is_available()); print('Device:', torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'CPU')" 2>/dev/null

echo ""
echo "=== LAST TRAINING LOG (tail) ==="
ls -lt /root/*/agents/runs/*.log 2>/dev/null | head -3
find /root -name "*.log" -newer /tmp -maxdepth 5 2>/dev/null | head -5

echo ""
echo "=== TENSORBOARD DATA ==="
find /root -name "events.out*" -maxdepth 7 2>/dev/null | head -5

echo ""
echo "=== REPO LOCATION ==="
find /root -name "train_anna_cuda_big.py" 2>/dev/null | head -3
find /workspace -name "train_anna_cuda_big.py" 2>/dev/null | head -3
