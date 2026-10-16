import { ChevronDown, Link2, MessageSquare, MoreHorizontal, Plus } from 'lucide-react'
import { columns, type Priority, type Task } from '../data'
import { AvatarStack } from './AvatarStack'

function priorityClass(p: Priority) {
  return p.toLowerCase()
}

function TaskCard({ task }: { task: Task }) {
  return (
    <article className={`task-card ${task.dragging ? 'dragging' : ''}`}>
      <h4>{task.title}</h4>
      <p>{task.description}</p>
      {task.image ? <img className="task-image" src={task.image} alt="" /> : null}
      <div className="task-footer">
        <AvatarStack urls={task.avatars} />
        <div className="task-stats">
          <span>
            <Link2 size={12} />
            {task.links}
          </span>
          <span>
            <MessageSquare size={12} />
            {task.comments}
          </span>
        </div>
        <span className={`priority ${priorityClass(task.priority)}`}>
          {task.priority}
        </span>
      </div>
    </article>
  )
}

export function KanbanBoard() {
  return (
    <>
      <div className="board-toolbar">
        <div className="view-switch">
          <button type="button" className="active">
            By Status
          </button>
          <button type="button">By Assigne</button>
          <button type="button">By Tasks</button>
        </div>
        <div className="board-filters">
          <button type="button" className="filter-btn">
            Filter
            <ChevronDown size={14} />
          </button>
          <button type="button" className="filter-btn">
            Sort by
            <ChevronDown size={14} />
          </button>
        </div>
      </div>

      <div className="board">
        {columns.map((column) => (
          <section key={column.id} className="column">
            <div className="column-header">
              <h3>{column.title}</h3>
              <button type="button" className="more" aria-label="Column menu">
                <MoreHorizontal size={16} />
              </button>
            </div>
            <div className="column-cards">
              {column.tasks.map((task) =>
                task.dragging ? (
                  <div key={task.id} className="drag-slot">
                    <div className="drag-placeholder" aria-hidden />
                    <TaskCard task={task} />
                  </div>
                ) : (
                  <TaskCard key={task.id} task={task} />
                ),
              )}
              {column.id === 'completed' ? (
                <button type="button" className="add-task">
                  <Plus size={14} />
                  Add Task
                </button>
              ) : null}
            </div>
          </section>
        ))}
      </div>
    </>
  )
}
