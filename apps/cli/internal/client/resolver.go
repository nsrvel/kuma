package client

import "strings"

// ResolveWorkspaceID resolves a workspace by short ID, full UUID, or name
func (c *Client) ResolveWorkspaceID(query string) (string, error) {
	query = strings.TrimSpace(query)
	if len(query) == 36 {
		return query, nil
	}

	var res WorkspaceListResponse
	if err := c.Call("workspace.list", map[string]interface{}{}, &res); err != nil {
		return query, nil
	}

	lower := strings.ToLower(query)
	for _, w := range res.Workspaces {
		if strings.HasPrefix(strings.ToLower(w.ID), lower) {
			return w.ID, nil
		}
		if strings.EqualFold(w.Name, query) {
			return w.ID, nil
		}
	}

	return query, nil
}

// GetActiveWorkspaceID returns the currently selected workspace or the first one
func (c *Client) GetActiveWorkspaceID() string {
	var val struct {
		Effective *string `json:"effective"`
		Stored    *string `json:"stored"`
		Value     *string `json:"value"`
	}
	if err := c.Call("settings.get", map[string]string{"key": "kuma.selectedWorkspaceId.storage"}, &val); err == nil {
		if val.Effective != nil && *val.Effective != "" {
			return *val.Effective
		}
		if val.Stored != nil && *val.Stored != "" {
			return *val.Stored
		}
		if val.Value != nil && *val.Value != "" {
			return *val.Value
		}
	}

	var res WorkspaceListResponse
	if err := c.Call("workspace.list", map[string]interface{}{}, &res); err == nil && len(res.Workspaces) > 0 {
		return res.Workspaces[0].ID
	}

	return ""
}

// SetActiveWorkspaceID saves the active workspace selection
func (c *Client) SetActiveWorkspaceID(id string) error {
	return c.Call("settings.set", map[string]interface{}{
		"values": map[string]interface{}{
			"kuma.selectedWorkspaceId.storage": id,
		},
	}, nil)
}

// ResolveServiceID allows using either a full UUID or an 8-character short ID or name
func (c *Client) ResolveServiceID(query string, workspaceID string) (string, error) {
	query = strings.TrimSpace(query)
	if len(query) == 36 { // Already a full UUID
		return query, nil
	}

	if workspaceID == "" {
		workspaceID = c.GetActiveWorkspaceID()
	}

	var res ServiceListResponse
	params := map[string]string{}
	if workspaceID != "" {
		params["workspaceID"] = workspaceID
	}

	if err := c.Call("service.list", params, &res); err != nil {
		return query, nil // Fallback to raw query
	}

	lowerQuery := strings.ToLower(query)
	for _, item := range res.Items {
		// Match short ID prefix
		if strings.HasPrefix(strings.ToLower(item.ID), lowerQuery) {
			return item.ID, nil
		}
		// Match exact name (case-insensitive)
		if strings.EqualFold(item.Name, query) {
			return item.ID, nil
		}
	}

	return query, nil
}
