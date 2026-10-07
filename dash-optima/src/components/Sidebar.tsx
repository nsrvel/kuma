import {
  LayoutDashboard,
  ListTodo,
  MessageSquare,
  Users,
  Settings,
  ChevronDown,
  ChevronLeft,
  ChevronRight,
  PanelLeft,
} from 'lucide-react'
import { labels, menuItems, projects } from '../data'

const menuIcons = {
  layout: LayoutDashboard,
  check: ListTodo,
  message: MessageSquare,
  users: Users,
  settings: Settings,
}

function ProjectGlyph({ color }: { color: string }) {
  return (
    <span className="project-icon" style={{ background: `${color}22` }}>
      <svg viewBox="0 0 12 12" fill={color}>
        <circle cx="3" cy="3" r="2" />
        <circle cx="9" cy="3" r="2" />
        <circle cx="3" cy="9" r="2" />
        <circle cx="9" cy="9" r="2" />
      </svg>
    </span>
  )
}

export function Sidebar() {
  return (
    <aside className="sidebar">
      <div className="sidebar-chrome">
        <div className="traffic">
          <span className="dot red" />
          <span className="dot yellow" />
          <span className="dot green" />
        </div>
        <PanelLeft size={14} />
        <div className="nav-arrows">
          <span>
            <ChevronLeft size={14} />
          </span>
          <span>
            <ChevronRight size={14} />
          </span>
        </div>
      </div>

      <div className="brand">
        <div className="brand-mark" aria-hidden>
          <span />
          <span />
          <span />
          <span />
        </div>
        <span className="brand-name">Dash Optima</span>
      </div>

      <div className="section-label">
        <span>Menu</span>
        <ChevronDown size={12} className="chev" />
      </div>
      <ul className="nav-list">
        {menuItems.map((item) => {
          const Icon = menuIcons[item.icon]
          return (
            <li key={item.id}>
              <button type="button" className="nav-item">
                <Icon className="icon" strokeWidth={1.75} />
                <span>{item.label}</span>
                {item.badge != null ? (
                  <span className="badge danger">{item.badge}</span>
                ) : null}
              </button>
            </li>
          )
        })}
      </ul>

      <div className="section-label" style={{ marginTop: 10 }}>
        <span>Projects</span>
        <ChevronDown size={12} className="chev" />
      </div>
      <ul className="nav-list">
        {projects.map((project) => (
          <li key={project.id}>
            <button
              type="button"
              className={`nav-item ${'expanded' in project && project.expanded ? 'expanded project-item' : 'project-item'}`}
            >
              <ProjectGlyph color={project.color} />
              <span>{project.label}</span>
              {'badge' in project && project.badge != null ? (
                <span className="badge danger">{project.badge}</span>
              ) : null}
            </button>
            {'children' in project && project.children ? (
              <ul className="project-children">
                {project.children.map((child) => (
                  <li key={child.id}>
                    <button
                      type="button"
                      className={`project-child ${child.active ? 'active' : ''}`}
                    >
                      {child.label}
                    </button>
                  </li>
                ))}
              </ul>
            ) : null}
          </li>
        ))}
      </ul>

      <div className="section-label" style={{ marginTop: 10 }}>
        <span>Labels</span>
        <ChevronDown size={12} className="chev" />
      </div>
      <ul className="nav-list">
        {labels.map((label) => (
          <li key={label.id}>
            <button type="button" className="nav-item">
              <span className="label-dot" style={{ background: label.color }} />
              <span>{label.label}</span>
              <span className="badge">{label.badge}</span>
            </button>
          </li>
        ))}
      </ul>

      <div className="sidebar-spacer" />
    </aside>
  )
}
