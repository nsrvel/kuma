import { Share2, Plus, MoreHorizontal } from 'lucide-react'
import { avatars, projectFiles } from '../data'
import { AvatarStack } from './AvatarStack'

function FileIcon({ icon, color }: { icon: string; color: string }) {
  if (icon === 'notion') {
    return (
      <div className="file-icon" style={{ background: '#111', border: '1px solid #333' }}>
        <svg width="16" height="16" viewBox="0 0 24 24" fill="#fff">
          <path d="M4 4.5A1.5 1.5 0 0 1 5.5 3h11.2c.5 0 1 .25 1.25.68l2.5 4.2c.2.35.2.78 0 1.13l-8.7 13.5A1.5 1.5 0 0 1 10.5 23H5.5A1.5 1.5 0 0 1 4 21.5v-17Z" />
        </svg>
      </div>
    )
  }
  if (icon === 'figma') {
    return (
      <div className="file-icon" style={{ background: '#1a1a1a', border: '1px solid #333' }}>
        <svg width="14" height="18" viewBox="0 0 38 57" fill="none">
          <path d="M19 28.5a9.5 9.5 0 1 1 19 0 9.5 9.5 0 0 1-19 0Z" fill="#1ABCFE" />
          <path d="M0 47.5A9.5 9.5 0 0 1 9.5 38H19v9.5A9.5 9.5 0 1 1 0 47.5Z" fill="#0ACF83" />
          <path d="M19 0v19h9.5a9.5 9.5 0 1 0 0-19H19Z" fill="#FF7262" />
          <path d="M0 9.5A9.5 9.5 0 0 0 9.5 19H19V0H9.5A9.5 9.5 0 0 0 0 9.5Z" fill="#F24E1E" />
          <path d="M0 28.5A9.5 9.5 0 0 0 9.5 38H19V19H9.5A9.5 9.5 0 0 0 0 28.5Z" fill="#A259FF" />
        </svg>
      </div>
    )
  }
  const labels: Record<string, string> = {
    notes: 'N',
    drive: 'D',
    ae: 'Ae',
    mood: '◈',
    ds: '◆',
  }
  return (
    <div className="file-icon" style={{ background: color }}>
      {labels[icon] ?? '•'}
    </div>
  )
}

function FlowerIcon() {
  return (
    <svg className="project-flower" viewBox="0 0 28 28" fill="currentColor" aria-hidden>
      <circle cx="14" cy="6" r="3.2" />
      <circle cx="22" cy="14" r="3.2" />
      <circle cx="14" cy="22" r="3.2" />
      <circle cx="6" cy="14" r="3.2" />
      <circle cx="14" cy="14" r="2.2" opacity="0.85" />
    </svg>
  )
}

export function ProjectHeader() {
  return (
    <>
      <div className="breadcrumbs">
        <span>…</span>
        <span className="sep">/</span>
        <span>Project</span>
        <span className="sep">/</span>
        <span>Electrona</span>
        <span className="sep">/</span>
        <span className="current">Project file</span>
      </div>

      <div className="project-title-row">
        <FlowerIcon />
        <h1>Electrona</h1>
        <div className="project-meta">
          <span className="pill mid">Mid</span>
          <span className="pill time">2 week left</span>
        </div>
      </div>

      <div className="files-row">
        <div className="files-left">
          <div className="files-header">
            <span>Project files</span>
            <span className="badge">7</span>
          </div>
          <div className="files-scroller">
            {projectFiles.map((file) => (
              <div key={file.id} className="file-card">
                <FileIcon icon={file.icon} color={file.color} />
                <div className="file-meta">
                  <div className="name">{file.name}</div>
                  <div className="size">{file.size}</div>
                </div>
              </div>
            ))}
          </div>
        </div>

        <div className="files-actions">
          <AvatarStack
            urls={[avatars.a, avatars.b, avatars.c, avatars.d]}
            more={5}
          />
          <button type="button" className="icon-btn" aria-label="Add member">
            <Plus size={16} />
          </button>
          <button type="button" className="btn btn-share">
            <Share2 size={14} />
            Share
          </button>
          <button type="button" className="btn btn-primary">
            Add Project
          </button>
          <button type="button" className="icon-btn" aria-label="More">
            <MoreHorizontal size={16} />
          </button>
        </div>
      </div>
    </>
  )
}
