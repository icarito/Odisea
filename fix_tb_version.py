import os

def fix_config(filepath):
    if os.path.exists(filepath):
        with open(filepath, 'r') as f:
            data = f.read()
        
        data = data.replace('version: 3,', '"version": 9,')
        
        with open(filepath, 'w') as f:
            f.write(data)
        print(f"Fixed {filepath}")
    else:
        print(f"{filepath} not found")

home = os.path.expanduser('~')
fix_config(os.path.join(home, '.TrenchBroom', 'games', 'Odisea', 'GameConfig.cfg'))
fix_config(os.path.join(home, '.TrenchBroom', 'games', 'Odisea', 'Odisea', 'GameConfig.cfg'))
