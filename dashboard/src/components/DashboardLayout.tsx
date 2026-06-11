import React, { useState, useEffect } from 'react';
import { 
  Activity, 
  Map, 
  Clock, 
  Play, 
  Menu, 
  X
} from 'lucide-react';
import { Panel, PanelGroup, PanelResizeHandle } from 'react-resizable-panels';
import { RetroTabs, RetroButton } from './retro';
import { useLayoutPersistence } from '../hooks/useLayoutPersistence';

interface DashboardLayoutProps {
  children: React.ReactNode;
  onLogout: () => void;
  peersConnected: number;
  isConnected: boolean;
  activeTab: string;
  setActiveTab: (tab: any) => void;
  playerList: React.ReactNode;
  isSessionSelected: boolean;
}

export const DashboardLayout: React.FC<DashboardLayoutProps> = ({
  children,
  onLogout,
  peersConnected,
  isConnected,
  activeTab,
  setActiveTab,
  playerList,
  isSessionSelected,
}) => {
  const { layout, updateLayout } = useLayoutPersistence();
  const [isMobile, setIsMobile] = useState(window.innerWidth < 640);
  const [isTablet, setIsTablet] = useState(window.innerWidth >= 640 && window.innerWidth < 1024);
  const [isDesktop, setIsDesktop] = useState(window.innerWidth >= 1024);
  const [showMobilePlayerList, setShowMobilePlayerList] = useState(false);

  useEffect(() => {
    const handleResize = () => {
      setIsMobile(window.innerWidth < 640);
      setIsTablet(window.innerWidth >= 640 && window.innerWidth < 1024);
      setIsDesktop(window.innerWidth >= 1024);
    };
    window.addEventListener('resize', handleResize);
    return () => window.removeEventListener('resize', handleResize);
  }, []);

  const tabs = [
    { id: 'live', label: 'Live', icon: <Activity size={16} /> },
    { id: 'heatmap', label: 'Heatmap', icon: <Map size={16} /> },
    { id: 'history', label: 'History', icon: <Clock size={16} /> },
    { id: 'playback', label: 'Playback', icon: <Play size={16} />, disabled: !isSessionSelected },
  ];

  const handleTabChange = (id: string) => {
    setActiveTab(id);
    updateLayout({ activeTab: id });
  };

  // Mobile Layout
  if (isMobile) {
    return (
      <div className="flex flex-col h-screen bg-bg-primary overflow-hidden font-mono crt-effect">
        <header className="flex items-center justify-between px-4 py-2 border-b-4 border-black bg-bg-card z-30">
          <h1 className="text-accent font-black text-xs italic tracking-tighter">ODISEA·V2</h1>
          <div className="flex items-center gap-3">
             <div className="flex items-center gap-1.5 text-[0.625rem]">
                <div className={`w-2 h-2 rounded-full ${isConnected ? 'bg-success shadow-[0_0_8px_rgba(63,185,80,0.5)]' : 'bg-danger'}`} />
                {isConnected ? 'ON' : 'OFF'}
             </div>
             <button onClick={() => setShowMobilePlayerList(true)} className="p-1 border-2 border-black bg-bg-primary">
                <Menu size={16} />
             </button>
          </div>
        </header>

        <main className="flex-1 overflow-y-auto pb-20 p-4">
          {children}
        </main>

        {showMobilePlayerList && (
            <div className="fixed inset-0 bg-black/80 z-50 flex flex-col animate-in fade-in slide-in-from-bottom duration-300">
                <div className="mt-auto bg-bg-card border-t-4 border-black p-4 max-h-[80vh] flex flex-col">
                    <div className="flex justify-between items-center mb-4 border-b-2 border-black pb-2">
                        <span className="font-black text-xs uppercase tracking-widest">Player List</span>
                        <button onClick={() => setShowMobilePlayerList(false)} className="p-1">
                            <X size={20} />
                        </button>
                    </div>
                    <div className="flex-1 overflow-y-auto" onClick={() => setShowMobilePlayerList(false)}>
                        {playerList}
                    </div>
                </div>
            </div>
        )}

        <nav className="fixed bottom-0 left-0 right-0 border-t-4 border-black bg-bg-card z-40">
           <RetroTabs 
             tabs={tabs} 
             activeTab={activeTab} 
             onTabChange={handleTabChange} 
           />
        </nav>
      </div>
    );
  }

  // Tablet/Desktop Layout
  return (
    <div className="flex flex-col h-screen bg-bg-primary overflow-hidden font-mono crt-effect">
      <header className="flex items-center px-4 py-2 border-b-4 border-black bg-bg-card z-30">
        <h1 className="text-accent font-black text-base italic tracking-tighter mr-8">ODISEA CENTRAL</h1>
        
        {!isDesktop && (
            <button 
                onClick={() => updateLayout({ sidebarCollapsed: !layout.sidebarCollapsed })}
                className="mr-4 p-1 border-2 border-black bg-bg-primary hover:bg-accent hover:text-black transition-colors"
            >
                <Menu size={18} />
            </button>
        )}

        <div className="flex-1">
            {isTablet && (
                <div className="max-w-md">
                     <RetroTabs 
                        tabs={tabs} 
                        activeTab={activeTab} 
                        onTabChange={handleTabChange} 
                    />
                </div>
            )}
        </div>

        <div className="flex items-center gap-6 text-[0.625rem] uppercase font-bold">
          <span className="flex items-center gap-2">
            <div className={`w-2.5 h-2.5 rounded-full ${isConnected ? 'bg-success shadow-[0_0_8px_rgba(63,185,80,0.5)]' : 'bg-danger'}`} />
            <span className={isConnected ? 'text-success' : 'text-danger'}>{isConnected ? 'system online' : 'system offline'}</span>
          </span>
          <span className="text-text-muted">Peers: <b className="text-text-primary">{peersConnected}</b></span>
          <RetroButton variant="secondary" onClick={onLogout} className="py-1 px-3 text-[0.625rem]">
            Log out
          </RetroButton>
        </div>
      </header>

      <div className="flex-1 overflow-hidden">
        {isDesktop ? (
          <PanelGroup direction="horizontal" onLayout={(sizes) => updateLayout({ panelSizes: sizes })}>
            <Panel 
                defaultSize={layout.panelSizes[0] || 20} 
                minSize={15} 
                className={`flex flex-col bg-bg-primary border-r-4 border-black ${layout.sidebarCollapsed ? 'hidden' : ''}`}
            >
                <div className="p-2 text-[0.625rem] uppercase text-text-muted font-black border-b-2 border-black flex justify-between items-center bg-bg-card/50">
                    <span>Active Sessions</span>
                    <button onClick={() => updateLayout({ sidebarCollapsed: true })} className="hover:text-accent">
                        <X size={12} />
                    </button>
                </div>
                <div className="flex-1 overflow-y-auto p-2">
                    {playerList}
                </div>
            </Panel>

            <PanelResizeHandle className="w-1.5 bg-black hover:bg-accent transition-colors cursor-col-resize flex items-center justify-center">
                <div className="w-0.5 h-8 bg-white/20" />
            </PanelResizeHandle>

            <Panel defaultSize={layout.panelSizes[1] || 80}>
                {children}
            </Panel>
          </PanelGroup>
        ) : (
          <div className="flex h-full">
             {!layout.sidebarCollapsed && (
                 <div className="w-64 flex flex-col bg-bg-primary border-r-4 border-black overflow-hidden animate-in slide-in-from-left duration-200">
                    <div className="p-2 text-[0.625rem] uppercase text-text-muted font-black border-b-2 border-black bg-bg-card/50">
                        Active Sessions
                    </div>
                    <div className="flex-1 overflow-y-auto p-2">
                        {playerList}
                    </div>
                 </div>
             )}
             <div className="flex-1 overflow-hidden">
                {children}
             </div>
          </div>
        )}
      </div>

      {isDesktop && (
        <nav className="border-t-4 border-black bg-bg-card">
          <div className="max-w-2xl">
            <RetroTabs 
              tabs={tabs} 
              activeTab={activeTab} 
              onTabChange={handleTabChange} 
            />
          </div>
        </nav>
      )}
    </div>
  );
};
