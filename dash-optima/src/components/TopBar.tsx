import { Search, Sun, Moon, ChevronDown } from 'lucide-react'
import { avatars } from '../data'

const tabs = ['Board', 'Calendar', 'Plans', 'Activity', 'Report']

export function TopBar() {
  return (
    <header className="topbar">
      <nav className="top-tabs" aria-label="Primary">
        {tabs.map((tab) => (
          <button
            key={tab}
            type="button"
            className={`top-tab ${tab === 'Board' ? 'active' : ''}`}
          >
            {tab}
          </button>
        ))}
      </nav>

      <div className="topbar-right">
        <label className="search">
          <Search size={15} strokeWidth={1.75} />
          <input type="search" placeholder="Search" />
        </label>

        <div className="theme-toggle" aria-label="Theme">
          <button type="button">
            <Sun size={14} />
          </button>
          <button type="button" className="active">
            <Moon size={14} />
          </button>
        </div>

        <button type="button" className="profile">
          <img src={avatars.profile} alt="" />
          <span className="profile-name">Draguzen</span>
          <ChevronDown size={14} color="#71717a" />
        </button>
      </div>
    </header>
  )
}
