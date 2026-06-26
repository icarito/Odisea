import { useState } from 'react';
import { Link, NavLink, Outlet } from 'react-router-dom';
import { LoginScreen } from '../components/LoginScreen';

// Shell retro-limpio para la IA incident-first. Sin crt-effect ni animaciones:
// header sobrio + nav + contenido. Comparte el gate de auth del dashboard
// clásico (token en localStorage `odisea_token`).
//
// Por ahora la única sección portada es Inbox; Investigate / Heatmap / Globe
// siguen viviendo en el dashboard clásico (link "Clásico") hasta que se porten.
export function IncidentShell() {
  const [token, setToken] = useState<string | null>(() => localStorage.getItem('odisea_token'));

  if (!token) {
    return (
      <LoginScreen
        onLogin={(t) => {
          localStorage.setItem('odisea_token', t);
          setToken(t);
        }}
      />
    );
  }

  const logout = () => {
    localStorage.removeItem('odisea_token');
    setToken(null);
  };

  return (
    <div className="flex h-screen flex-col overflow-hidden bg-bg-primary font-mono text-text-primary">
      <header className="flex shrink-0 items-center justify-between border-b-4 border-black bg-bg-card px-4 py-2">
        <div className="flex items-center gap-3">
          <h1 className="text-sm font-black italic tracking-tighter text-accent sm:text-base">
            ODISEA <span className="not-italic text-text-muted">CENTRAL</span>
          </h1>
          <span className="hidden h-4 w-px bg-black/20 sm:block" />
          <span className="text-[0.625rem] font-black uppercase tracking-widest text-text-muted">
            Incidentes
          </span>
        </div>
        <div className="flex items-center gap-2">
          <Link
            to="/"
            className="border-2 border-black bg-bg-primary px-2 py-1 text-[0.625rem] font-black uppercase text-text-muted transition-colors hover:bg-accent hover:text-black"
            title="Dashboard clásico"
          >
            Clásico
          </Link>
          <button
            onClick={logout}
            className="border-2 border-black bg-bg-primary px-2 py-1 text-[0.625rem] font-black uppercase transition-colors hover:bg-danger hover:text-black"
            title="Cerrar sesión"
          >
            Salir
          </button>
        </div>
      </header>

      <nav className="flex shrink-0 border-b-2 border-black bg-bg-card">
        <NavLink
          to="/investigate"
          className={({ isActive }) =>
            `border-r-2 border-black px-4 py-2 text-[0.6875rem] font-black uppercase tracking-widest transition-colors ${
              isActive ? 'bg-accent text-black' : 'bg-bg-primary text-text-muted hover:text-accent'
            }`
          }
        >
          Investigate
        </NavLink>
      </nav>

      <main className="min-h-0 flex-1 overflow-y-auto">
        <Outlet />
      </main>
    </div>
  );
}
