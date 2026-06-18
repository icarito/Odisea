import React from 'react';
import { SceneHealthCard } from './SceneHealthCard';

interface ScenesIndexProps {
  scenes: any[];
  onSelectScene: (id: string) => void;
}

export const ScenesIndex: React.FC<ScenesIndexProps> = ({ scenes, onSelectScene }) => {
  return (
    <div className="grid grid-cols-1 gap-4 p-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
      {scenes.map(scene => (
        <SceneHealthCard 
          key={scene.scene_id} 
          scene={scene} 
          onClick={() => onSelectScene(scene.scene_id)} 
        />
      ))}
    </div>
  );
};
