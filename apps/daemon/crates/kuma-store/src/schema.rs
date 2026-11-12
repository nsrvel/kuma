//! Expected `sqlite_master` rows after v1..v8 ([01 §3.5.1](docs/specs/daemon/01-data-model.md)).

pub const KNOWN_MIGRATION_IDENTIFIERS: [&str; 8] = [
    "v1_production_schema",
    "v2_service_groups",
    "v3_service_group_memberships",
    "v4_provider_custom_kubeconfig",
    "v5_port_mapping_provider",
    "v6_provider_compose_and_script_paths",
    "v7_kube_config_source_path",
    "v8_provider_auto_reconnect",
];

/// User-visible schema objects in creation order (type, name, tbl_name, sql).
pub const EXPECTED_SQLITE_MASTER: [(&str, &str, &str, Option<&str>); 14] = [
    (
        "table",
        "grdb_migrations",
        "grdb_migrations",
        Some("CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY)"),
    ),
    (
        "table",
        "workspace",
        "workspace",
        Some(
            r#"CREATE TABLE "workspace" ("id" TEXT PRIMARY KEY, "name" TEXT NOT NULL, "imagePath" TEXT, "sortOrder" INTEGER NOT NULL DEFAULT 0, "createdAt" DATETIME NOT NULL, "updatedAt" DATETIME NOT NULL)"#,
        ),
    ),
    (
        "table",
        "kube_config",
        "kube_config",
        Some(
            r#"CREATE TABLE "kube_config" ("id" TEXT PRIMARY KEY, "name" TEXT NOT NULL, "configContent" TEXT NOT NULL, "createdAt" DATETIME NOT NULL, "updatedAt" DATETIME NOT NULL, "sourceFilePath" TEXT)"#,
        ),
    ),
    (
        "table",
        "service",
        "service",
        Some(
            r#"CREATE TABLE "service" ("id" TEXT PRIMARY KEY, "workspaceID" TEXT NOT NULL REFERENCES "workspace"("id") ON DELETE CASCADE, "name" TEXT NOT NULL, "icon" TEXT, "colorHex" TEXT, "description" TEXT, "activeProviderID" TEXT, "isDisabled" BOOLEAN NOT NULL DEFAULT 0, "isStarred" BOOLEAN NOT NULL DEFAULT 0, "createdAt" DATETIME NOT NULL, "updatedAt" DATETIME NOT NULL, "groupID" TEXT REFERENCES "service_group"("id") ON DELETE SET NULL)"#,
        ),
    ),
    (
        "table",
        "provider",
        "provider",
        Some(
            r#"CREATE TABLE "provider" ("id" TEXT PRIMARY KEY, "serviceID" TEXT NOT NULL REFERENCES "service"("id") ON DELETE CASCADE, "type" TEXT NOT NULL, "label" TEXT, "kubeConfigID" TEXT, "kubeContext" TEXT, "kubeNamespace" TEXT, "targetName" TEXT, "kubeTargetType" TEXT, "usePattern" BOOLEAN, "yamlConfig" TEXT, "initialScript" TEXT, "runCommand" TEXT, "workingDirectory" TEXT, "sshHost" TEXT, "sshUser" TEXT, "sshPort" INTEGER, "sshKeyPath" TEXT, "sshPassword" TEXT, "httpCheckUrl" TEXT, "httpCheckInterval" INTEGER, "tunnelType" TEXT, "tunnelTargetUrl" TEXT, "ngrokAuthToken" TEXT, "monitorProcessName" TEXT, "monitorInterval" INTEGER, "createdAt" DATETIME NOT NULL, "updatedAt" DATETIME NOT NULL, "customKubeConfigPath" TEXT, "composeFilePath" TEXT, "initialScriptPath" TEXT, "autoReconnect" BOOLEAN NOT NULL DEFAULT 0)"#,
        ),
    ),
    (
        "table",
        "portMapping",
        "portMapping",
        Some(
            r#"CREATE TABLE "portMapping" ("id" TEXT PRIMARY KEY, "serviceID" TEXT NOT NULL REFERENCES "service"("id") ON DELETE CASCADE, "localPort" INTEGER NOT NULL, "remotePort" INTEGER NOT NULL, "protocolType" TEXT NOT NULL DEFAULT 'TCP', "providerID" TEXT REFERENCES "provider"("id") ON DELETE CASCADE)"#,
        ),
    ),
    (
        "index",
        "idx_service_workspace",
        "service",
        Some(r#"CREATE INDEX "idx_service_workspace" ON "service"("workspaceID", "createdAt")"#),
    ),
    (
        "index",
        "idx_provider_service",
        "provider",
        Some(r#"CREATE INDEX "idx_provider_service" ON "provider"("serviceID")"#),
    ),
    (
        "index",
        "idx_port_service",
        "portMapping",
        Some(r#"CREATE INDEX "idx_port_service" ON "portMapping"("serviceID")"#),
    ),
    (
        "table",
        "service_group",
        "service_group",
        Some(
            r#"CREATE TABLE "service_group" ("id" TEXT PRIMARY KEY, "workspaceID" TEXT NOT NULL REFERENCES "workspace"("id") ON DELETE CASCADE, "name" TEXT NOT NULL, "sortOrder" INTEGER NOT NULL DEFAULT 0, "createdAt" DATETIME NOT NULL, "updatedAt" DATETIME NOT NULL)"#,
        ),
    ),
    (
        "index",
        "idx_group_workspace",
        "service_group",
        Some(
            r#"CREATE INDEX "idx_group_workspace" ON "service_group"("workspaceID", "sortOrder")"#,
        ),
    ),
    (
        "table",
        "service_group_membership",
        "service_group_membership",
        Some(
            r#"CREATE TABLE "service_group_membership" ("serviceID" TEXT NOT NULL REFERENCES "service"("id") ON DELETE CASCADE, "groupID" TEXT NOT NULL REFERENCES "service_group"("id") ON DELETE CASCADE, "createdAt" DATETIME NOT NULL, PRIMARY KEY ("serviceID", "groupID"))"#,
        ),
    ),
    (
        "index",
        "idx_membership_group",
        "service_group_membership",
        Some(
            r#"CREATE INDEX "idx_membership_group" ON "service_group_membership"("groupID", "serviceID")"#,
        ),
    ),
    (
        "index",
        "idx_port_provider",
        "portMapping",
        Some(r#"CREATE INDEX "idx_port_provider" ON "portMapping"("providerID")"#),
    ),
];
