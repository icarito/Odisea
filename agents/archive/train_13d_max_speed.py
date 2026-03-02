#!/usr/bin/env python3
"""
MAX SPEED TRAINING 13D - Optimized for throughput and stability
- Full curriculum: RL -> RL2 -> RL3_Door -> RL4
- Using 13D observations
- Single process per environment to maximize Godot headless FPS
- Extra Godot launch flags to mitigate bottlenecks
- Verbose logging to console (SB3 Tables) and /tmp
"""
import sys, os, time
import subprocess

LOG_FILE = '/tmp/13d_max_speed.log'

def log(msg):
    ts = time.strftime("%H:%M:%S")
    line = f"[{ts}] {msg}"
    print(line)
    try:
        with open(LOG_FILE, 'a') as f:
            f.write(line + '\n')
    except:
        pass

def cleanup():
    log("🧹 Cleaning up lingering Godot instances...")
    subprocess.run(["pkill", "-f", "godot3-mono-bin -m"], stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-f", "godot3-server -m"], stderr=subprocess.DEVNULL)
    time.sleep(1)

cleanup()

sys.path.insert(0, 'core_v2/anna/client')
from anna_gym import AnnaGymEnv
from stable_baselines3 import PPO
from stable_baselines3.common.vec_env import DummyVecEnv

MODELS_DIR = 'core_v2/trained_models'
os.makedirs(MODELS_DIR, exist_ok=True)

# OPTIMIZED CONFIG
N_ENVS = 1
PHYSICS_FPS = 4000
BASE_PORT = 12000

BEST_PARAMS = {
    'lr': 6e-4,
    'ent': 0.08,
    'arch': [128, 128],
}

STAGES = [
    ('RL', 'core_v2/tests/TestScene_RL.tscn', 50000),
    ('RL2', 'core_v2/tests/TestScene_RL_2.tscn', 100000),
    ('RL3', 'core_v2/tests/TestScene_RL_3_Door.tscn', 800000),
    ('RL4', 'core_v2/tests/TestScene_RL_4_TwoFloorRoom.tscn', 500000),
]


def make_env(scene_path, port_offset):
    def _init():
        port = BASE_PORT + port_offset
        os.environ['ANNA_RL_PHYSICS_FPS'] = str(PHYSICS_FPS)
        os.environ['ANNA_RL_TARGET_FPS'] = str(PHYSICS_FPS)
        os.environ['ANNA_RL_DISABLE_CPU_SLEEP'] = '1'
        os.environ['ANNA_GODOT_DISABLE_AUDIO_DRIVER_FLAG'] = '1'
        return AnnaGymEnv(scene_path, port=port, launch_godot=True, headless=True)
    return _init


def make_eval_env(scene_path, port_offset):
    port = BASE_PORT + 500 + port_offset
    os.environ['ANNA_RL_PHYSICS_FPS'] = '60'
    os.environ['ANNA_GODOT_DISABLE_AUDIO_DRIVER_FLAG'] = '1'
    return AnnaGymEnv(scene_path, port=port, launch_godot=True, headless=True)


def eval_model(model, scene, port, episodes=10):
    env = make_eval_env(scene, port)
    successes = 0
    for _ in range(episodes):
        obs, _ = env.reset()
        done = False
        while not done:
            action, _ = model.predict(obs, deterministic=True)
            obs, reward, terminated, truncated, _ = env.step(int(action))
            done = terminated or truncated
            if terminated and reward > 0:
                successes += 1
                break
    env.close()
    return successes / episodes * 100


def main():
    open(LOG_FILE, 'w').close()
    log("=" * 60)
    log("🚀 13D MAX SPEED TRAINING (Best Architecture + Curriculum)")
    log("=" * 60)
    log(f"Config: lr={BEST_PARAMS['lr']}, ent={BEST_PARAMS['ent']}, arch={BEST_PARAMS['arch']}")
    log(f"Physics FPS: {PHYSICS_FPS} x {N_ENVS} envs")
    log(f"n_steps=4096, batch_size=512")
    log("=" * 60)
    
    os.environ['OMP_NUM_THREADS'] = '8'
    os.environ['MKL_NUM_THREADS'] = '8'
    
    total_start = time.time()
    
    # Start with RL
    log(f"\n📚 Stage 1: {STAGES[0][0]} on scene {STAGES[0][1]} ({STAGES[0][2]} steps)")
    env_fns = [make_env(STAGES[0][1], i) for i in range(N_ENVS)]
    env = DummyVecEnv(env_fns)

    model = PPO(
        'MlpPolicy', env,
        n_steps=4096,
        batch_size=512,
        n_epochs=3,
        learning_rate=BEST_PARAMS['lr'],
        ent_coef=BEST_PARAMS['ent'],
        policy_kwargs={'net_arch': dict(pi=BEST_PARAMS['arch'], vf=BEST_PARAMS['arch'])},
        verbose=1,
        device='cpu',
    )
    
    t0 = time.time()
    model.learn(total_timesteps=STAGES[0][2], progress_bar=False)
    log(f"   ⏱️  {STAGES[0][0]} done in {time.time()-t0:.0f}s")
    env.close()

    rate = eval_model(model, STAGES[0][1], 100, episodes=10)
    log(f"   📊 Manual Eval {STAGES[0][0]}: {rate:.0f}% success rate")
    
    # Subsequent stages
    for stage_idx, (name, path, steps) in enumerate(STAGES[1:], 1):
        log(f"\n📚 Stage {stage_idx+1}: {name} on scene {path} ({steps} steps)")
        
        env_fns = [make_env(path, stage_idx * N_ENVS + i) for i in range(N_ENVS)]
        env = DummyVecEnv(env_fns)
        model.set_env(env)
        
        t0 = time.time()
        model.learn(total_timesteps=steps, progress_bar=False)
        stage_time = time.time() - t0
        
        env.close()
        
        rate = eval_model(model, path, 200 + stage_idx, episodes=10)
        log(f"   📊 Manual Eval {name}: {rate:.0f}% success rate | {stage_time:.0f}s")
        
        model.save(f"{MODELS_DIR}/chk_13d_{name}.zip", exclude=['policy.optimizer'])
    
    # Final eval
    log("\n🎯 FINAL")
    final_rate = eval_model(model, STAGES[3][1], 300, episodes=20)
    log(f"   RL4 Final Eval: {final_rate:.0f}% success rate")
    
    model.save(f"{MODELS_DIR}/best_13d_max.zip")
    
    total = time.time() - total_start
    log(f"\n✅ Done in {total/60:.1f} min")


if __name__ == '__main__':
    try:
        main()
    finally:
        cleanup()
