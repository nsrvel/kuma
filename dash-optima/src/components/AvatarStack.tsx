interface AvatarStackProps {
  urls: string[]
  more?: number
  size?: 'sm' | 'md'
}

export function AvatarStack({ urls, more }: AvatarStackProps) {
  return (
    <div className="avatar-stack">
      {urls.map((url, i) => (
        <img key={`${url}-${i}`} src={url} alt="" />
      ))}
      {more != null && more > 0 ? <span className="more">+{more}</span> : null}
    </div>
  )
}
