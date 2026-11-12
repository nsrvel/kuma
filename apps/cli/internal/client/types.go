package client

// DaemonStatus represents the response from daemon.status
type DaemonStatus struct {
	Version          string                 `json:"version"`
	ProtocolVersion  string                 `json:"protocolVersion"`
	UptimeSecs       uint64                 `json:"uptimeSecs"`
	DataDir          string                 `json:"dataDir"`
	RuntimeDir       string                 `json:"runtimeDir"`
	SocketPath       string                 `json:"socketPath"`
	DBPath           string                 `json:"dbPath"`
	DaemonStatePath  string                 `json:"daemonStatePath"`
	SchemaMigrations []string               `json:"schemaMigrations"`
	WorkspaceCount   int                    `json:"workspaceCount"`
	ServiceCount     int                    `json:"serviceCount"`
	RunningServices  []string               `json:"runningServices"`
	LegacyAppRunning bool                   `json:"legacyAppRunning"`
	AdoptReport      map[string]interface{} `json:"adoptReport"`
	RESTListenAddr   *string                `json:"restListenAddr"`
	InstanceID       string                 `json:"instanceId"`
}

// WorkspaceListResponse represents response from workspace.list
type WorkspaceListResponse struct {
	Workspaces []Workspace `json:"workspaces"`
}

// Workspace represents a workspace
type Workspace struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	IsDefault bool   `json:"isDefault,omitempty"`
	SortOrder int    `json:"sortOrder,omitempty"`
	HasImage  bool   `json:"hasImage,omitempty"`
}

// ServiceListResponse represents response from service.list
type ServiceListResponse struct {
	Items      []ServiceItem `json:"items"`
	TotalCount int           `json:"totalCount"`
}

// ServiceItem represents a single service returned from service.list
type ServiceItem struct {
	ID                     string      `json:"id"`
	Name                   string      `json:"name"`
	Subtitle               string      `json:"subtitle,omitempty"`
	ActiveProviderCategory string      `json:"activeProviderCategory"`
	LocalPorts             []int       `json:"localPorts"`
	IsDisabled             bool        `json:"isDisabled"`
	IsStarred              bool        `json:"isStarred"`
	Runtime                ServiceRun  `json:"runtime"`
}

// ServiceRun holds runtime info
type ServiceRun struct {
	Status      string `json:"status"`
	StatusTitle string `json:"statusTitle"`
	IsLoading   bool   `json:"isLoading"`
}

// Group represents a service group
type Group struct {
	ID          string `json:"id"`
	WorkspaceID string `json:"workspaceID"`
	Name        string `json:"name"`
	Order       int    `json:"order,omitempty"`
}

// DependencyReport represents env.dependencies output
type DependencyReport struct {
	Dependencies []DependencyItem `json:"dependencies"`
}

// DependencyItem represents a single detected dev dependency
type DependencyItem struct {
	Name      string `json:"name"`
	Installed bool   `json:"installed"`
	Version   string `json:"version,omitempty"`
	Path      string `json:"path,omitempty"`
}
