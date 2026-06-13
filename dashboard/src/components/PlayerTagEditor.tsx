import React, { useState, useEffect } from 'react';
import { RetroCard, RetroButton, RetroInput } from './retro';
import { getPlayerTags, postPlayerTag, deletePlayerTag } from '../api';
import { X, Save, Trash2, UserPlus, Pencil } from 'lucide-react';
import { notify } from '../lib/notify';

interface PlayerTag {
  player_id: string;
  display_name: string;
  notes?: string;
  color?: string;
}

interface PlayerTagEditorProps {
  playerId?: string | null;
  onSaved?: () => void;
  onClose?: () => void;
}

export const PlayerTagEditor: React.FC<PlayerTagEditorProps> = ({ playerId, onSaved, onClose }) => {
  const [tags, setTags] = useState<PlayerTag[]>([]);
  const [editing, setEditing] = useState<Partial<PlayerTag> | null>(null);
  const [loading, setLoading] = useState(true);

  const loadTags = async () => {
    try {
      const data = await getPlayerTags();
      setTags(data);
    } catch (e) {
      notify.error("Error cargando tags");
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
      notify.error("Player ID y Nombre son requeridos");
      return;
    }
    try {
      await postPlayerTag(editing as PlayerTag);
      notify.success("Tag guardado");
      setEditing(null);
      onSaved?.();
      onClose?.();
    } catch (e) {
      notify.error("Error guardando tag");
    }
  };

  const handleDelete = async (playerId: string) => {
    if (!window.confirm(`¿Eliminar tag para ${playerId}?`)) return;
    try {
      await deletePlayerTag(playerId);
      notify.success("Tag eliminado");
      loadTags();
      onSaved?.();
      if (editing?.player_id === playerId) {
        setEditing(null);
        onClose?.();
      }
    } catch (e) {
      notify.error("Error eliminando tag");
    }
  };

  if (loading) return <div className="p-4 text-[0.625rem] uppercase font-bold text-text-muted">Cargando tags...</div>;

  return (
    <div className="flex flex-col gap-4 border-b-2 border-black bg-bg-card/95 p-3 shadow-[0_4px_0px_0px_black]">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <h3 className="text-[0.625rem] font-black uppercase tracking-widest text-accent">Player Tags</h3>
          <div className="mt-1 truncate text-[0.5625rem] text-text-muted">
            {playerId ? `Editando ${playerId}` : 'Nombres visibles, notas y color por player'}
          </div>
        </div>
        <RetroButton 
            variant="primary" 
            onClick={() => setEditing({ color: '#7fd1ff' })}
            className="shrink-0 px-2 py-1 text-[0.625rem]"
        >
          <UserPlus size={14} className="mr-1" /> Nuevo Tag
        </RetroButton>
      </div>

      <div className="grid grid-cols-1 gap-2">
        {tags.map(tag => (
          <div key={tag.player_id} className={`flex items-center justify-between gap-2 border-2 p-2 shadow-[2px_2px_0px_0px_black] ${tag.player_id === playerId ? 'border-accent bg-accent/10' : 'border-black bg-bg-primary'}`}>
            <div className="flex min-w-0 items-center gap-3">
              <div className="h-3 w-3 shrink-0 rounded-full border border-black" style={{ backgroundColor: tag.color || '#888' }} />
              <div className="min-w-0">
                <div className="truncate text-xs font-black text-text-primary">{tag.display_name}</div>
                <div className="text-[0.5625rem] text-text-muted truncate font-mono">{tag.player_id}</div>
              </div>
            </div>
            <div className="flex shrink-0 gap-1">
              <button onClick={() => setEditing(tag)} className="border-2 border-black bg-bg-card p-1 hover:bg-accent hover:text-black" title="Editar tag"><Pencil size={14} /></button>
              <button onClick={() => handleDelete(tag.player_id)} className="border-2 border-black bg-bg-card p-1 hover:bg-danger hover:text-black" title="Eliminar tag"><Trash2 size={14} /></button>
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
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4 backdrop-blur-sm">
          <RetroCard title={editing.player_id ? "Editar Tag" : "Nuevo Tag"} className="w-full max-w-md">
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
                <RetroButton variant="primary" onClick={handleSave} className="flex flex-1 items-center justify-center gap-2">
                  <Save size={16} /> Guardar
                </RetroButton>
                <RetroButton variant="secondary" onClick={() => { setEditing(null); onClose?.(); }}><X size={16} /></RetroButton>
              </div>
            </div>
          </RetroCard>
        </div>
      )}
    </div>
  );
};
