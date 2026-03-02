#!/bin/bash
source .venv/bin/activate

export OMP_NUM_THREADS=8
export MKL_NUM_THREADS=8
export ANNA_RL_PHYSICS_FPS=4000
export ANNA_RL_TARGET_FPS=4000
export ANNA_RL_DISABLE_CPU_SLEEP=1
export ANNA_GODOT_DISABLE_AUDIO_DRIVER_FLAG=1

echo "Starting GA competition..."

for variant in "v1:6e-4:0.08:128,128" "v2:8e-4:0.10:128,128" "v3:5e-4:0.06:160,128,64" "v4:4e-4:0.05:256,128"; do
    NAME=$(echo $variant | cut -d: -f1)
    LR=$(echo $variant | cut -d: -f2)
    ENT=$(echo $variant | cut -d: -f3)
    ARCH=$(echo $variant | cut -d: -f4)
    
    echo "=== $NAME: lr=$LR ent=$ENT arch=$ARCH ==="
    
    python3 -c "
import sys, os, time
sys.path.insert(0, 'core_v2/anna/client')
from anna_gym import AnnaGymEnv
from stable_baselines3 import PPO
from stable_baselines3.common.vec_env import DummyVecEnv

def log(msg):
    with open('/tmp/ga_${NAME}.log', 'a') as f:
        f.write(f'{time.strftime(\"%H:%M:%S\")} {msg}\n')
    print(msg)

log('START: $NAME lr=$LR ent=$ENT arch=[$ARCH]')

# RL
log('RL')
env = DummyVecEnv([lambda: AnnaGymEnv('core_v2/tests/TestScene_RL.tscn', port=14000, launch_godot=True, headless=True)])
model = PPO('MlpPolicy', env, n_steps=2048, batch_size=512, n_epochs=3, learning_rate=$LR, ent_coef=$ENT, policy_kwargs={'net_arch': dict(pi=[$ARCH], vf=[$ARCH])}, verbose=1, device='cpu')
model.learn(total_timesteps=30000, progress_bar=True)
log('RL done')
env.close()

# RL2
log('RL2')
env = DummyVecEnv([lambda: AnnaGymEnv('core_v2/tests/TestScene_RL_2.tscn', port=14001, launch_godot=True, headless=True)])
model.set_env(env)
model.learn(total_timesteps=60000, progress_bar=True)
log('RL2 done')
env.close()

# RL3_Door
log('RL3_Door')
env = DummyVecEnv([lambda: AnnaGymEnv('core_v2/tests/TestScene_RL_3_Door.tscn', port=14002, launch_godot=True, headless=True)])
model.set_env(env)
model.learn(total_timesteps=100000, progress_bar=True)

s=0
for _ in range(5):
    obs,_=env.reset()
    done=False
    while not done:
        a,_=model.predict(obs,deterministic=True)
        obs,r,t,tr,_=env.step(int(a))
        done=t or tr
        if t and r>0: s+=1; break
log(f'RL3_Door eval: {s/5*100:.0f}%')
rl3=s/5*100
env.close()

# RL4
log('RL4')
env = DummyVecEnv([lambda: AnnaGymEnv('core_v2/tests/TestScene_RL_4_TwoFloorRoom.tscn', port=14003, launch_godot=True, headless=True)])
model.set_env(env)
model.learn(total_timesteps=150000, progress_bar=True)

s=0
for _ in range(10):
    obs,_=env.reset()
    done=False
    while not done:
        a,_=model.predict(obs,deterministic=True)
        obs,r,t,tr,_=env.step(int(a))
        done=t or tr
        if t and r>0: s+=1; break
log(f'RL4 FINAL: {s/10*100:.0f}%')
rl4=s/10*100
env.close()

model.save(f'core_v2/trained_models/ga_$NAME.zip')
log(f'SAVED ga_$NAME.zip')
log(f'SCORES: RL3={rl3:.0f}% RL4={rl4:.0f}%')
"
    
    echo "=== $NAME complete ==="
done

echo "GA Competition done!"
