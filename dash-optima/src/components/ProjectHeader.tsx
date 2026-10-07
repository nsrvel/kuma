import { Share2, Plus, MoreHorizontal } from 'lucide-react'
import { avatars, projectFiles } from '../data'
import { AvatarStack } from './AvatarStack'

function FileIcon({ icon, color }: { icon: string; color: string }) {
  const labels: Record<string, string> = {
    notion: 'N',
    notes: '✎',
    drive: 'D',
    ae: 'Ae',
    mood: 'M',
    figma: 'F',
    ds: '◆',
  }
  return (
    <div className="file-icon" style={{ background: color === '#FFFFFF' ? '#111' : color, color: color === '#FFFFFF' ? '#fff' : '#fff', border: color === '#FFFFFF' ? '1px solid #333' : undefined }}>
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
