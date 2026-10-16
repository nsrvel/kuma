import { Sidebar } from './components/Sidebar'
import { TopBar } from './components/TopBar'
import { ProjectHeader } from './components/ProjectHeader'
import { KanbanBoard } from './components/KanbanBoard'

export default function App() {
  return (
    <div className="app">
      <Sidebar />
      <div className="main">
        <TopBar />
        <div className="content">
          <ProjectHeader />
          <KanbanBoard />
        </div>
      </div>
    </div>
  )
}
