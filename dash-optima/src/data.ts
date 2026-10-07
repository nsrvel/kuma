export type Priority = 'High' | 'Mid' | 'Low'

export interface Task {
  id: string
  title: string
  description: string
  image?: string
  avatars: string[]
  links: number
  comments: number
  priority: Priority
  dragging?: boolean
}

export interface Column {
  id: string
  title: string
  tasks: Task[]
}

export interface ProjectFile {
  id: string
  name: string
  size: string
  icon: 'notion' | 'drive' | 'notes' | 'ae' | 'figma' | 'mood' | 'ds'
  color: string
}

export const avatars = {
  a: 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=64&h=64&fit=crop&crop=face',
  b: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=64&h=64&fit=crop&crop=face',
  c: 'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=64&h=64&fit=crop&crop=face',
  d: 'https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?w=64&h=64&fit=crop&crop=face',
  e: 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=64&h=64&fit=crop&crop=face',
  profile: 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=64&h=64&fit=crop&crop=face',
}

export const menuItems = [
  { id: 'dashboard', label: 'Dashboard', icon: 'layout' as const },
  { id: 'tasks', label: 'Tasks', icon: 'check' as const, badge: 4 },
  { id: 'messengers', label: 'Messengers', icon: 'message' as const },
  { id: 'teams', label: 'Teams', icon: 'users' as const },
  { id: 'settings', label: 'Settings', icon: 'settings' as const },
]

export const projects = [
  { id: 'fintech', label: 'Fintech Cydex', color: '#F43F5E', badge: 5 },
  { id: 'keylen', label: 'Keylen Production', color: '#F59E0B', badge: 4 },
  { id: 'colorbox', label: 'ColorBox Assurance', color: '#8B5CF6', badge: 2 },
  {
    id: 'electrona',
    label: 'Electrona',
    color: '#84CC16',
    expanded: true,
    children: [
      { id: 'project-file', label: 'Project file', active: true },
      { id: 'roadmap', label: 'Roadmap' },
    ],
  },
  { id: 'sparck', label: 'All Sparck Shipp', color: '#06B6D4', badge: 2 },
  { id: 'architect', label: 'Architect Imanc', color: '#A855F7', badge: 2 },
  { id: 'clown', label: 'Clown ColorFun', color: '#EC4899', badge: 2 },
]

export const labels = [
  { id: 'high', label: 'High Priority', color: '#EF4444', badge: 3 },
  { id: 'mid', label: 'Mid Priority', color: '#F59E0B', badge: 4 },
  { id: 'low', label: 'Low Priority', color: '#84CC16', badge: 4 },
  { id: 'standby', label: 'On Standby', color: '#3B82F6', badge: 1 },
]

export const projectFiles: ProjectFile[] = [
  { id: '1', name: 'Briefing Team', size: '152 KB', icon: 'notion', color: '#FFFFFF' },
  { id: '2', name: 'Notes', size: '15 KB', icon: 'notes', color: '#FBBF24' },
  { id: '3', name: 'Content', size: '1.5 MB', icon: 'drive', color: '#22C55E' },
  { id: '4', name: 'Animation', size: '25 MB', icon: 'ae', color: '#A855F7' },
  { id: '5', name: 'Mood Board', size: '8.2 MB', icon: 'mood', color: '#EC4899' },
  { id: '6', name: 'Design System', size: '522 KB', icon: 'figma', color: '#A78BFA' },
  { id: '7', name: 'Wireframes', size: '210 KB', icon: 'ds', color: '#38BDF8' },
]

export const columns: Column[] = [
  {
    id: 'coming-soon',
    title: 'Coming Soon',
    tasks: [
      {
        id: 't1',
        title: 'Animation Design',
        description: 'Create character animation for hero sequence and product intro.',
        image:
          'https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?w=480&h=280&fit=crop',
        avatars: [avatars.a, avatars.b],
        links: 2,
        comments: 2,
        priority: 'High',
      },
      {
        id: 't2',
        title: 'Landing Page Design',
        description: 'Draft layout options for Electrona landing conversion flow.',
        avatars: [avatars.c, avatars.d],
        links: 5,
        comments: 5,
        priority: 'Low',
      },
    ],
  },
  {
    id: 'in-progress',
    title: 'In Progress',
    tasks: [
      {
        id: 't3',
        title: 'Landing Page Design',
        description: 'Refine responsive breakpoints and CTA hierarchy.',
        avatars: [avatars.b, avatars.e],
        links: 3,
        comments: 8,
        priority: 'Low',
      },
      {
        id: 't4',
        title: 'Animation Design',
        description: 'Polish timing curves for onboarding micro-interactions.',
        avatars: [avatars.a, avatars.c],
        links: 4,
        comments: 6,
        priority: 'High',
      },
      {
        id: 't5',
        title: 'Branding App Design',
        description: 'Align icon set and color tokens with brand guidelines.',
        avatars: [avatars.d, avatars.b],
        links: 2,
        comments: 4,
        priority: 'Mid',
      },
    ],
  },
  {
    id: 'review',
    title: 'Review',
    tasks: [
      {
        id: 't6',
        title: 'Illustration',
        description: 'Final illustration pass for campaign storyboard frames.',
        image:
          'https://images.unsplash.com/photo-1579783902614-a3fb3927b6a5?w=480&h=280&fit=crop',
        avatars: [avatars.e, avatars.a],
        links: 7,
        comments: 12,
        priority: 'High',
      },
      {
        id: 't7',
        title: 'Prototype Design',
        description: 'Clickable prototype for stakeholder walkthrough.',
        avatars: [avatars.c],
        links: 1,
        comments: 3,
        priority: 'Mid',
      },
      {
        id: 't8',
        title: 'UI Design',
        description: 'Component states for settings and notifications.',
        avatars: [avatars.b, avatars.d],
        links: 2,
        comments: 5,
        priority: 'Mid',
      },
    ],
  },
  {
    id: 'completed',
    title: 'Completed',
    tasks: [
      {
        id: 't9',
        title: 'UI / UX Design',
        description: 'Completed research synthesis and UX flow maps.',
        avatars: [avatars.a, avatars.e],
        links: 6,
        comments: 9,
        priority: 'Mid',
      },
      {
        id: 't10',
        title: 'Development',
        description: 'Core board interactions and drag-and-drop states shipped.',
        avatars: [avatars.d, avatars.c, avatars.b],
        links: 15,
        comments: 35,
        priority: 'Low',
        dragging: true,
      },
      {
        id: 't11',
        title: 'Re-Branding App Design',
        description: 'Legacy brand assets archived and new kit delivered.',
        avatars: [avatars.e],
        links: 4,
        comments: 7,
        priority: 'Mid',
      },
    ],
  },
]
