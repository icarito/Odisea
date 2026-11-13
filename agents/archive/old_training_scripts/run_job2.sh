#!/bin/bash
source .venv/bin/activate
export OMP_NUM_THREADS=8
export MKL_NUM_THREADS=8
export ANNA_RL_PHYSICS_FPS=3000
export ANNA_RL_TARGET_FPS=3000
export ANNA_RL_DISABLE_CPU_SLEEP=1
export ANNA_GODOT_DISABLE_AUDIO_DRIVER_FLAG=1
python3 -c "
import sys
sys.path.insert(0, 'core_v2/anna/client')
from anna_gym import AnnaGymEnv
from stable_baselines3 import PPO
import time

def log(msg):
    line = f'[{time.strftime(\"%H:%M:%S\")}] {msg}'
    print(line)
    with open('/tmp/job2.log', 'a') as f:
        f.write(line+'\n')

log('JOB 2 START: lr=8e-4, ent=0.10')

# RL
log('RL')
env = AnnaGymEnv('core_v2/tests/TestScene_RL.tscn', port=11100, launch_godot=True, headless=True)
model = PPO('MlpPolicy', env, n_steps=2048, batch_size=512, n_epochs=3, learning_rate=8e-4, ent_coef=0.10, policy_kwargs={'net_arch': dict(pi=[128,128], vf=[128,128])}, verbose=1, device='cpu')
model.learn(total_timesteps=50000, progress_bar=True)
log('RL done')
env.close()

# RL2
log('RL2')
env = AnnaGymEnv('core_v2/tests/TestScene_RL_2.tscn', port=11101, launch_godot=True, headless=True)
model.set_env(env)
model.learn(total_timesteps=100000, progress_bar=True)
log('RL2 done')
env.close()

# RL3_Door
log('RL3_Door')
env = AnnaGymEnv('core_v2/tests/TestScene_RL_3_Door.tscn', port=11102, launch_godot=True, headless=True)
model.set_env(env)
model.learn(total_timesteps=200000, progress_bar=True)

s=0
for _ in range(10):
    obs,_=env.reset()
    done=False
    while not done:
        a,_=model.predict(obs,deterministic=True)
        obs,r,t,tr,_=env.step(int(a))
        done=t or tr
        if t and r>0:
            s+=1
            break
log(f'RL3_Door eval: {s/10*100:.0f}%')
env.close()

# RL4
log('RL4')
env = AnnaGymEnv('core_v2/tests/TestScene_RL_4_TwoFloorRoom.tscn', port=11103, launch_godot=True, headless=True)
model.set_env(env)
model.learn(total_timesteps=300000, progress_bar=True)

s=0
for _ in range(20):
    obs,_=env.reset()
    done=False
    while not done:
        a,_=model.predict(obs,deterministic=True)
        obs,r,t,tr,_=env.step(int(a))
        done=t or tr
        if t and r>0:
            s+=1
            break
log(f'RL4 FINAL: {s/20*100:.0f}%')
env.close()
model.save('core_v2/trained_models/job2.zip')
log('DONE')
"
