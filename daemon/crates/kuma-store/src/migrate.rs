use crate::schema::KNOWN_MIGRATION_IDENTIFIERS;
use crate::seed::{default_workspace_name, new_uppercase_uuid, now_grdb_datetime};
use kuma_domain::StoreError;
use rusqlite::{Connection, OptionalExtension};
use std::collections::HashSet;

pub fn read_applied_identifiers(conn: &Connection) -> Result<Vec<String>, StoreError> {
    let exists: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='grdb_migrations'",
            [],
            |r| r.get(0),
        )
        .map_err(|e| StoreError::DbOpenFailed {
            detail: e.to_string(),
        })?;
    if exists == 0 {
        return Ok(Vec::new());
    }
    let mut stmt = conn
        .prepare("SELECT identifier FROM grdb_migrations ORDER BY rowid")
        .map_err(|e| StoreError::DbOpenFailed {
            detail: e.to_string(),
        })?;
    let ids = stmt
        .query_map([], |r| r.get(0))
        .map_err(|e| StoreError::DbOpenFailed {
            detail: e.to_string(),
        })?
        .collect::<Result<Vec<String>, _>>()
        .map_err(|e| StoreError::DbOpenFailed {
            detail: e.to_string(),
        })?;
    Ok(ids)
}

pub fn ensure_grdb_migrations_table(conn: &Connection) -> Result<(), StoreError> {
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY)",
    )
    .map_err(|e| StoreError::DbOpenFailed {
        detail: e.to_string(),
    })
}

pub fn refuse_unknown_identifiers(applied: &[String]) -> Result<(), StoreError> {
    let known: HashSet<&str> = KNOWN_MIGRATION_IDENTIFIERS.iter().copied().collect();
    for id in applied {
        if !known.contains(id.as_str()) {
            return Err(StoreError::SchemaTooNew {
                identifier: id.clone(),
            });
        }
    }
    Ok(())
}

pub fn pending_migrations(applied: &[String]) -> Vec<&'static str> {
    let applied: HashSet<&str> = applied.iter().map(String::as_str).collect();
    KNOWN_MIGRATION_IDENTIFIERS
        .iter()
        .copied()
        .filter(|id| !applied.contains(id))
        .collect()
}

pub fn apply_all_pending(conn: &Connection) -> Result<(), StoreError> {
    ensure_grdb_migrations_table(conn)?;
    let applied = read_applied_identifiers(conn)?;
    refuse_unknown_identifiers(&applied)?;
    for id in pending_migrations(&applied) {
        apply_one(conn, id)?;
    }
    Ok(())
}

/// Apply migrations through index `through` inclusive (0 = v1 only).
pub fn apply_through(conn: &Connection, through: usize) -> Result<(), StoreError> {
    ensure_grdb_migrations_table(conn)?;
    let applied = read_applied_identifiers(conn)?;
    refuse_unknown_identifiers(&applied)?;
    for (idx, id) in KNOWN_MIGRATION_IDENTIFIERS.iter().enumerate() {
        if idx > through {
            break;
        }
        if !applied.contains(&id.to_string()) {
            apply_one(conn, id)?;
        }
    }
    Ok(())
}

fn apply_one(conn: &Connection, identifier: &str) -> Result<(), StoreError> {
    conn.execute_batch("PRAGMA foreign_keys = OFF")
        .map_err(|e| StoreError::MigrationFailed {
            identifier: identifier.into(),
            detail: e.to_string(),
        })?;
    let body = || -> Result<(), rusqlite::Error> {
        match identifier {
            "v1_production_schema" => migrate_v1(conn),
            "v2_service_groups" => migrate_v2(conn),
            "v3_service_group_memberships" => migrate_v3(conn),
            "v4_provider_custom_kubeconfig" => migrate_v4(conn),
            "v5_port_mapping_provider" => migrate_v5(conn),
            "v6_provider_compose_and_script_paths" => migrate_v6(conn),
            "v7_kube_config_source_path" => migrate_v7(conn),
            "v8_provider_auto_reconnect" => migrate_v8(conn),
            _ => Err(rusqlite::Error::InvalidParameterName(identifier.into())),
        }
    };
    conn.execute("BEGIN IMMEDIATE", [])
        .map_err(|e| StoreError::MigrationFailed {
            identifier: identifier.into(),
            detail: e.to_string(),
        })?;
    let result = (|| {
        body()?;
        foreign_key_check(conn)?;
        conn.execute(
            "INSERT INTO grdb_migrations (identifier) VALUES (?1)",
            [identifier],
        )?;
        Ok::<(), rusqlite::Error>(())
    })();
    match result {
        Ok(()) => {
            conn.execute("COMMIT", []).map_err(|e| StoreError::MigrationFailed {
                identifier: identifier.into(),
                detail: e.to_string(),
            })?;
        }
        Err(e) => {
            let _ = conn.execute("ROLLBACK", []);
            return Err(StoreError::MigrationFailed {
                identifier: identifier.into(),
                detail: e.to_string(),
            });
        }
    }
    conn.execute_batch("PRAGMA foreign_keys = ON")
        .map_err(|e| StoreError::MigrationFailed {
            identifier: identifier.into(),
            detail: e.to_string(),
        })?;
    Ok(())
}

fn foreign_key_check(conn: &Connection) -> Result<(), rusqlite::Error> {
    let mut stmt = conn.prepare("PRAGMA foreign_key_check")?;
    let violations: Vec<String> = stmt
        .query_map([], |row| {
            let table: String = row.get(0)?;
            Ok(table)
        })?
        .collect::<Result<Vec<_>, _>>()?;
    if violations.is_empty() {
        Ok(())
    } else {
        Err(rusqlite::Error::SqliteFailure(
            rusqlite::ffi::Error::new(rusqlite::ffi::SQLITE_CONSTRAINT),
            Some(format!("foreign_key_check: {violations:?}")),
        ))
    }
}

fn migrate_v1(conn: &Connection) -> Result<(), rusqlite::Error> {
    conn.execute_batch(
        r#"
CREATE TABLE "workspace" ("id" TEXT PRIMARY KEY, "name" TEXT NOT NULL, "imagePath" TEXT, "sortOrder" INTEGER NOT NULL DEFAULT 0, "createdAt" DATETIME NOT NULL, "updatedAt" DATETIME NOT NULL);
CREATE TABLE "kube_config" ("id" TEXT PRIMARY KEY, "name" TEXT NOT NULL, "configContent" TEXT NOT NULL, "createdAt" DATETIME NOT NULL, "updatedAt" DATETIME NOT NULL);
CREATE TABLE "service" ("id" TEXT PRIMARY KEY, "workspaceID" TEXT NOT NULL REFERENCES "workspace"("id") ON DELETE CASCADE, "name" TEXT NOT NULL, "icon" TEXT, "colorHex" TEXT, "description" TEXT, "activeProviderID" TEXT, "isDisabled" BOOLEAN NOT NULL DEFAULT 0, "isStarred" BOOLEAN NOT NULL DEFAULT 0, "createdAt" DATETIME NOT NULL, "updatedAt" DATETIME NOT NULL);
CREATE TABLE "provider" ("id" TEXT PRIMARY KEY, "serviceID" TEXT NOT NULL REFERENCES "service"("id") ON DELETE CASCADE, "type" TEXT NOT NULL, "label" TEXT, "kubeConfigID" TEXT, "kubeContext" TEXT, "kubeNamespace" TEXT, "targetName" TEXT, "kubeTargetType" TEXT, "usePattern" BOOLEAN, "yamlConfig" TEXT, "initialScript" TEXT, "runCommand" TEXT, "workingDirectory" TEXT, "sshHost" TEXT, "sshUser" TEXT, "sshPort" INTEGER, "sshKeyPath" TEXT, "sshPassword" TEXT, "httpCheckUrl" TEXT, "httpCheckInterval" INTEGER, "tunnelType" TEXT, "tunnelTargetUrl" TEXT, "ngrokAuthToken" TEXT, "monitorProcessName" TEXT, "monitorInterval" INTEGER, "createdAt" DATETIME NOT NULL, "updatedAt" DATETIME NOT NULL);
CREATE TABLE "portMapping" ("id" TEXT PRIMARY KEY, "serviceID" TEXT NOT NULL REFERENCES "service"("id") ON DELETE CASCADE, "localPort" INTEGER NOT NULL, "remotePort" INTEGER NOT NULL, "protocolType" TEXT NOT NULL DEFAULT 'TCP');
CREATE INDEX "idx_service_workspace" ON "service"("workspaceID", "createdAt");
CREATE INDEX "idx_provider_service" ON "provider"("serviceID");
CREATE INDEX "idx_port_service" ON "portMapping"("serviceID");
"#,
    )?;
    let now = now_grdb_datetime();
    let id = new_uppercase_uuid();
    let name = default_workspace_name();
    conn.execute(
        "INSERT INTO workspace (id, name, imagePath, sortOrder, createdAt, updatedAt) VALUES (?1, ?2, NULL, 0, ?3, ?4)",
        rusqlite::params![id, name, now, now],
    )?;
    Ok(())
}

fn migrate_v2(conn: &Connection) -> Result<(), rusqlite::Error> {
    conn.execute_batch(
        r#"
CREATE TABLE "service_group" ("id" TEXT PRIMARY KEY, "workspaceID" TEXT NOT NULL REFERENCES "workspace"("id") ON DELETE CASCADE, "name" TEXT NOT NULL, "sortOrder" INTEGER NOT NULL DEFAULT 0, "createdAt" DATETIME NOT NULL, "updatedAt" DATETIME NOT NULL);
ALTER TABLE "service" ADD COLUMN "groupID" TEXT REFERENCES "service_group"("id") ON DELETE SET NULL;
CREATE INDEX "idx_group_workspace" ON "service_group"("workspaceID", "sortOrder");
"#,
    )
}

fn migrate_v3(conn: &Connection) -> Result<(), rusqlite::Error> {
    conn.execute_batch(
        r#"
CREATE TABLE "service_group_membership" ("serviceID" TEXT NOT NULL REFERENCES "service"("id") ON DELETE CASCADE, "groupID" TEXT NOT NULL REFERENCES "service_group"("id") ON DELETE CASCADE, "createdAt" DATETIME NOT NULL, PRIMARY KEY ("serviceID", "groupID"));
INSERT OR IGNORE INTO service_group_membership (serviceID, groupID, createdAt)
    SELECT id, groupID, datetime('now')
    FROM service
    WHERE groupID IS NOT NULL AND groupID != '';
CREATE INDEX "idx_membership_group" ON "service_group_membership"("groupID", "serviceID");
"#,
    )
}

fn migrate_v4(conn: &Connection) -> Result<(), rusqlite::Error> {
    conn.execute_batch(r#"ALTER TABLE "provider" ADD COLUMN "customKubeConfigPath" TEXT;"#)
}

fn migrate_v5(conn: &Connection) -> Result<(), rusqlite::Error> {
    conn.execute_batch(
        r#"ALTER TABLE "portMapping" ADD COLUMN "providerID" TEXT REFERENCES "provider"("id") ON DELETE CASCADE;"#,
    )?;
    let mut stmt = conn.prepare("SELECT id, serviceID FROM portMapping WHERE providerID IS NULL")?;
    let rows: Vec<(String, String)> = stmt
        .query_map([], |r| Ok((r.get(0)?, r.get(1)?)))?
        .collect::<Result<Vec<_>, _>>()?;
    for (port_id, service_id) in rows {
        let provider_id: Option<String> = conn
            .query_row(
                "SELECT COALESCE(
                    (SELECT activeProviderID FROM service WHERE id = ?1),
                    (SELECT id FROM provider WHERE serviceID = ?2 ORDER BY createdAt ASC LIMIT 1)
                )",
                rusqlite::params![service_id, service_id],
                |r| r.get(0),
            )
            .optional()?
            .flatten();
        if let Some(pid) = provider_id {
            conn.execute(
                "UPDATE portMapping SET providerID = ?1 WHERE id = ?2",
                rusqlite::params![pid, port_id],
            )?;
        }
    }
    conn.execute_batch(r#"CREATE INDEX "idx_port_provider" ON "portMapping"("providerID");"#)
}

fn migrate_v6(conn: &Connection) -> Result<(), rusqlite::Error> {
    conn.execute_batch(
        r#"
ALTER TABLE "provider" ADD COLUMN "composeFilePath" TEXT;
ALTER TABLE "provider" ADD COLUMN "initialScriptPath" TEXT;
"#,
    )
}

fn migrate_v7(conn: &Connection) -> Result<(), rusqlite::Error> {
    conn.execute_batch(r#"ALTER TABLE "kube_config" ADD COLUMN "sourceFilePath" TEXT;"#)
}

fn migrate_v8(conn: &Connection) -> Result<(), rusqlite::Error> {
    conn.execute_batch(
        r#"ALTER TABLE "provider" ADD COLUMN "autoReconnect" BOOLEAN NOT NULL DEFAULT 0;"#,
    )
}

pub fn ensure_default_workspace_if_empty(conn: &Connection) -> Result<(), StoreError> {
    let count: i64 = conn
        .query_row("SELECT COUNT(*) FROM workspace", [], |r| r.get(0))
        .map_err(|e| StoreError::DbOpenFailed {
            detail: e.to_string(),
        })?;
    if count > 0 {
        return Ok(());
    }
    let now = now_grdb_datetime();
    let id = new_uppercase_uuid();
    let name = default_workspace_name();
    conn.execute(
        "INSERT INTO workspace (id, name, imagePath, sortOrder, createdAt, updatedAt) VALUES (?1, ?2, NULL, 0, ?3, ?4)",
        rusqlite::params![id, name, now, now],
    )
    .map_err(|e| StoreError::DbOpenFailed {
        detail: e.to_string(),
    })?;
    Ok(())
}
