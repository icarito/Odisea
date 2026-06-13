import React, { useState, useEffect } from 'react';
import { RetroCard, RetroButton, RetroInput } from './retro';
import { getPlayerTags, postPlayerTag, deletePlayerTag } from '../api';
import { X, Save, Trash2, UserPlus } from 'lucide-react';
import { toast } from 'react-hot-toast';

interface PlayerTag {
  player_id: string;
  display_name: string;
  notes?: string;
  color?: string;
}

interface PlayerTagEditorProps {
  playerId?: string | null;
  onSaved?: () => void;
}

export const PlayerTagEditor: React.FC<PlayerTagEditorProps> = ({ playerId, onSaved }) => {
  const [tags, setTags] = useState<PlayerTag[]>([]);
  const [editing, setEditing] = useState<Partial<PlayerTag> | null>(null);
  const [loading, setLoading] = useState(true);

  const loadTags = async () => {
    try {
      const data = await getPlayerTags();
      setTags(data);
    } catch (e) {
      toast.error("Error cargando tags");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadTags();
  }, []);

  useEffect(() => {
    if (!playerId || loading || editing) return;
    const existing = tags.find((tag) => tag.player_id === playerId);
    setEditing(existing || { player_id: playerId, color: '#7fd1ff' });
  }, [playerId, loading, tags, editing]);

  const handleSave = async () => {
    if (!editing?.player_id || !editing?.display_name) {
      toast.error("Player ID y Nombre son requeridos");
      return;
    }
    try {
      await postPlayerTag(editing as PlayerTag);
      toast.success("Tag guardado");
      setEditing(null);
      loadTags();
      onSaved?.();
    } catch (e) {
      toast.error("Error guardando tag");
    }
  };

  const handleDelete = async (playerId: string) => {
    if (!window.confirm(`¿Eliminar tag para ${playerId}?`)) return;
    try {
      await deletePlayerTag(playerId);
      toast.success("Tag eliminado");
      loadTags();
    } catch (e) {
      toast.error("Error eliminando tag");
    }
  };

  if (loading) return <div className="p-4 text-[0.625rem] uppercase font-bold text-text-muted">Cargando tags...</div>;

  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-center justify-between">
        <h3 className="text-[0.625rem] font-black uppercase tracking-widest text-accent">Player Tags</h3>
        <RetroButton 
            variant="primary" 
            onClick={() => setEditing({ color: '#7fd1ff' })}
            className="py-1 px-2 text-[0.625rem]"
        >
          <UserPlus size={14} className="mr-1" /> Nuevo Tag
        </RetroButton>
      </div>

      <div className="grid grid-cols-1 gap-2">
        {tags.map(tag => (
          <div key={tag.player_id} className="border-2 border-black bg-bg-card p-2 flex items-center justify-between shadow-[2px_2px_0px_0px_black]">
            <div className="flex items-center gap-3">
              <div className="w-3 h-3 rounded-full" style={{ backgroundColor: tag.color || '#888' }} />
              <div className="min-w-0">
                <div className="text-xs font-black text-text-primary">{tag.display_name}</div>
                <div className="text-[0.5625rem] text-text-muted truncate font-mono">{tag.player_id}</div>
              </div>
            </div>
            <div className="flex gap-1">
              <button onClick={() => setEditing(tag)} className="p-1 hover:text-accent"><Save size={14} /></button>
              <button onClick={() => handleDelete(tag.player_id)} className="p-1 hover:text-danger"><Trash2 size={14} /></button>
            </div>
          </div>
        ))}
        {tags.length === 0 && !editing && (
          <div className="text-center py-4 border-2 border-dashed border-black text-[0.625rem] text-text-muted uppercase">
            No hay tags definidos
          </div>
        )}
      </div>

      {editing && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4">
          <RetroCard title={editing.player_id ? "Editar Tag" : "Nuevo Tag"} className="w-full max-w-sm">
            <div className="flex flex-col gap-3">
              <div>
                <label className="text-[0.5625rem] font-bold uppercase text-text-muted mb-1 block">Player ID</label>
                <RetroInput 
                  value={editing.player_id || ''} 
                  onChange={e => setEditing({...editing, player_id: e.target.value})} 
                  disabled={!!editing.player_id && tags.some(t => t.player_id === editing.player_id)}
                  placeholder="12345678-12345..."
                />
              </div>
              <div>
                <label className="text-[0.5625rem] font-bold uppercase text-text-muted mb-1 block">Nombre Visible</label>
                <RetroInput 
                  value={editing.display_name || ''} 
                  onChange={e => setEditing({...editing, display_name: e.target.value})} 
                  placeholder="Ej: Tester Pro"
                />
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div>
                    <label className="text-[0.5625rem] font-bold uppercase text-text-muted mb-1 block">Color</label>
                    <input 
                        type="color" 
                        value={editing.color || '#7fd1ff'} 
                        onChange={e => setEditing({...editing, color: e.target.value})}
                        className="w-full h-8 border-2 border-black bg-bg-primary cursor-pointer"
                    />
                </div>
              </div>
              <div>
                <label className="text-[0.5625rem] font-bold uppercase text-text-muted mb-1 block">Notas</label>
                <textarea 
                  value={editing.notes || ''} 
                  onChange={e => setEditing({...editing, notes: e.target.value})}
                  className="w-full h-16 border-2 border-black bg-bg-primary p-1.5 text-xs font-mono text-text-primary"
                />
              </div>
              <div className="flex gap-2 mt-2">
                <RetroButton variant="primary" onClick={handleSave} className="flex-1">Guardar</RetroButton>
                <RetroButton variant="secondary" onClick={() => setEditing(null)}><X size={16} /></RetroButton>
              </div>
            </div>
          </RetroCard>
        </div>
      )}
    </div>
  );
};
