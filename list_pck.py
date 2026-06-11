#!/usr/bin/env python3
import struct
import sys

def list_pck_contents(pck_path):
    with open(pck_path, 'rb') as f:
        # Read magic
        magic = f.read(4)
        if magic != b'GDPC':
            print(f"Error: Not a valid Godot PCK file (magic: {magic})")
            return
        
        # Read version
        version = struct.unpack('<I', f.read(4))[0]
        
        # Read file count
        file_count = struct.unpack('<I', f.read(4))[0]
        print(f"PCK Version: {version}")
        print(f"Total files: {file_count}\n")
        
        files = []
        total_size = 0
        
        for _ in range(file_count):
            path_len = struct.unpack('<I', f.read(4))[0]
            path = f.read(path_len).decode('utf-8')
            offset = struct.unpack('<Q', f.read(8))[0]
            size = struct.unpack('<Q', f.read(8))[0]
            md5 = f.read(16)
            
            files.append((path, size))
            total_size += size
            
        # Sort by path for readability
        files.sort(key=lambda x: x[0])
        
        for path, size in files:
            size_kb = size / 1024
            print(f"{size_kb:>8.1f} KB | {path}")
            
        print(f"\nTotal unpacked size: {total_size / (1024*1024):.2f} MB")

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python3 list_pck.py <path_to_pck>")
    else:
        list_pck_contents(sys.argv[1])
