# Daemon Spec 02: Security and Secrets

> **Status:** Draft for implementation  
> **Area code:** `SEC`  
> **Baseline:** Kuma 1.x (Swift). Conventions, ID schemes and the RPC name registry are in [00](00-overview-and-conventions.md). Data model in [01](01-data-model.md), providers in [05](05-providers-and-validation.md), execution in [06](06-execution-engine.md), kubeconfig in [07](07-kubernetes.md), logs in [08](08-logs-and-events.md), DataPort in [09](09-dataport.md), wire protocol in [10](10-rpc-protocol.md), REST in [13](13-rest-api.md), MCP in [12](12-mcp.md).

---

## 1. Purpose and scope

This spec defines everything the daemon does to protect credentials and to restrict who may talk to it:

1. **Vault (PARITY, wire-compatible):** AES-256-GCM encryption with a 32-byte master key file, byte-compatible with 1.x so a Rust daemon can read a 1.x `kuma.sqlite` and 1.x backups, and 1.x can read what the daemon writes.
2. **Field-level encryption inventory (PARITY):** every secret-bearing field, where it is encrypted and decrypted, legacy-plaintext fallback, empty-string rules, fail-closed writes.
3. **Temporary secret artifacts (PARITY + hardening):** SSH askpass script, materialized kubeconfig, validation temp kubeconfig, with permission and cleanup guarantees.
4. **Transport security ([V2-ADD]):** Unix socket permissions and peer-credential check, REST loopback/bearer-token/Host/Origin rules, MCP bridge restrictions, audit log.
5. **Secret masking and reveal contract ([V2-ADD]):** what RPC responses may contain, and the central redaction function (GR-04).
6. **Platform facts:** sandbox/entitlements state of 1.x and what it implies for the daemon.
7. **Threat model.**

Out of scope: the shape of non-secret fields (see 01, 05), the command lines of runners (06), the JSON-RPC framing (10).

---

## 2. 1.x source of truth

Files read in full (paths relative to repo root). Line references in section 3 point into these.

| Path | Relevance |
|------|-----------|
| `Kuma/Core/Security/CryptoVault.swift` | AES-256-GCM vault, master key file, error enum |
| `Kuma/Core/Security/CredentialProtector.swift` | Fail-closed encryption entry point (`encryptForStorage`) |
| `Kuma/Core/Database/Records/Provider+Record.swift` | Provider row decode (decrypt + legacy fallback), encode (encrypt) |
| `Kuma/Core/Database/Records/KubeConfig+Record.swift` | Kubeconfig row mapping (no crypto here) |
| `Kuma/Domain/Models/KubeConfig.swift` | `defaultID`, `resolvedPlainYAML()` |
| `Kuma/Core/Database/Repositories/DataPortRepository+Mapping.swift` | `toExportProvider`, `fromExportProvider`, `importKubeConfigs`, `collectReferencedKubeConfigIDs` |
| `Kuma/Core/Database/Repositories/DataPortRepository+Export.swift` | Export of providers and kubeconfig ciphertext |
| `Kuma/Core/Database/Repositories/DataPortRepository+Import.swift` (166-215, 66-67) | Import re-save of providers |
| `Kuma/Core/DataPort/DataPortService+BackupModels.swift` | `ExportProvider`, `ExportKubeConfig` JSON shapes |
| `Kuma/Core/DataPort/DataPortService+ImportExport.swift` (64-90) | Backup JSON encoder/decoder settings |
| `Kuma/Core/DataPort/DataPortService+FactoryReset.swift` | Factory reset (what is and is not deleted) |
| `Kuma/Core/Kubernetes/KubeConfigMaterializer.swift` | Materialized kubeconfig path/perms |
| `Kuma/Core/Kubernetes/KubeConfigExecutionResolver.swift` | Second decrypt site (`loadYAML`) |
| `Kuma/Core/Kubernetes/KubeConnectionValidator.swift` | Validation temp kubeconfig |
| `Kuma/Core/Execution/Runners/SSHTunnelRunner.swift` | Askpass script, `vault:` prefix quirks |
| `Kuma/Core/Execution/Runners/TunnelRunner.swift` | ngrok `--authtoken` argv |
| `Kuma/Core/Execution/Runners/ContainerRunner.swift` (309-324), `Compose/ComposeStackResolver.swift` | Compose failure text, ephemeral compose file |
| `Kuma/Core/Execution/ServiceExecutionEngine.swift` (5-33, 78-148) | Error descriptions, stop paths |
| `Kuma/Core/Execution/Supervision/RunSpool.swift`, `ExecutionSupervisor.swift` (440-516) | Spool file mode, poller log lines |
| `Kuma/Core/Execution/ProcessRegistry.swift` (90-130) | Environment merge when spawning |
| `Kuma/Core/Database/AppDatabase.swift` (1-75) | Data dir creation (default attributes), DB wipe |
| `Kuma/Core/Configuration/ServiceConfigurationValidator.swift` (225-290) | Secret required-field messages |
| `Kuma/Presentation/Features/Services/ViewModels/KubeConfigViewModel.swift` | Kubeconfig encryption on save, decryption for display |
| `Kuma/Presentation/Features/Services/Views/CreateService/Components/CreateServicePayloadBuilder.swift` (14-75), `Models/ProviderSSHAuth.swift` | Empty/trim rules on write |
| `Kuma/Kuma.entitlements`, `Kuma.xcodeproj/project.pbxproj` (251, 314, 337-392), `Scripts/mac-sign-app.sh` | Sandbox/hardened runtime facts |
| `SECURITY.md`, `docs/specs/00-app.md` (INV-APP-05), `docs/testing/00-app-test-matrix.md` | Documented intent |
| `KumaTests/Features/App/CryptoVaultTests.swift`, `KumaTests/Features/DataPort/DataPortValidationAndSecurityTests.swift`, `KumaTests/Features/Services/ServicesValidationAndSecurityTests.swift` (TC-B01, B02, B02b, B04, B04d, B06, B06b), `KumaTests/Features/DataPort/DataPortPersistenceAndSyncTests.swift` (C20, C21), `KumaTests/Features/Services/RunnersExecutionTests.swift` (TC-R07) | Implicit requirements |

Not present in 1.x: any Keychain use (grep `Keychain|SecItem` over `Kuma/` returns nothing), any network listener, any redaction of log text, any audit log. See DEV-09 in [00](00-overview-and-conventions.md) (secrets use `master.key`, not Keychain; the text in `docs/specs/07-kuma-daemon.md` lines 18, 128, 151 is superseded).

---

## 3. Normative behavior

### 3.1 Constants

| Name | Value | Source |
|------|-------|--------|
| Cipher | AES-256-GCM, no AAD, no KDF | `CryptoVault.swift:94-106` (`AES.GCM.seal(data, using: key)`) |
| Master key length | 32 bytes (raw, no header, no encoding) | `CryptoVault.swift:69` |
| Nonce length | 12 bytes, random per encryption | CryptoKit default nonce |
| Tag length | 16 bytes | CryptoKit default tag |
| Key file name | `master.key` in the data dir | `CryptoVault.swift:63` |
| Data dir default | `~/Library/Application Support/Kuma` (override `KUMA_DATA_DIR`) | `CryptoVault.swift:50-56`, [00](00-overview-and-conventions.md) |
| Data dir mode (when 1.x creates it via vault) | `0700` | `CryptoVault.swift:58-60` |
| Key file mode | `0600` | `CryptoVault.swift:84` |
| Ciphertext string | `<nonceB64>:<tagB64>:<ciphertextB64>` | `CryptoVault.swift:99-106` |
| Base64 variant | Standard alphabet (RFC 4648 section 4) with `=` padding, no line breaks | `Data.base64EncodedString()` default |
| Ciphertext split | split on `:`, empty subsequences kept, exactly 3 parts | `CryptoVault.swift:111-118` |
| Whitespace trim before split | `.whitespacesAndNewlines` on the whole string | `CryptoVault.swift:111` |
| Materialized kubeconfig dir | `<data dir>/kubeconfigs`, mode `0700` | `KubeConfigMaterializer.swift:58-75` |
| Materialized kubeconfig file | `<data dir>/kubeconfigs/<UUID UPPERCASE>.yaml`, mode `0600` | `KubeConfigMaterializer.swift:50-55, 75` |
| Askpass dir (1.x) | `$TMPDIR/kuma-ssh-<serviceID UPPERCASE>` | `SSHTunnelRunner.swift:124` |
| Askpass file | `askpass.sh`, mode `0700` | `SSHTunnelRunner.swift:127, 140` |
| Askpass env | `SSH_ASKPASS=<script path>`, `SSH_ASKPASS_REQUIRE=force`, `DISPLAY=kuma:0` | `SSHTunnelRunner.swift:62-66` |
| ssh auth args (password mode) | `-o PreferredAuthentications=password,keyboard-interactive`, `-o PubkeyAuthentication=no`, `-o NumberOfPasswordPrompts=1` | `SSHTunnelRunner.swift:68-71` |
| Validation temp file | `<NSTemporaryDirectory>/kuma-chk-<random UUID>.yaml` | `KubeConnectionValidator.swift:64-66` |
| Redaction mark | `***` | this spec (ADD-33) |
| API token file | `<data dir>/api-token`, mode `0600` | this spec (ADD-31) |
| API token entropy | 32 random bytes, encoded as 64 lowercase hex chars | this spec (ADD-31, ADD-08) |
| Audit log file | `<data dir>/audit.log`, mode `0600`, JSON Lines | this spec (ADD-34) |

### 3.2 CryptoVault (exact)

#### 3.2.1 `getOrCreateMasterKey()` (`CryptoVault.swift:43-88`)

Algorithm in 1.x:

1. If the in-memory cache holds a key, return it (no disk access).
2. Resolve `<data dir>`. If it does not exist, create it with intermediate directories and mode `0700`. (If it exists, its mode is NOT touched. In practice `AppDatabase.init` creates the same directory first with default attributes, `AppDatabase.swift:23`, so in 1.x installs the data dir is usually `0755`; see DEV-36.)
3. If `<data dir>/master.key` exists: read all bytes (a read error propagates as a raw Foundation error; it is **not** wrapped in `CryptoVaultError.fileAccessError`, which is declared but never thrown, `CryptoVault.swift:10, 21`). If length is exactly 32, cache and return. Any other length (including 0) logs a warning "Existing master key file corrupted (length != 32 bytes). Generating a replacement." and falls through.
4. Generate 32 random bytes, write them with the atomic option (temp file then rename), then `chmod 0600`, cache and return.

Normative daemon behavior:

- The daemon MUST implement steps 1-4 with identical on-disk results: raw 32 bytes, file name `master.key`, no trailing newline, no encoding.
- Wrong-length rule (parity): a key file whose length is not 32 MUST be replaced by a fresh key. **All ciphertext produced under the old key becomes undecryptable.** Hardening (DEV-36c): before replacing, the daemon renames the bad file to `master.key.corrupt-<unixMs>` (mode `0600`) so an operator can recover; a WARN is logged and an audit entry `vault.key_replaced` is written.
- Missing file: generate (parity). WARN-level log `vault.key_created` and audit entry `vault.key_created`. The daemon MUST NOT refuse to start.
- Key read errors other than "not found" (permission denied, I/O error, path is a directory) MUST NOT trigger regeneration (parity: 1.x throws). They surface as `KUMA_SEC_KEY_FILE_ACCESS` with message `File access error for master key: <OS error text>`.
- Creation MUST be serialized inside the process (one mutex around the whole get-or-create; 1.x only locked the cache, so two first callers could both generate and the loser's ciphertext would be orphaned). Creation MUST also be race-safe against the 1.x app or another daemon: write the new key to a temp file in the data dir created with mode `0600` (`O_CREAT|O_EXCL`), `fsync`, then publish with `link(temp, master.key)` (fails with `EEXIST` if someone else won); on `EEXIST` re-read `master.key` and use it; always unlink the temp file. For the wrong-length replacement use `rename` (overwrite) after the backup step. (DEV-36c.)
- Cache: the key is cached for the process lifetime and never re-read. If `master.key` changes on disk while the daemon runs, the daemon keeps using the cached key until restart (parity).
- Memory: the key SHOULD be held in a zeroizing container and MUST NOT be logged, serialized, or included in any RPC/event/error. Core dumps SHOULD be disabled at daemon start (`setrlimit(RLIMIT_CORE, 0)`) (ADD-30).
- Factory reset does NOT delete `master.key` (1.x: `DataPortService+FactoryReset.swift` removes defaults, DB rows and images only). The daemon keeps this (earlier backups remain importable on the same machine).

#### 3.2.2 `encrypt(plainText)` (`CryptoVault.swift:94-106`)

1. UTF-8 encode the string (Swift: failure -> `invalidUTF8`; unreachable for valid strings, so Rust `&str` never fails).
2. Obtain the key (3.2.1). Key-file errors propagate as in 3.2.1.
3. Draw a fresh random 12-byte nonce from the OS CSPRNG. A nonce MUST NOT be reused with the same key.
4. AES-256-GCM seal, no associated data. Output: ciphertext (same length as plaintext) and 16-byte tag, kept separate.
5. Return `base64(nonce) + ":" + base64(tag) + ":" + base64(ciphertext)`.

The empty string encrypts to a valid payload with an empty third component, e.g. `oKGio6Slpqeoqaqr:XGmWJa9Lk6D4IgoqYRnF0A==:` (trailing colon, nothing after). This is how 1.x stores "no inline content" for file-backed kubeconfigs (`KubeConfigViewModel.swift:239`, test TC-B04d).

Encryption is non-deterministic: two encryptions of the same text differ. Nothing may compare ciphertexts for equality.

#### 3.2.3 `decrypt(cipherText)` (`CryptoVault.swift:110-134`)

1. Trim leading/trailing whitespace and newlines of the whole input.
2. Split on `:` keeping empty parts. If the part count is not 3 -> `invalidPayloadFormat`.
3. Base64-decode part 0 (nonce) and part 1 (tag). If either fails to decode -> `invalidPayloadFormat`. Part 2 (ciphertext): if it is empty it is the empty byte string, otherwise base64-decode; decode failure -> `invalidPayloadFormat`.
4. Obtain the key (3.2.1). Note this step can **create** a new key if `master.key` is missing.
5. Build the GCM nonce from part 0, then the sealed box from nonce, ciphertext, tag, then open. Any failure in this block (nonce length not accepted, tag length not accepted, authentication failure) is caught by a catch-all and mapped to `payloadCorrupted`.
6. The opened bytes MUST decode as UTF-8; otherwise `invalidUTF8` (this error is rethrown unchanged, not mapped to `payloadCorrupted`).

Daemon rules:

- Nonce MUST be exactly 12 bytes and tag exactly 16 bytes; any other size -> `payloadCorrupted` (1.x only ever produces 12/16; see Open questions).
- Base64 decoding: standard alphabet, padded. The daemon MUST accept every string 1.x emits. It MUST reject characters outside the alphabet (including internal whitespace). Unpadded input is accepted (superset; Open questions).
- An empty nonce or tag part (e.g. `:x:`) is an empty byte string after decoding and therefore fails at step 5 with `payloadCorrupted`, **not** `invalidPayloadFormat`. Only a wrong part count or an undecodable non-empty part yields `invalidPayloadFormat`.
- Decryption MUST be constant-time with respect to the tag comparison (use the AEAD library's `open`).

#### 3.2.4 Error enum and messages

| 1.x case | Raised when | `errorDescription` (exact) | Daemon code |
|----------|-------------|----------------------------|-------------|
| `invalidUTF8` | opened bytes are not UTF-8 (decrypt); encode failure (encrypt, unreachable) | `The data could not be encoded or decoded as UTF-8.` | `KUMA_SEC_INVALID_UTF8` |
| `invalidPayloadFormat` | wrong part count or undecodable base64 | `The encrypted payload format is invalid (expected nonce:tag:ciphertext).` | `KUMA_SEC_INVALID_PAYLOAD` |
| `payloadCorrupted` | nonce/tag size rejected, or authentication failed | `The encrypted payload is corrupted or authentication tag verification failed.` | `KUMA_SEC_PAYLOAD_CORRUPTED` |
| `fileAccessError(msg)` | declared in 1.x but never thrown | `File access error for master key: <msg>` | `KUMA_SEC_KEY_FILE_ACCESS` (the daemon DOES use it, for key-file I/O errors) |

#### 3.2.5 Thread-safety

1.x guards only the cached key with an unfair lock; encrypt/decrypt are otherwise stateless and callable concurrently from sync (GRDB record encode/decode) and async contexts. The daemon: key cache behind a `Mutex`/`OnceLock`; encrypt/decrypt MUST be callable concurrently from any task or blocking thread; creation serialized per 3.2.1.

#### 3.2.6 Wire-compatibility test vectors (procedure)

The goal: prove the Rust vault reads what 1.x wrote and 1.x can read what Rust writes. The format has no version byte, so compatibility is fully determined by: raw 32-byte key, 12-byte nonce, 16-byte tag, no AAD, standard padded base64, `:` separators.

**A. Deterministic known-answer vectors (no 1.x install needed).** The Rust crate MUST expose a test-only entry `encrypt_with_nonce(key, nonce, plaintext)` (cfg(test) or a feature flag; production `encrypt` always draws a random nonce). Fixed inputs:

- Key (32 bytes): `000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f`
- Nonce (12 bytes): `a0a1a2a3a4a5a6a7a8a9aaab` (base64 `oKGio6Slpqeoqaqr`)

| Plaintext (UTF-8) | Expected payload |
|-------------------|------------------|
| `kuma_test_data` | `oKGio6Slpqeoqaqr:aSlm+ME6/z3+vc54fWZPHg==:jW0RTBq/Z8wWOuOycxs=` |
| `` (empty) | `oKGio6Slpqeoqaqr:XGmWJa9Lk6D4IgoqYRnF0A==:` |
| `p@ss:wörd` | `oKGio6Slpqeoqaqr:hg/3i/XXrP1NwCqoumpYjQ==:llgPXn+8wQkQAQ==` |

These were produced by an independent standard AES-256-GCM implementation (12-byte nonce, 16-byte tag, empty AAD); any conforming implementation yields the same bytes, and CryptoKit `AES.GCM.seal(_, using:)` with an explicit nonce is the same primitive.

Pseudo-steps for the test (no external tools):

1. Load the fixed key as the in-memory master key (bypass the file).
2. For each row: `assert encrypt_with_nonce(key, nonce, plaintext) == expected`.
3. For each row: `assert decrypt(expected) == plaintext`.
4. Negative: flip one bit of the tag part (decode, XOR, re-encode) -> `decrypt` returns `KUMA_SEC_PAYLOAD_CORRUPTED`.
5. Negative: `decrypt("not_a_valid_payload")` and `decrypt("part1:part2")` -> `KUMA_SEC_INVALID_PAYLOAD`.
6. Negative: replace the ciphertext part with `YWJjZGVmZ2hpams=` (10 bytes) while keeping nonce and tag -> `KUMA_SEC_PAYLOAD_CORRUPTED` (1.x TC-E06).
7. Leading/trailing whitespace: `decrypt("  \n" + expected + "\t ")` succeeds.
8. Part count: `decrypt(expected + ":extra")` -> `KUMA_SEC_INVALID_PAYLOAD`.
9. `decrypt(":x:")`-style empty nonce -> `KUMA_SEC_PAYLOAD_CORRUPTED`.
10. Round trip: `encrypt("super_secret_ssh_token_12345!@#$%")` then `decrypt` equals input; two encryptions of the same text differ; the output has exactly 3 colon-separated parts, nonce part decodes to 12 bytes, tag part to 16 bytes.

**B. Real 1.x capture (acceptance gate, needs a Mac with 1.x).**

1. With 1.x, create an SSH service with password `kuma_test_data` and a pasted kubeconfig `apiVersion: v1\nkind: Config\n`.
2. Copy `~/Library/Application Support/Kuma/master.key` (exactly 32 bytes) and `kuma.sqlite` (with `-wal` checkpointed) into a fixture dir.
3. Rust test: point `KUMA_DATA_DIR` at the fixture; read `provider.sshPassword` raw (has two colons, three parts) and `kube_config.configContent`; `decrypt` both; assert plaintexts match. Also run a 1.x data export of that service and decrypt `providers[].sshPassword` and `kubeConfigs[].encryptedConfigContent`.
4. Reverse direction: with Rust, encrypt `kuma_test_data` using the fixture key and store it in the `provider.sshPassword` column of a copy of the DB; open that copy in 1.x (key file copied back) and verify the SSH service shows a password and starts. Expected: 1.x decrypts it.
5. The fixture MUST be generated on a throwaway key; never commit a real `master.key`.

### 3.3 Secret-bearing field inventory

Legend: **E** = encrypt site, **D** = decrypt site. "Stored form" is the content of the SQLite column in `kuma.sqlite` (schema byte-compatible, [01](01-data-model.md)).

| # | Field | Stored form | E (1.x) | D (1.x) | Daemon rule |
|---|-------|-------------|---------|---------|-------------|
| 1 | `provider.sshPassword` (`provider` table, column `sshPassword`) | vault ciphertext, or NULL | `Provider+Record.swift:127-131` (`encode`, via `CredentialProtector.encryptForStorage`) | `Provider+Record.swift:39-47` (`init(row:)`), then `SSHTunnelRunner.swift:50-56` | Encrypt in the repository write path for every insert/update (create, update, duplicate, import). Decrypt in repository read path. See 3.4, 3.5. |
| 2 | `provider.ngrokAuthToken` (column `ngrokAuthToken`) | vault ciphertext, or NULL | `Provider+Record.swift:139-143` | `Provider+Record.swift:52-60`, then `TunnelRunner.swift:76-81` | Same as 1. |
| 3 | `kube_config.configContent` | vault ciphertext (never NULL; `encrypt("")` for file-backed) | `KubeConfigViewModel.swift:239` (file mode `encrypt("")`), `:244` (paste mode `encrypt(trimmedYAML)`). **The repository/record layer does not encrypt** (`KubeConfig+Record.swift:29-35` writes `configContent` verbatim). | `KubeConfigViewModel.swift:119` (display), `KubeConfigMaterializer.swift:43` (kubectl), `KubeConfigExecutionResolver.swift:62` (context resolution) | The daemon moves encryption into the kubeconfig write path (`kubeconfig.create`/`kubeconfig.update`): callers send plaintext, the daemon stores ciphertext. Decrypt only inside the daemon. |
| 4 | Backup `providers[].sshPassword` | vault ciphertext (freshly encrypted, new nonce) | `DataPortRepository+Mapping.swift:44-48, 79` (`toExportProvider`) | `DataPortRepository+Mapping.swift:92-97` (`fromExportProvider`) then re-encrypted by 1 on save | Export re-encrypts plaintext (not byte-stable between exports). Import decrypts with legacy fallback (3.5) and the provider write re-encrypts under the local key. |
| 5 | Backup `providers[].ngrokAuthToken` | vault ciphertext | `Mapping.swift:50-54, 84` | `Mapping.swift:99-104` | Same as 4. |
| 6 | Backup `kubeConfigs[].encryptedConfigContent` | the DB ciphertext copied verbatim | `DataPortRepository+Export.swift:255` (no decrypt/re-encrypt) | `Mapping.swift:12-39` (`importKubeConfigs`): stored verbatim into `kube_config.configContent` | Verbatim pass-through (parity). Not portable across machines with different `master.key` (see 3.5, DEV-37). |
| 7 | Backup `kubeConfigs[].path` | plain path string (= `sourceFilePath`) | `Export.swift:254` | `Mapping.swift:13, 21` | Not a secret but sensitive (reveals home dir layout). Exported as-is. |
| 8 | `provider.sshKeyPath` | plain path string, or a `vault:`-prefixed string | never written by 1.x code | `SSHTunnelRunner.swift:72-80` | See 3.6 (quirk). Path only; the private key file itself is never read, copied or stored by Kuma (`ssh -i <path>`). |
| 9 | `master.key` | raw 32 bytes file | `CryptoVault.swift:79-84` | `CryptoVault.swift:66-72` | 3.2.1 |
| 10 | API token (new) | `<data dir>/api-token` | ADD-31 | ADD-31 | 3.9.2 |
| 11 | In-memory decrypted values (provider read results, kubeconfig plaintext) | process memory | - | - | MUST NOT be logged; added to the redaction known-value set (3.12.3). |

**Plaintext-by-design fields that can still carry secrets** (never encrypted by 1.x, present verbatim in `kuma.sqlite` and in every backup JSON):

| Field | Why it can hold a secret |
|-------|--------------------------|
| `provider.yamlConfig` (compose YAML) | `environment:` blocks, `.env` style passwords, registry credentials |
| `provider.initialScript`, `provider.runCommand` | inline tokens, `export` statements, `-p <password>` style flags |
| `provider.httpCheckUrl`, `provider.tunnelTargetUrl` | URL userinfo (`https://user:pw@host`), `?token=` query |
| `provider.sshUser`, `provider.sshHost` | identity disclosure only |
| `provider.customKubeConfigPath`, `kube_config.sourceFilePath`, `provider.sshKeyPath`, `provider.composeFilePath`, `provider.workingDirectory` | file-system layout |
| `service.description`, names | user-typed free text |

Normative: the daemon MUST NOT silently start encrypting these (would break 1.x read compatibility and byte-compatible backups). It MUST apply the strict redaction profile (3.12) whenever it echoes any of them into logs, events, error messages or the `runtime_process` table. Clients (CLI/REST docs) SHOULD tell users that backup JSON contains these fields in plaintext. The CLI `data.export` human output SHOULD print a one-line stderr notice; the daemon returns no extra field for it.

### 3.4 Write rules, empty strings and fail-closed

**Empty-string -> nil rules (parity)**

| Where | Rule | Source |
|-------|------|--------|
| Record encode (provider write) | `sshPassword` / `ngrokAuthToken`: if value is `nil` **or empty string** -> column set to NULL; otherwise encrypt. A whitespace-only value is NOT empty here and is encrypted as is. | `Provider+Record.swift:127-143` |
| Record decode (provider read) | If raw column is NULL **or empty string** -> `nil`; otherwise decrypt with legacy fallback (3.5). | `Provider+Record.swift:39-60` |
| Create-service payload | password / key path / ngrok token are trimmed (`.whitespacesAndNewlines`) and omitted (nil) when empty (password only when auth type is password; key path only when key; ngrok token only when engine is ngrok). | `CreateServicePayloadBuilder.swift:20-37` |
| Inspector commit | `ngrokAuthToken` empty -> nil; `sshPassword` binding writes the raw string (empty allowed; becomes NULL at encode). | `InspectorRemoteAndNetworkFormSections.swift:54-56, 88-90` |
| SSH auth switch | switching to key auth sets `sshPassword = nil`; switching to password auth sets `sshKeyPath = nil`; persistence normalizes the same way. | `ProviderSSHAuth.swift:11-32` |
| Runner use | password and token are trimmed again at use time; a trimmed-empty password means "no password" (falls through to the key branch); a trimmed-empty token means "no `--authtoken` arg". | `SSHTunnelRunner.swift:50-58`, `TunnelRunner.swift:76-81` |
| Validator | `ssh.password` "SSH password is required." (password mode, trimmed empty); `tunnel.ngrok_token` "Ngrok auth token is required." (ngrok engine, trimmed empty). | `ServiceConfigurationValidator.swift:236-240, 275-279` |
| Kubeconfig save | file mode: path trimmed, must be non-empty and the expanded path must exist, otherwise the save is silently a no-op; stored ciphertext is `encrypt("")`, `sourceFilePath` = the trimmed **unexpanded** path. Paste mode: content trimmed, must be non-empty, stored ciphertext `encrypt(trimmed)`, `sourceFilePath` = NULL. | `KubeConfigViewModel.swift:231-245` |
| Kubeconfig import | cipher and path both trimmed; **if both empty the row is skipped**; empty cipher stored as `""` (empty string, not NULL); empty path stored as NULL; row id equal to the Default id is skipped; missing name -> `Imported`; missing dates -> now. Upsert on id (`ON CONFLICT(id) DO UPDATE` of name, configContent, sourceFilePath, updatedAt; `createdAt` of an existing row is kept). | `Mapping.swift:9-40` |

**Daemon wire rules for write calls (`provider.add`, `provider.update`, `kubeconfig.create`, `kubeconfig.update`)** (ADD-32):

| Param state | Meaning for `sshPassword` / `ngrokAuthToken` |
|-------------|-----------------------------------------------|
| key absent | keep the stored value unchanged (clients holding only masked data must not wipe secrets) |
| `null` or `""` | clear (column NULL) |
| non-empty string | encrypt and replace |

For kubeconfig: `configContent` absent and `sourceFilePath` absent on update -> keep both stored columns; `configContent` non-empty -> store `encrypt(trimmed)` and set `sourceFilePath` NULL; `sourceFilePath` non-empty -> store `encrypt("")` and `sourceFilePath` = trimmed raw path. Providing both is rejected by the kubeconfig spec ([07](07-kubernetes.md)); this spec only fixes the stored form.

**Fail-closed writes (parity, INV-D-SEC-04):** `CredentialProtector.encryptForStorage` (`CredentialProtector.swift:5-7`) is a thin wrapper over `CryptoVault.encrypt` and has no fallback. If encryption throws (for example the key file is unreadable), the exception propagates out of `Provider.encode` and the whole GRDB write fails; nothing is persisted, and plaintext is never written. The daemon MUST: (a) encrypt before opening/while inside the write transaction so that a failure rolls back the entire RPC mutation (e.g. `service.create` with its provider, `data.import`), (b) return the vault error code from 3.2.4, (c) never store plaintext as a fallback, (d) leave existing rows untouched. This also applies to export: `toExportProvider` throws and the export fails rather than emitting plaintext.

### 3.5 Read rules and legacy plaintext fallback

1.x read semantics (`Provider+Record.swift:43, 56`; `Mapping.swift:94, 101`):

```
value = try? decrypt(raw)  ??  raw        // any failure -> the raw column text is used as the secret
```

This exists so a database written by a pre-vault build (plaintext in the column) keeps working. Consequences in 1.x: (1) legacy plaintext passwords/tokens are used verbatim and re-encrypted the next time that provider row is saved; (2) **any** decrypt failure also silently yields the ciphertext string as the "password" - wrong key, replaced key (3.2.1), unreadable key file, ciphertext imported from another machine; (3) there is no legacy fallback for kubeconfig content: decrypt failures throw (`KubeConfigMaterializer.swift:43`, `KubeConfigExecutionResolver.swift:62`) and the UI list logs the error and shows the raw ciphertext as the content (`KubeConfigViewModel.swift:119-122`).

Daemon rules:

1. **Legacy plaintext fallback is preserved** for `sshPassword` and `ngrokAuthToken` read from the DB and from backup JSON: a non-empty value that does not look like vault ciphertext is a legacy plaintext secret and is used as is. It is re-encrypted the next time the provider row is written (the daemon MUST NOT proactively rewrite rows on read).
2. **DEV-37(a):** a non-empty value that **looks like vault ciphertext** and fails to decrypt is NOT used as a secret. It is treated as unset (`None`), a WARN `KUMA_SEC_PAYLOAD_CORRUPTED`/`KUMA_SEC_INVALID_PAYLOAD` (no value) is logged, and on the import path the item is reported in the import result warnings ([09](09-dataport.md) owns the field; text `credential could not be decrypted with this machine's master key and was skipped`). "Looks like vault ciphertext" is the regex (after whitespace trim):

   `^[A-Za-z0-9+/]{16}:[A-Za-z0-9+/]{22}==:(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$`

   (12-byte nonce = 16 base64 chars; 16-byte tag = 22 chars + `==`; ciphertext any length, valid padded base64.) The value then also does not count for `sshPasswordSet`/`ngrokAuthTokenSet` (3.11).
3. Kubeconfig content has no legacy fallback (parity): decrypt failure -> error (3.2.4 code and message, surfaced for starts as `Start failed: <message>` in the activity log because the 1.x error is a `CryptoVaultError`, not a `ServiceExecutionError`). **DEV-37(b):** `kubeconfig.get` with reveal on an undecryptable inline content returns that error; it never returns the ciphertext as if it were YAML.
4. Decrypting an existing ciphertext while `master.key` is missing creates a new key as a side effect (parity: `decrypt` calls `getOrCreateMasterKey`, and all ciphertext then fails authentication, so 3.5 rule 2 applies). The daemon keeps this behavior but MUST emit the audit entry `vault.key_created` and a WARN log so the situation is visible (1.x was silent).

### 3.6 `vault:` prefix quirk (`provider.sshKeyPath`, passwords, tokens)

1.x contains three branches that look for a literal `vault:` prefix. No 1.x code ever writes such a value, and the real ciphertext format has no `vault:` prefix, so these are effectively dead code with surprising edge behavior:

| Site | 1.x behavior for a value starting with `vault:` | Source |
|------|--------------------------------------------------|--------|
| SSH password (after DB decode, trimmed) | `try? decrypt(value)` is called **with the prefix included**; the format check fails (the prefix adds a part or breaks base64), result `nil`, so a real password that merely starts with `vault:` is silently dropped and the runner falls to key auth / no auth. | `SSHTunnelRunner.swift:50-56` |
| ngrok token (trimmed) | `(try? decrypt(value)) ?? value`: decrypt fails, the raw token (with prefix) is passed to `--authtoken`. | `TunnelRunner.swift:76-80` |
| SSH key path (trimmed, only when no password) | `decrypt(value)` with prefix; always throws `invalidPayloadFormat`; runner throws `ServiceExecutionError.processFailed("Failed to decrypt SSH key path: <CryptoVaultError message>")`, displayed as `Execution failed: Failed to decrypt SSH key path: The encrypted payload format is invalid (expected nonce:tag:ciphertext).` | `SSHTunnelRunner.swift:72-80` |

**Daemon rule (DEV-37(c)):** a value starting with `vault:` is interpreted as `vault:<vault ciphertext>`. The daemon strips the prefix and decrypts the remainder. For SSH password and ngrok token, on any failure (including no valid ciphertext after the prefix) the value is used **verbatim** (so a real password `vault:abc` works; ngrok behavior unchanged). For SSH key path, a failure yields the exact error above (with the real `CryptoVaultError` message). The path is then tilde-expanded and must exist, otherwise `Invalid configuration: SSH private key file not found: '<keyPath>'` (`SSHTunnelRunner.swift:81-83`, the message embeds the **decrypted/stripped** path as in 1.x). The daemon never writes `vault:` values.

### 3.7 Temporary secret artifacts

#### 3.7.1 SSH askpass script (`SSHTunnelRunner.swift:123-142`)

When (after 3.6) the effective SSH password is non-empty, the runner creates an ephemeral askpass script. 1.x details:

| Aspect | 1.x |
|--------|-----|
| Directory | `$TMPDIR/kuma-ssh-<serviceID.uuidString>`; created with `withIntermediateDirectories: true` and **default attributes** (not `0700`); parent `$TMPDIR` is the macOS per-user private temp dir |
| File | `<dir>/askpass.sh`, written atomically (temp file + rename, UTF-8), then `chmod 0700` after the rename |
| Content | line 1 `#!/bin/sh`, line 2 `cat << 'EOF'`, line 3 the password with `\` -> `\\`, `"` -> `\"`, `$` -> `\$`, `` ` `` -> `` \` `` applied in that order, line 4 `EOF` (no trailing newline) |
| Spawn | `/usr/bin/ssh` with env additions `SSH_ASKPASS=<script path>`, `SSH_ASKPASS_REQUIRE=force`, `DISPLAY=kuma:0`, merged on top of the inherited environment (`ProcessRegistry.swift:113-118`) |
| Registration | `activeAskpassScripts[serviceID] = scriptPath` under an `NSLock` |
| Cleanup | only in `SSHTunnelRunner.stop(serviceID:)` (`:114-117, 150-158`): remove the **directory** (`removeItem` on the script's parent), ignoring errors. `stop` is called by `ServiceExecutionEngine.stop` for ssh providers and by `stopAllRunners`. A crash/exit of ssh that is never followed by a stop, a daemon/app crash, or a start failure after script creation (e.g. port conflict thrown at `:97-101`) leaves the script and password on disk. |
| Password transport | never via argv or env; only via the script file |

Quirk in 1.x: because the heredoc delimiter is quoted (`'EOF'`), the shell performs no expansion, so the escape step corrupts any password containing `\`, `"`, `$` or `` ` `` (ssh receives the password **with the added backslashes**), and a password containing a line equal to `EOF` or a newline breaks the script. Passwords without those characters work.

**Daemon rules (DEV-35):**

1. Script content MUST emit the password **verbatim**: `#!/bin/sh\nprintf '%s\n' '<pw with every ' replaced by '\''>'\n` (single-quote escaping; handles `\`, `$`, `` ` ``, `"`, spaces, newlines, `EOF`). Output is the password followed by exactly one `\n` (same as 1.x `cat` of the heredoc). A password containing NUL is rejected with `Invalid configuration: SSH password contains an unsupported character.`
2. Location: `<runtime dir>/askpass/<serviceID UPPERCASE>/askpass.sh`. The `askpass/` directory and the per-service directory MUST be mode `0700`; the script MUST be created with mode `0700` at creation time (`open(O_CREAT|O_EXCL, 0700)`, no chmod-after-write window; DEV-36a).
3. Environment: exactly `SSH_ASKPASS=<abs script path>`, `SSH_ASKPASS_REQUIRE=force`, `DISPLAY=kuma:0`, merged over the inherited environment. ssh argv additions exactly as in the constants table (06 owns the full argv).
4. Lifecycle - the directory MUST be removed on **all** of: runner `stop`; the ssh child exiting for any reason (the supervisor exit hook), including crashes before auto-reconnect (a reconnect re-creates it); a failed start after creation; daemon graceful shutdown; and a sweep of `<runtime dir>/askpass/` at daemon start (anything left by a crash, except for services whose ssh process was adopted - an adopted ssh no longer needs the script). Removal errors are logged (no content) and never fail the stop.
5. Adoption ([06](06-execution-engine.md)): the script is not needed by an already-authenticated ssh; an adopted service MUST NOT get a new script.
6. The password MUST be added to the redaction known-value set (3.12.3) while the script exists.

#### 3.7.2 Materialized kubeconfig (`KubeConfigMaterializer.swift`)

Used only when a provider references a stored (non-Default) kubeconfig whose `sourceFilePath` is empty. Resolution order in 1.x (paths only; full algorithm in [07](07-kubernetes.md)):

1. `provider.customKubeConfigPath` (legacy import-only), tilde-expanded, **if the file exists** -> used directly.
2. `kubeConfigID` nil -> Default id. If Default -> the user-configured/resolved real kubeconfig path (never materialized).
3. Row missing -> `Invalid configuration: Selected kubeconfig no longer exists.`
4. `sourceFilePath` non-empty -> expanded; exists -> used directly; else `Invalid configuration: Kubeconfig file not found at <rawPath>.` (raw, unexpanded, as stored).
5. Otherwise decrypt `configContent` (vault error propagates unchanged), trim; empty -> `Invalid configuration: Selected kubeconfig is empty.`; write the trimmed text to the materialized file.

| Aspect | 1.x | Daemon |
|--------|-----|--------|
| Dir | `<data dir>/kubeconfigs`; created if missing, then `chmod 0700` (an existing dir is never fixed) | create/enforce `0700` every time (DEV-36b) |
| File | `<dir>/<configID.uuidString>.yaml` (UPPERCASE UUID); written atomically then `chmod 0600` | same path; created with mode `0600` at creation (temp file `0600` + rename; DEV-36a). The path MUST NOT change: `kubectl port-forward` adoption matches running processes by this path ([07](07-kubernetes.md)). |
| Content | decrypted, trimmed YAML | same |
| Lifecycle | never deleted; rewritten on every start | rewritten on every start; **deleted** when the kubeconfig is deleted or updated (DEV-36d), by factory reset (the whole `kubeconfigs/` dir), and orphan files (UUID without a `kube_config` row) are swept at daemon start. Not deleted while a running service uses it (the file is only read at kubectl startup, but a reconnect re-materializes anyway). |
| Failure | exception | `KUMA_SEC_*` vault code, or the `Invalid configuration: <text>` messages of steps 3-5 above |

The Default kubeconfig is never copied, encrypted or imported (`importKubeConfigs` skips `KubeConfig.defaultID`, `collectReferencedKubeConfigIDs` filters it out). Its content is the user's own file and is never returned by default (3.11).

#### 3.7.3 Validation temp kubeconfig (`KubeConnectionValidator.swift:62-112`)

For `kubeconfig.test_connection` and the k8s preflight, 1.x writes the trimmed plaintext to `<NSTemporaryDirectory>/kuma-chk-<UUID>.yaml` (atomic write, default mode, private per-user temp dir), runs `kubectl --kubeconfig <file> version --output=yaml --request-timeout=4s [--context <ctx>]` with stdout+stderr merged, and removes the file in a `defer` registered right after the write (runs on success, failure and cancellation). The result cache key is `SHA-256(content + "::" + context)` hex (in memory only, never persisted; the digest is not reversible but the daemon MUST NOT log or return it).

Daemon rules:

- File under `<runtime dir>/tmp/` (dir `0700`), name `kuma-chk-<random UUID>.yaml`, created `0600`.
- Removal guaranteed on every path (success, kubectl failure, spawn failure, cancellation, panic via an RAII guard); orphan `kuma-chk-*` swept at daemon start.
- kubectl output (which may echo server URLs or tokens in error text) is not returned; only `isReachable` and the fixed messages `Unable to reach cluster`, `Empty kubeconfig content`, `kubectl binary not found in system PATH`, `Validation cancelled` ([07](07-kubernetes.md)).

#### 3.7.4 Other plaintext temp artifacts that can contain secrets

| Artifact | 1.x | Daemon requirement |
|----------|-----|--------------------|
| Ephemeral compose file | `docker-compose.kuma.yml` in the configured working dir, or `$TMPDIR/kuma-compose-<serviceID>/` (default perms) containing `provider.yamlConfig` (`ComposeStackResolver.swift:26-41`) | file mode `0600` at creation; the fallback dir `0700`; content never logged ([06](06-execution-engine.md)) |
| Process spool `<serviceID>.out` | `$TMPDIR/kuma-run/`, files created `0644` (`RunSpool.swift:20, 27`) | `<runtime dir>/spool` dir `0700`, files `0600` (DEV-36b) |

### 3.8 App sandbox, hardened runtime and entitlements (facts and implications)

Facts (1.x):

| Fact | Evidence |
|------|----------|
| App Sandbox is **off** for both Debug and Release | `project.pbxproj:340` and `:372` `ENABLE_APP_SANDBOX = NO` |
| `ENABLE_USER_SELECTED_FILES = readonly` is set but inert while the sandbox is off | `project.pbxproj:342, 374` |
| `ENABLE_USER_SCRIPT_SANDBOXING = YES` (Xcode build-phase scripts only, irrelevant at runtime) | `project.pbxproj:251, 314` |
| Entitlements file (Release only, `CODE_SIGN_ENTITLEMENTS = Kuma/Kuma.entitlements`, `project.pbxproj:367`) contains exactly three keys, all `false`: `com.apple.security.cs.allow-jit`, `com.apple.security.cs.allow-unsigned-executable-memory`, `com.apple.security.cs.disable-library-validation` | `Kuma/Kuma.entitlements` |
| No sandbox entitlements (`com.apple.security.app-sandbox`, `com.apple.security.network.client`, file-access entitlements) are declared | same file |
| `ENABLE_HARDENED_RUNTIME` is **not** set in the Xcode project; hardened runtime is applied at distribution time by `Scripts/mac-sign-app.sh` (`codesign --options runtime`, Developer ID, passing the entitlements file; notarization via `mac-notarize-dmg.sh`). Without signing secrets the release DMG is ad-hoc signed. | `Scripts/mac-sign-app.sh:16, 32-37`; README lines 63-88 |
| The bundle has no Keychain access | no `Keychain`/`SecItem` usage in `Kuma/` |

Implications for the daemon:

1. The daemon is a normal unsandboxed user process. It can spawn arbitrary executables (`kubectl`, `docker`, `podman`, `ssh`, `cloudflared`, `ngrok`, `/bin/sh`, `/bin/ps`), read any file the user can read (user-supplied key paths, kubeconfigs, compose files), and bind sockets. This matches 1.x and is required for parity.
2. If the daemon binary is distributed signed with hardened runtime, it needs **none** of the three exception entitlements (a Rust binary needs no JIT, no unsigned executable memory, and loads no third-party-signed dylibs). The daemon MUST NOT be shipped with `disable-library-validation`.
3. Because there is no sandbox, the data dir permissions (`0700`, 3.13) and the same-uid transport checks are the *only* isolation between the daemon and other local users. They are therefore normative, not best-effort.
4. Child processes inherit the daemon's environment (as in 1.x, `ProcessRegistry.swift:113-118`). The daemon MUST NOT put `KUMA_*` secret material (api token, key) into its own environment or into children's.
5. Any future sandboxing of the SwiftUI client must not affect the daemon; the client reaches the daemon only through the Unix socket (sandboxed apps would need a temporary-exception entitlement for that path - note for the client team, no daemon action).

### 3.9 Transport security (V2-ADD)

#### 3.9.1 Unix domain socket (ADD-30)

1. **Directory:** the runtime dir (`KUMA_RUNTIME_DIR`, default `<data dir>/run`) MUST be created `0700` and owned by the daemon's uid. If it exists: `lstat` it; if it is a symlink, not a directory, or owned by another uid -> refuse to start with `KUMA_SEC_RUNTIME_DIR_INSECURE`; if its mode has any group/other bit -> `chmod 0700` (WARN). Same enforcement for the data dir (`KUMA_SEC_DATA_DIR_INSECURE` for foreign owner/symlink; `chmod 0700` otherwise).
2. **Socket file:** `umask(0o177)` around `bind(2)`, then explicit `chmod(path, 0o600)`, then `lstat` and verify `mode & 0o177 == 0` and `st_uid == geteuid()`; otherwise close and fail start. A stale socket path is unlinked only if it is a socket owned by this uid and no process answers `connect` (full single-instance rules in [14](14-lifecycle-and-platform.md)). Note: macOS limits `sun_path` to 104 bytes including the NUL; the daemon fails start with a clear error if the resolved path is longer.
3. **Peer credential check (every accepted connection, before reading any byte):** obtain the peer uid with `getsockopt(fd, SOL_LOCAL, LOCAL_PEERCRED, struct xucred)` on macOS (`cr_uid`; also `cr_version` must equal `XUCRED_VERSION`), `SO_PEERCRED` (`struct ucred`) on Linux; Rust: `tokio::net::UnixStream::peer_cred()`. macOS pid for the audit log: `LOCAL_PEERPID`. If `peer_uid != geteuid()` (including uid 0 - root is NOT special-cased) -> close the connection immediately without a protocol reply, write an audit entry `kind: "auth", outcome: "rejected", reason: "peer-uid"` (error code `KUMA_SEC_PEER_REJECTED`, not sent). If the credential lookup itself fails -> treat as rejected.
4. No authentication token on the socket: filesystem mode + peer uid is the authentication. This transport is "trusted local" and is the only one eligible for `revealSecrets` (3.11).
5. The socket path and dir names are defined in [14](14-lifecycle-and-platform.md)/[10](10-rpc-protocol.md); only the permissions here are normative.
6. Process hardening (ADD-30): `setrlimit(RLIMIT_CORE, 0)` at start; the data dir `umask` for files created by the daemon is `0o077`; secrets zeroized on drop where the language allows.

#### 3.9.2 REST adapter (ADD-08 token, ADD-31 rest)

1. **Bind address:** default and only supported bind is `127.0.0.1` (IPv4 loopback). `::1` MAY be added as a second listener. Any non-loopback bind address (`0.0.0.0`, `::`, a LAN address) is refused at startup with `KUMA_SEC_REST_BIND_FORBIDDEN`: `REST adapter may only bind to a loopback address.` V2 provides no TLS; TLS is not required on loopback.
2. **Token (ADD-08):** every request, including `GET`, WebSocket upgrades and SSE streams, MUST carry `Authorization: Bearer <token>`. A token in the URL/query string MUST NOT be accepted (URLs end up in logs). There is no "auth disabled" mode.
   - File: `<data dir>/api-token`, mode `0600`, content = 64 lowercase hex characters (32 bytes from the OS CSPRNG) followed by one `\n`. Readers trim whitespace.
   - Created on first start of the REST listener if absent (temp file `0600` + rename). If it exists with a looser mode -> `chmod 0600` (WARN); if it is not owned by this uid or is a symlink -> `KUMA_SEC_DATA_DIR_INSECURE` (the REST listener does not start).
   - The daemon re-validates the token on every request against the in-memory copy; it re-reads the file when its `(inode, mtime, size)` changes (so rotation by file replacement takes effect without restart).
   - Comparison MUST be constant-time over equal-length byte strings (e.g. `subtle::ConstantTimeEq`); a length mismatch returns false after a dummy compare.
   - Missing/malformed header -> HTTP 401, `WWW-Authenticate: Bearer`, error `KUMA_SEC_TOKEN_MISSING`. Wrong token -> 401, `KUMA_SEC_TOKEN_INVALID`. Failed attempts are delayed 250 ms before the response and written to the audit log (`kind:"auth"`, `reason:"token"`), never including the presented value.
   - The token is never returned by any RPC/REST response, never logged, never put in an event, and is in the redaction known-value set.
3. **Rotation (ADD-31):** (a) RPC `daemon.rotate_api_token` (Unix socket only, [00 §5.1](00-overview-and-conventions.md)): generate 32 new bytes, write temp `0600`, `rename` over `api-token`, swap in-memory copy atomically, close every open REST WebSocket/SSE session (close code 1008 `policy violation`), audit `token.rotated`; result `{ "tokenPath": "<abs path>", "rotatedAt": "<ISO-8601>" }` (the token itself is NOT returned; the caller reads the 0600 file). (b) Manual: replace the file content with a new 64-hex value (`openssl rand -hex 32 > api-token` then `chmod 600`); picked up per the `(inode, mtime, size)` check. Deleting the file while running: the daemon keeps the in-memory token until restart and re-creates the file at the next start (WARN).
4. **Host header validation (anti DNS-rebinding):** the `Host` header MUST be present and equal (case-insensitive) one of `127.0.0.1:<port>`, `localhost:<port>`, `[::1]:<port>`, where `<port>` is the actual bound port. Otherwise HTTP 403 `KUMA_SEC_HOST_FORBIDDEN`. Evaluated **before** token checks and before any routing.
5. **Origin / CORS default deny:** if an `Origin` header is present (browser-originated request, including WebSocket upgrades) the request is rejected with 403 `KUMA_SEC_ORIGIN_FORBIDDEN`; `OPTIONS` preflights are answered 403; the daemon NEVER emits `Access-Control-Allow-*` headers. Non-browser clients (curl, CLI, scripts) send no `Origin` and are unaffected. V2 has no allow-list.
6. Response headers: `Cache-Control: no-store` on every response; `X-Content-Type-Options: nosniff`.
7. The REST adapter MUST present itself to the core with transport kind `rest` so that `revealSecrets` is refused (3.11) even if the adapter runs in-process.

#### 3.9.3 MCP bridge (ADD-30)

1. `kuma mcp` speaks MCP over **stdio only**; it opens no listening socket and no network connection.
2. It reaches the daemon over the Unix socket as the same uid (3.9.1 check applies), and sets connection kind `mcp` (3.11, Proposed RPC additions).
3. It MUST NEVER reveal secrets: it never sends `revealSecrets`; if a tool argument contains `revealSecrets` the bridge rejects the call locally; the daemon additionally refuses `revealSecrets` on a connection declared `mcp` (`KUMA_SEC_REVEAL_FORBIDDEN`).
4. It strips (removes the key; the masked boolean `sshPasswordSet`, `ngrokAuthTokenSet` or `hasContent` stays) any `sshPassword`, `ngrokAuthToken`, `configContent` and `encryptedConfigContent` keys from any result it forwards, including `data.export*` payloads. Free text it forwards is already redacted by the daemon (3.12); the bridge MUST NOT add raw log text from sources other than the daemon.
5. Tool/resource names and JSON shapes: [12](12-mcp.md).

### 3.10 Audit log (ADD-34)

File `<data dir>/audit.log`, JSON Lines (one compact JSON object per line, UTF-8, `\n` terminated), mode `0600`, opened `O_APPEND`. Rotation: when size >= 5 MiB at write time rename `audit.log.2 -> .3`, `.1 -> .2`, `audit.log -> .1` (drop old `.3`) and start a new file (still `0600`). A failure to write the audit line is logged (no payload) and MUST NOT fail the RPC call.

Entry fields:

| Key | Type | Notes |
|-----|------|-------|
| `ts` | string | ISO-8601 UTC with milliseconds, `2026-11-02T00:32:10.123Z` |
| `seq` | integer | monotonically increasing per daemon start, reset at start (not the event seq) |
| `kind` | string | `rpc`, `auth`, `vault`, `token` |
| `transport` | string | `unix`, `rest`, `mcp` |
| `peerUid` | integer or null | socket peer uid; null for REST |
| `peerPid` | integer or null | `LOCAL_PEERPID`/`SO_PEERCRED` pid when available |
| `remote` | string or null | REST remote `ip:port` |
| `method` | string or null | RPC method name (registry in [00](00-overview-and-conventions.md) section 5) |
| `outcome` | string | `ok`, `error`, `rejected` |
| `errorCode` | string or null | `KUMA_*` code when outcome is not `ok` |
| `reveal` | boolean | `revealSecrets` was requested and honored |
| `refs` | object | whitelisted identifiers only (below) |
| `durationMs` | integer | handler time |
| `event` | string or null | for `kind != rpc`: `vault.key_created`, `vault.key_replaced`, `peer-uid`, `token`, `token.rotated`, `host`, `origin` |

`refs` whitelist (values are UUID strings, enum strings or integers; any other param is dropped): `workspaceID`, `serviceID`, `providerID`, `kubeConfigID`, `groupID`, `scope`, `strategy`, `count` (length of a list param such as an id selection), `keys` (setting **names** for `settings.set`, never values). **No** string parameter values, no free text, no paths, no secrets, no kubeconfig content, no argv, ever.

Logged calls: all mutating methods - `daemon.shutdown`, `daemon.rotate_api_token`, `settings.set`, `settings.reset`, `workspace.create|update|delete|reorder|set_image|clear_image`, `group.create|update|delete|reorder`, `service.create|update|delete|duplicate|set_starred|set_disabled|set_groups|toggle_group|switch_provider|start|stop|restart|start_all|stop_all`, `provider.add|update|delete|set_ports`, `kubeconfig.create|update|delete`, `logs.clear`, `data.import`, `data.factory_reset`; plus secret-bearing reads `data.export`, `data.export_service_json`; plus **any** call with `revealSecrets: true` (honored or refused); plus every rejected connection/request (`auth`). Not logged: `daemon.ping`, `daemon.status`, `*.list/get/status/statuses` without reveal, `kubeconfig.contexts`, `kubeconfig.test_connection`, `env.*`, `events.*`, `logs.tail`, `logs.workload_tail`, `logs.follow`, `k8s.*`, `ports.check`, `service.preflight`, `runtime.adopt_report`.

### 3.11 Secret masking and reveal contract (ADD-32)

**Default (all transports): responses never contain secret plaintext.**

| Entity | Plaintext fields removed from responses | Replacement fields (always present) |
|--------|------------------------------------------|--------------------------------------|
| Provider (`provider.list`, `provider.add`, `provider.update`, embedded in `service.get`/`service.create`/`service.duplicate`/`data.*` previews that carry providers) | `sshPassword`, `ngrokAuthToken` | `sshPasswordSet: boolean`, `ngrokAuthTokenSet: boolean` (true iff a usable, decryptable non-empty secret is stored; both `false` for providers of other types) |
| KubeConfig (`kubeconfig.list`, `kubeconfig.get`, `kubeconfig.create`, `kubeconfig.update`) | `configContent` | `hasContent: boolean` (true iff `sourceFilePath` is empty and the decrypted inline content, trimmed, is non-empty; false for file-backed and for the virtual Default), plus `sourceFilePath` (string or null) as before |
| Backup/export payloads (`data.export`, `data.export_service_json`) | none: they carry **ciphertext** only: `providers[].sshPassword`, `providers[].ngrokAuthToken`, `kubeConfigs[].encryptedConfigContent` (vault format, 3.2) | - |
| Events, activity log lines, error messages, `daemon.status`, `settings.*` | any secret (3.12) | - |

Rules:

1. `data.import_preview` and import results MUST NOT echo secret values or ciphertext.
2. Ciphertext in `data.export*` is allowed on the Unix socket and REST (it is useless without this machine's `master.key` and is what a backup is), and is stripped by the MCP bridge (3.9.3).
3. Event payloads (`service.created`, `service.updated`, `kubeconfig.changed`, and every other event in the 00 section 5.7 registry) always carry the masked form; `revealSecrets` does not apply to events.

**`revealSecrets`:** optional boolean param (default `false`) accepted by `provider.list`, `provider.add`, `provider.update`, `service.get`, `service.list` (when it embeds providers), `kubeconfig.list`, `kubeconfig.get`, `kubeconfig.create`, `kubeconfig.update`.

| Transport | `revealSecrets: true` |
|-----------|----------------------|
| Unix socket, peer uid verified equal, connection kind `cli` or `app` (or unspecified) | honored: the response additionally contains `sshPassword` / `ngrokAuthToken` (plaintext strings, omitted when unset) and `configContent` (for a stored inline kubeconfig the decrypted text; for a file-backed stored kubeconfig the current file text as 1.x `resolvedPlainYAML()` does, empty string if unreadable; for Default the real file text). The masked booleans stay present. Audit entry with `reveal: true`. |
| Unix socket, connection kind `mcp` or `rest` | refused: error `KUMA_SEC_REVEAL_FORBIDDEN` (the call is not partially served) |
| REST | refused: `KUMA_SEC_REVEAL_FORBIDDEN` (HTTP 403) |
| MCP | refused (bridge rejects locally; daemon also refuses) |

Undecryptable stored secrets under reveal: the field is omitted (DEV-37(a)); undecryptable kubeconfig content returns the vault error (DEV-37(b)).

**Connection kind** is a *safety rail*, not a security boundary: any same-uid process can read `master.key` and the database directly (see threat model). It prevents accidental reveals by adapters and gives the audit log attribution. See Proposed RPC additions (extension of `daemon.ping`).

### 3.12 Redaction (GR-04) - ADD-33, DEV-38

GR-04: no secret may appear in logs, events or error messages. 1.x has no redaction anywhere: free text such as `Start failed: <description>`, compose output (`composeFailureMessage` embeds the full `compose up` output, `ContainerRunner.swift:309-324`), `[HEALTH] <url>` lines (`ExecutionSupervisor.swift:473-476`), and raw process output are written verbatim to the activity log, and `ngrok --authtoken <token>` is visible in `ps` (the supervisor itself reads `ps -axo pid=,command=`, `ExecutionSupervisor.swift:520-524`). The daemon adds one central function.

#### 3.12.1 Function contract

```
redact(text: &str, profile: Profile, known: &KnownSecrets) -> String      // total, never fails
redact_argv(argv: &[String], known: &KnownSecrets) -> Vec<String>          // for persisted/echoed argv
```

- Replacement mark: exactly `***`.
- Pure and idempotent: `redact(redact(x)) == redact(x)`. Must be linear-time (no catastrophic regexes; use the Rust `regex` crate, which guarantees this). Input larger than 1 MiB is processed in 64 KiB overlapping windows (overlap 4 KiB) so very long log lines cannot stall the daemon.
- Rules are applied in the order R8, R5, R4, R2, R1, R3, R6, R7 (known values first so partial pattern matches cannot split them).
- Profiles: `strict` = all rules; `workload` = R4, R5, R8 only (high-precision rules; user process output keeps its fidelity).

| Rule | Matches | Replaced by |
|------|---------|-------------|
| **R8 known values** | every occurrence of any value in `KnownSecrets` with length >= 4 (plain, and also its percent-encoded form and base64 form) | `***` |
| **R5 PEM private keys** | `-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----` through the matching `-----END [A-Z0-9 ]*PRIVATE KEY-----` (non-greedy, dot matches newline); an unterminated BEGIN redacts to end of input | `***` |
| **R4 vault ciphertext** | the 3.5 ciphertext regex (anchors removed, word-bounded) | `***` |
| **R2 kubeconfig material** (per line, YAML) | `(?im)^(\s*(?:-\s*)?(?:token\|password\|client-key-data\|client-certificate-data\|access-token\|refresh-token\|id-token\|client-secret)\s*:\s*)\S.*$` | `${1}***` |
| **R1 secret flags** | `(?i)(--?(?:auth-?token\|token\|password\|passwd\|secret\|api-?key\|access-?key\|client-?secret))(?:=\|\s+)("[^"]*"\|'[^']*'\|\S+)`; for `redact_argv`, an argv element equal to such a flag (no `=`) masks the **next element**, and `--flag=value` becomes `--flag=***` | `${1}=***` in text; `***` as the next argv element |
| **R3 bearer/auth headers** | `(?i)\bauthorization\s*:\s*\S+(?:\s+\S+)?` and `(?i)\bbearer\s+[A-Za-z0-9._~+/=-]{8,}` | `Authorization: ***` / `Bearer ***` |
| **R6 URL userinfo** | `(?i)\b([a-z][a-z0-9+.-]*://[^/\s:@]+:)[^@\s/]+@` | `${1}***@` |
| **R7 env-style assignments** | `(?i)\b([A-Z0-9_]*(?:TOKEN\|PASSWORD\|PASSWD\|SECRET\|API_?KEY\|ACCESS_KEY\|AUTH)[A-Z0-9_]*)=("[^"]*"\|'[^']*'\|\S+)` | `${1}=***` |

R1 deliberately excludes short `-p` (ambiguous with port flags). Query strings (`?token=...`) are covered by R7 only when written as `NAME=value`; `?token=abc` is matched because R7's name part allows a preceding non-word boundary (`\b`) and `token` is in the list. Examples (normative test inputs):

| Input | Output |
|-------|--------|
| `ngrok http http://localhost:3000 --authtoken 2Bxx_Secret` | `ngrok http http://localhost:3000 --authtoken=***` |
| `kubectl --token abc123 get pods` | `kubectl --token=*** get pods` |
| `kubectl --token=abc123 get pods` | `kubectl --token=*** get pods` |
| `https://user:hunter2@example.com/x` | `https://user:***@example.com/x` |
| `Authorization: Bearer eyJhbGciOi.xyz` | `Authorization: ***` |
| `    token: s3cr3t` (kubeconfig line) | `    token: ***` |
| `MY_API_KEY="abc def"` | `MY_API_KEY=***` |
| `oKGio6Slpqeoqaqr:aSlm+ME6/z3+vc54fWZPHg==:jW0RTBq/Z8wWOuOycxs=` | `***` |
| `ssh failed: bad password SuperSecretSSHPassword123!` (value in known set) | `ssh failed: bad password ***` |

#### 3.12.2 Where it is applied

| Sink | Profile | Notes |
|------|---------|-------|
| Daemon's own tracing/log output (every message and every captured error text) | `strict` | tracing layer wrapper; secrets MUST also never be placed in structured fields |
| RPC error `message` and `data` strings (all transports) | `strict` | after the exact 1.x text is formed |
| Activity log lines (`[KUMA]`, `[FAILURE]`, `[HEALTH]`, `[MONITOR]` prefixed lines, compose failure text, `Start failed: <description>` lines) before they enter the buffer and before `service.log_line` | `strict` | [08](08-logs-and-events.md) |
| `notify` / any event free-text field | `strict` | |
| Workload log lines served by `logs.workload_tail`, `logs.follow`, and process output lines that become `service.log_line` | `workload` | DEV-38; the on-disk spool stays raw |
| `runtime_process.argvJSON` and any argv shown in `daemon.status` / diagnostics | `redact_argv` + `strict` per element | persisted **already redacted**; adoption comparison (06) MUST redact the live process argv with the same function and compare redacted-to-redacted; `executable`, `composeContextJSON` contain no secrets but still pass through `strict` |
| Audit log | not needed (whitelist), but `refs` strings pass `strict` defensively | |
| `kubectl`/`docker` stderr surfaced in errors (e.g. compose output) | `strict` | |

#### 3.12.3 KnownSecrets

An in-memory set (never persisted, never logged, zeroized on drop) holding: every non-empty decrypted `sshPassword`/`ngrokAuthToken` loaded by any repository read; the effective SSH password while an askpass script exists; the plaintext of kubeconfig token/key values is **not** tracked (R2 covers the YAML shape); the API token (hex); the master key as hex and as base64. Entries are added when decrypted and are never removed during the process lifetime (a later password change must not un-redact the old value in historic log lines). The set is capped at 4096 entries (oldest evicted).

### 3.13 Permission matrix (what the daemon creates or enforces)

| Path | Type | Mode | Created by | Enforcement on existing |
|------|------|------|------------|--------------------------|
| `<data dir>` | dir | `0700` | daemon | `chmod 0700` if looser (DEV-36b) |
| `<data dir>/master.key` | file | `0600` | vault | `chmod 0600` if looser; length rules per 3.2.1 |
| `<data dir>/kuma.sqlite`, `-wal`, `-shm` | files | `0600` | DB layer | `chmod 0600` at open (DEV-36b); 1.x leaves umask default |
| `<data dir>/daemon-state.sqlite` (+ `-wal`, `-shm`) | files | `0600` | daemon | same |
| `<data dir>/kubeconfigs/` | dir | `0700` | materializer | `chmod 0700` |
| `<data dir>/kubeconfigs/<UUID>.yaml` | file | `0600` | materializer | rewritten with `0600` |
| `<data dir>/api-token` | file | `0600` | REST | `chmod 0600` |
| `<data dir>/audit.log*` | files | `0600` | audit | `chmod 0600` |
| `<runtime dir>` | dir | `0700` | daemon | per 3.9.1 |
| `<runtime dir>/<socket>` | socket | `0600` | daemon | per 3.9.1 |
| `<runtime dir>/askpass/`, `/<serviceID>/` | dirs | `0700` | SSH runner | recreated |
| `<runtime dir>/askpass/<serviceID>/askpass.sh` | file | `0700` | SSH runner | recreated |
| `<runtime dir>/tmp/`, `kuma-chk-*.yaml` | dir / file | `0700` / `0600` | validator | swept at start |
| `<runtime dir>/spool/`, `<serviceID>.out` | dir / files | `0700` / `0600` | execution | enforced |
| `master.key.corrupt-<unixMs>` | file | `0600` | vault | - |

All secret files MUST be created with their final mode atomically (open with the mode, or temp file with the mode then `rename`), never `write` then `chmod` (DEV-36a).

---

## 4. Data shapes

### 4.1 Vault payload

| Part | Index | Raw bytes | Encoding |
|------|-------|-----------|----------|
| nonce | 0 | 12 | base64 standard, padded (16 chars) |
| tag | 1 | 16 | base64 standard, padded (always 24 chars: 22 significant characters followed by `==`) |
| ciphertext | 2 | `len(plaintext)` | base64 standard, padded; empty string when plaintext is empty |

### 4.2 Masked provider additions (wire)

| Field | Type | Optional? | Default | JSON key |
|-------|------|-----------|---------|----------|
| SSH password present | boolean | no | `false` | `sshPasswordSet` |
| ngrok token present | boolean | no | `false` | `ngrokAuthTokenSet` |
| SSH password (reveal only) | string | yes (omitted unless revealed and set) | - | `sshPassword` |
| ngrok token (reveal only) | string | yes | - | `ngrokAuthToken` |
| Write: SSH password | string or null | yes (absent = keep) | - | `sshPassword` |
| Write: ngrok token | string or null | yes (absent = keep) | - | `ngrokAuthToken` |

### 4.3 Masked kubeconfig additions (wire)

| Field | Type | Optional? | Default | JSON key |
|-------|------|-----------|---------|----------|
| Inline content present | boolean | no | `false` | `hasContent` |
| Source path | string | yes (null) | null | `sourceFilePath` |
| Content (reveal only) | string | yes | - | `configContent` |
| Write: pasted content | string | yes | - | `configContent` |

### 4.4 Backup JSON secret fields (unchanged from 1.x; `DataPortService+BackupModels.swift:116-146, 318-342`)

| Object | Field | Type | Optional? | JSON key |
|--------|-------|------|-----------|----------|
| `providers[]` | SSH password ciphertext | string | yes | `sshPassword` |
| `providers[]` | ngrok token ciphertext | string | yes | `ngrokAuthToken` |
| `providers[]` | key path | string | yes | `sshKeyPath` |
| `kubeConfigs[]` | id | UUID | no | `id` |
| `kubeConfigs[]` | name | string | yes | `name` |
| `kubeConfigs[]` | source path | string | yes | `path` |
| `kubeConfigs[]` | ciphertext | string | yes | `encryptedConfigContent` |
| `kubeConfigs[]` | created / updated | ISO-8601 (`.iso8601`, second precision, e.g. `2023-11-14T22:13:20Z`) | yes | `createdAt`, `updatedAt` |

Backups are written with `.prettyPrinted` and `.sortedKeys`, `version` = 1 (`DataPortService.currentVersion`). Full backup schema: [09](09-dataport.md).

### 4.5 Audit entry

See 3.10 table.

### 4.6 Transport matrix

| Property | Unix socket | REST | MCP (stdio) |
|----------|-------------|------|-------------|
| Reachability | local fs, uid-only | `127.0.0.1` only | local process, no listener |
| Authentication | dir `0700` + socket `0600` + peer uid == daemon uid | bearer token + Host + no Origin | via the socket (same uid) |
| `revealSecrets` | honored (kind cli/app) | refused | refused |
| Ciphertext in `data.export*` | yes | yes | stripped |
| Audit `transport` value | `unix` | `rest` | `mcp` |
| TLS | n/a | not required (loopback) | n/a |

---

## 5. Features table

| FEAT id | Tag | Description | 1.x source | RPC methods |
|---------|-----|-------------|------------|-------------|
| FEAT-SEC-01 | [PARITY] | AES-256-GCM vault: encrypt/decrypt with `nonce:tag:ciphertext` payloads, exact errors | `CryptoVault.swift:94-134`, `CryptoVaultTests` TC-E04..E09 | - (internal; used by `provider.*`, `kubeconfig.*`, `data.*`) |
| FEAT-SEC-02 | [PARITY] | Master key file lifecycle: `master.key`, 32 bytes, `0600`, dir `0700`, atomic write, regenerate on wrong length, process-lifetime cache | `CryptoVault.swift:43-88`, TC-E01..E03, E08 | - |
| FEAT-SEC-03 | [PARITY] | Provider `sshPassword` encrypted at rest, decrypted on read | `Provider+Record.swift:39-47, 127-131`, TC-B01 | `provider.add`, `provider.update`, `provider.list`, `service.create`, `service.duplicate`, `service.get` |
| FEAT-SEC-04 | [PARITY] | Provider `ngrokAuthToken` encrypted at rest, decrypted on read | `Provider+Record.swift:52-60, 139-143`, TC-B02 | same as FEAT-SEC-03 |
| FEAT-SEC-05 | [PARITY] | Kubeconfig inline content encrypted at rest; file-backed stores `encrypt("")` + `sourceFilePath` | `KubeConfigViewModel.swift:231-245`, TC-B04, B04d | `kubeconfig.create`, `kubeconfig.update`, `kubeconfig.get`, `kubeconfig.list` |
| FEAT-SEC-06 | [PARITY] | Legacy plaintext fallback on read for provider secrets (kept; hardened by DEV-37) | `Provider+Record.swift:43, 56`, `Mapping.swift:94, 101` | `provider.list`, `service.get`, `data.import` |
| FEAT-SEC-07 | [PARITY] | Empty string -> nil/NULL rules for secrets, trims, kubeconfig import skip rules | 3.4 sources | `provider.add`, `provider.update`, `kubeconfig.create`, `data.import` |
| FEAT-SEC-08 | [PARITY] | Fail-closed writes: encryption failure aborts the write, never stores plaintext | `CredentialProtector.swift:5-7`, `Provider+Record.swift:128-142` | all mutating methods that write providers/kubeconfigs |
| FEAT-SEC-09 | [PARITY] | Export re-encrypts provider credentials; backup JSON never contains plaintext password/token | `Mapping.swift:42-89`, TC-B02b, TC-B06 | `data.export`, `data.export_service_json` |
| FEAT-SEC-10 | [PARITY] | Kubeconfig ciphertext exported and imported verbatim; referenced-only export; Default skipped | `Export.swift:240-263`, `Mapping.swift:5-40`, TC-B06b, DataPort C20/C21, B07 | `data.export`, `data.export_service_json`, `data.import` |
| FEAT-SEC-11 | [PARITY] | Provider secret import: decrypt-with-fallback then re-encrypt under local key | `Mapping.swift:91-139` | `data.import` |
| FEAT-SEC-12 | [PARITY] | `vault:`-prefixed values for key path / password / token (quirk, normalized by DEV-37) | `SSHTunnelRunner.swift:50-80`, `TunnelRunner.swift:76-80` | `service.start`, `service.restart` |
| FEAT-SEC-13 | [PARITY] | SSH password auth via ephemeral askpass script (`SSH_ASKPASS`, `SSH_ASKPASS_REQUIRE=force`, `DISPLAY=kuma:0`), removed on stop | `SSHTunnelRunner.swift:56-72, 123-158`, TC-R07 | `service.start`, `service.stop`, `service.restart` |
| FEAT-SEC-14 | [PARITY] | Kubeconfig materialization to `<data dir>/kubeconfigs/<UUID>.yaml` (`0700`/`0600`) for kubectl | `KubeConfigMaterializer.swift` | `service.start`, `kubeconfig.test_connection` |
| FEAT-SEC-15 | [PARITY] | Validation temp kubeconfig `kuma-chk-<UUID>.yaml`, removed after probe | `KubeConnectionValidator.swift:62-112` | `kubeconfig.test_connection`, `service.preflight` |
| FEAT-SEC-16 | [PARITY] | ngrok token passed as `--authtoken <token>` argv (documented exposure) | `TunnelRunner.swift:76-81` | `service.start` |
| FEAT-SEC-17 | [PARITY] | Platform facts: unsandboxed process, no Keychain, hardened-runtime-at-distribution, empty entitlements | `project.pbxproj`, `Kuma.entitlements`, `mac-sign-app.sh` | - |
| FEAT-SEC-18 | [V2-ADD] | Unix socket hardening: dir `0700`, socket `0600`, ownership checks (ADD-30) | - | all (transport) |
| FEAT-SEC-19 | [V2-ADD] | Peer-credential uid check; refuse other uids incl. root (ADD-30) | - | all (transport) |
| FEAT-SEC-20 | [V2-ADD] | REST loopback-only bind (ADD-31) | - | all via REST |
| FEAT-SEC-21 | [V2-ADD] | REST bearer token file `api-token`, constant-time compare (ADD-08, ADD-31) | - | all via REST |
| FEAT-SEC-22 | [V2-ADD] | API token rotation (RPC and manual file replacement) (ADD-31) | - | `daemon.rotate_api_token` |
| FEAT-SEC-23 | [V2-ADD] | Host header allow-list, Origin rejection, CORS default deny (ADD-31) | - | all via REST |
| FEAT-SEC-24 | [V2-ADD] | MCP bridge: stdio only, same-uid, never reveals secrets, strips ciphertext (ADD-30, ADD-32) | - | all via MCP |
| FEAT-SEC-25 | [V2-ADD] | Masked responses: `sshPasswordSet`, `ngrokAuthTokenSet`, `hasContent` (ADD-32) | - | `provider.list`, `provider.add`, `provider.update`, `service.get`, `service.list`, `kubeconfig.list`, `kubeconfig.get` |
| FEAT-SEC-26 | [V2-ADD] | `revealSecrets` socket-only, same-uid, refused elsewhere (ADD-32) | - | same as FEAT-SEC-25 |
| FEAT-SEC-27 | [V2-ADD] | Central redaction function and profiles (ADD-33, DEV-38) | - | all error/log/event surfaces |
| FEAT-SEC-28 | [V2-ADD] | Redacted persisted argv in `runtime_process` and redacted adoption comparison (ADD-33) | - | `runtime.adopt_report`, `daemon.status` |
| FEAT-SEC-29 | [V2-ADD] | Audit log of mutating and secret-bearing calls, no secrets (ADD-34) | - | all mutating methods |
| FEAT-SEC-30 | [V2-ADD] | File/dir permission enforcement (`0700`/`0600`), mode-at-creation, spool `0600`, kubeconfig lifecycle cleanup (DEV-36) | - | - |
| FEAT-SEC-31 | [V2-ADD] | Askpass verbatim password and full cleanup guarantees (DEV-35) | - | `service.start`, `service.stop` |
| FEAT-SEC-32 | [V2-ADD] | Process hardening: no core dumps, key zeroization, `master.key` race-safe creation (ADD-30, DEV-36) | - | - |
| FEAT-SEC-33 | [CLIENT] | UI masking of password/token fields, "show password" toggle, copy actions in Create/Inspector forms (client only; the client must not request `revealSecrets` unless the user explicitly asks to show a stored value) | `SSHSettingsView.swift`, `TunnelSettingsView.swift` | - |
| FEAT-SEC-34 | [CLIENT] | Kubeconfig editor: choose file vs paste mode, `isSaveDisabled`, inline form state (`KubeConfigViewModel` form state) | `KubeConfigViewModel.swift:180-216` | - (writes go through `kubeconfig.create`/`kubeconfig.update`) |
| FEAT-SEC-35 | [PARITY] | `KubeConfigViewModel.fetchAndDecryptConfigs`/`deleteConfig`: list with decrypted content; delete (not Default) | `KubeConfigViewModel.swift:78-131, 287-296` | `kubeconfig.list`, `kubeconfig.get` (reveal), `kubeconfig.delete` |

Function accountability (every function in the assigned 1.x sources): `CryptoVault.getOrCreateMasterKey/encrypt/decrypt` -> FEAT-SEC-01/02; `CryptoVaultError` -> 3.2.4; `CredentialProtector.encryptForStorage` -> FEAT-SEC-08; `Provider.init(row:)`/`encode(to:)` -> FEAT-SEC-03/04/06/07; `KubeConfig` record init/encode -> no crypto (note in 3.3 row 3); `collectReferencedKubeConfigIDs`/`importKubeConfigs`/`toExportProvider`/`fromExportProvider` -> FEAT-SEC-09..11; `exportSingleServiceBackup`/`exportAll`/`exportWorkspace`/`kubeConfigsForExport`/`exportKubeConfigs`/`exportSingleServiceJSON` -> FEAT-SEC-09/10; `KubeConfigMaterializer.kubectlKubeconfigPath`/`materializedFileURL` -> FEAT-SEC-14; `SSHTunnelRunner.createAskpassScript`/`registerAskpass`/`cleanupAskpass` -> FEAT-SEC-13; `TunnelRunner.startNgrok` -> FEAT-SEC-16 (the rest of `TunnelRunner`, `startCloudflare`, is 06); `KubeConfigViewModel.saveConfig` -> FEAT-SEC-05; remaining `KubeConfigViewModel` members (selection, context parsing, validation triggers) -> [07](07-kubernetes.md)/[CLIENT]; `KubeConnectionValidator` temp file -> FEAT-SEC-15 (cache and messages in 07).

---

## 6. Error catalog

| Code | Condition | Message |
|------|-----------|---------|
| `KUMA_SEC_INVALID_UTF8` | opened plaintext is not valid UTF-8 | `The data could not be encoded or decoded as UTF-8.` |
| `KUMA_SEC_INVALID_PAYLOAD` | payload does not have 3 parts or a non-empty part is not base64 | `The encrypted payload format is invalid (expected nonce:tag:ciphertext).` |
| `KUMA_SEC_PAYLOAD_CORRUPTED` | nonce/tag size wrong or GCM authentication failed | `The encrypted payload is corrupted or authentication tag verification failed.` |
| `KUMA_SEC_KEY_FILE_ACCESS` | `master.key`/data dir cannot be read or written (not a wrong-length file) | `File access error for master key: <OS error text>` |
| `KUMA_SEC_PEER_REJECTED` | socket peer uid differs from daemon uid or credential lookup failed (connection dropped, audit only) | `Connection rejected: peer user does not match the daemon user.` |
| `KUMA_SEC_TOKEN_MISSING` | REST request without a `Bearer` token (HTTP 401) | `Authentication required: missing bearer token.` |
| `KUMA_SEC_TOKEN_INVALID` | REST bearer token does not match (HTTP 401) | `Authentication failed: invalid bearer token.` |
| `KUMA_SEC_HOST_FORBIDDEN` | REST `Host` header not in the loopback allow-list (HTTP 403) | `Request rejected: unexpected Host header.` |
| `KUMA_SEC_ORIGIN_FORBIDDEN` | REST request carries an `Origin` header or is a CORS preflight (HTTP 403) | `Request rejected: cross-origin requests are not allowed.` |
| `KUMA_SEC_REVEAL_FORBIDDEN` | `revealSecrets: true` on REST, MCP, or a non-reveal connection kind | `Revealing secrets is only allowed over the local Unix socket.` |
| `KUMA_SEC_REST_BIND_FORBIDDEN` | REST bind address is not loopback | `REST adapter may only bind to a loopback address.` |
| `KUMA_SEC_RUNTIME_DIR_INSECURE` | runtime dir is a symlink, not a directory, or owned by another uid | `Runtime directory is not safe to use: <path>` |
| `KUMA_SEC_DATA_DIR_INSECURE` | data dir or token file is a symlink or owned by another uid | `Data directory is not safe to use: <path>` |
| `KUMA_SEC_LOCAL_ONLY` | operation restricted to the local Unix socket was called over REST/MCP (`daemon.rotate_api_token`) | `This operation is only allowed over the local Unix socket.` |
| `KUMA_SEC_ASKPASS_UNSUPPORTED` | SSH password contains NUL | `Invalid configuration: SSH password contains an unsupported character.` |

Messages reproduced verbatim from 1.x elsewhere (owned by 06/07, listed because secrets are involved): `Invalid configuration: SSH Host is not configured.`, `Invalid configuration: Selected kubeconfig no longer exists.`, `Invalid configuration: Kubeconfig file not found at <rawPath>.`, `Invalid configuration: Selected kubeconfig is empty.`, `Invalid configuration: SSH private key file not found: '<keyPath>'`, `Execution failed: Failed to decrypt SSH key path: <vault message>`, validator messages `SSH password is required.`, `Ngrok auth token is required.`, `SSH private key path is required.`.

All messages pass through `redact(strict)` before leaving the daemon; none contain secret values.

---

## 7. Deviations

| ID | Summary (full text in [15](15-traceability-and-parity.md)) |
|----|------|
| DEV-09 | Secrets use `master.key` (AES-256-GCM), not Keychain (pre-assigned). |
| DEV-35 | Askpass script emits the password verbatim (1.x corrupted passwords containing `\ " $ `` ` ``), lives in `<runtime dir>/askpass/<serviceID>/` (dir `0700`), and is removed on stop, child exit, failed start, shutdown, and swept at start (1.x: only on `stop`). |
| DEV-36 | Secret-file hygiene: (a) files/dirs created with final mode atomically (1.x chmod after write); (b) existing data dir, `kuma.sqlite`, `master.key`, `kubeconfigs/`, runtime dir are tightened to `0700`/`0600` and spool files become `0600` (1.x: data dir typically `0755`, spool `0644`); (c) `master.key` creation is mutex-serialized and no-clobber (`link`), and a wrong-length key file is backed up to `master.key.corrupt-<unixMs>` before replacement; (d) materialized plaintext kubeconfigs are deleted on `kubeconfig.delete`/update, factory reset, and orphan sweep (1.x never deleted them). |
| DEV-37 | Credential read semantics: (a) ciphertext-shaped values that fail to decrypt are treated as unset instead of being used as the password/token (1.x fed the ciphertext string to ssh/ngrok); (b) `kubeconfig.get` reveal never returns ciphertext as YAML; (c) `vault:` prefix is stripped before decrypt and falls back to the verbatim value for passwords/tokens (1.x dropped a `vault:` password). |
| DEV-38 | Workload (user process) output served to clients goes through the `workload` redaction profile (R4, R5, R8); 1.x showed raw output. On-disk spool remains raw. |

New additions in this range: ADD-30 (local transport and process hardening: socket perms, peer-uid, MCP bridge, core dumps), ADD-31 (REST loopback bind, token file management and rotation, Host/Origin/CORS), ADD-32 (masking and reveal contract), ADD-33 (central redaction and redacted persisted argv), ADD-34 (audit log). ADD-08 (REST bearer-token auth) is defined here normatively (3.9.2).

---

## 8. Invariants

| ID | Statement |
|----|-----------|
| INV-D-SEC-01 | `master.key` is exactly 32 raw bytes, mode `0600`, in a `0700` data dir; the daemon never logs, returns, or serializes it. |
| INV-D-SEC-02 | Every payload the daemon writes into `provider.sshPassword`, `provider.ngrokAuthToken`, `kube_config.configContent` and backup secret fields is `nonce(12):tag(16):ciphertext`, standard padded base64, AES-256-GCM, no AAD, fresh random nonce per encryption. |
| INV-D-SEC-03 | Any payload produced by Kuma 1.x with the same `master.key` decrypts in the daemon, and vice versa. |
| INV-D-SEC-04 | A failure to encrypt aborts the whole write; plaintext is never persisted and never exported in place of a ciphertext. |
| INV-D-SEC-05 | `provider.sshPassword`/`ngrokAuthToken` are NULL when unset or empty; never an encrypted empty string. File-backed kubeconfigs store `encrypt("")`, never NULL, never plaintext. |
| INV-D-SEC-06 | No RPC response, event, log line, error message, audit entry or persisted argv contains a secret value or kubeconfig plaintext, except `revealSecrets: true` responses on the Unix socket to a verified same-uid non-`mcp`, non-`rest` connection. |
| INV-D-SEC-07 | The socket is `0600` in a `0700` directory and every connection's peer uid equals the daemon uid, else it is dropped before any byte is read. |
| INV-D-SEC-08 | The REST listener binds only to loopback, requires a valid bearer token on every request, validates `Host`, rejects any `Origin`, and never emits CORS headers. |
| INV-D-SEC-09 | Token comparison is constant-time; the token file is `0600`; the token is never returned by any call. |
| INV-D-SEC-10 | Askpass scripts, materialized kubeconfigs and validation temp files are created with their final mode (`0700`/`0600`/`0600`) inside `0700` directories, and are deleted on every exit path of their owner (askpass: stop, child exit, failed start, shutdown, startup sweep; validation file: always). |
| INV-D-SEC-11 | The SSH password is delivered to `ssh` only via the askpass file; it never appears in argv or environment. |
| INV-D-SEC-12 | A ciphertext-shaped value that cannot be decrypted is never used as a credential. |
| INV-D-SEC-13 | Redaction is total, idempotent, linear-time, and uses the single mark `***`. |
| INV-D-SEC-14 | Every mutating call, every `revealSecrets` request and every rejected connection/request produces exactly one audit entry whose `refs` contain only whitelisted identifiers. |
| INV-D-SEC-15 | The daemon's own environment and its children's environment never contain the API token or master key. |
| INV-D-SEC-16 | The default kubeconfig (`00000000-0000-0000-0000-000000000001`) is never encrypted, copied, exported or imported. |

---

## 9. Acceptance tests

| ID | Arrange | Assert |
|----|---------|--------|
| DT-SEC-01 | Known-answer table 3.2.6 A | `encrypt_with_nonce` equals each expected string; `decrypt` returns each plaintext. |
| DT-SEC-02 | Fixed key, vector 1 | Tag bit flip -> `KUMA_SEC_PAYLOAD_CORRUPTED`; ciphertext replaced by `YWJjZGVmZ2hpams=` -> `KUMA_SEC_PAYLOAD_CORRUPTED`. |
| DT-SEC-03 | Random key | `decrypt("not_a_valid_payload")`, `decrypt("part1:part2")`, `decrypt(valid + ":x")` -> `KUMA_SEC_INVALID_PAYLOAD` with exact message; `decrypt(":x:")` -> `KUMA_SEC_PAYLOAD_CORRUPTED`. |
| DT-SEC-04 | Empty data dir | First `encrypt` creates `master.key` with 32 bytes, mode `0600`; data dir `0700`; second call returns the identical key; file unchanged. |
| DT-SEC-05 | `master.key` of 31 bytes and another of 0 bytes | New 32-byte key generated; old file preserved as `master.key.corrupt-<ms>` (`0600`); audit `vault.key_replaced`. |
| DT-SEC-06 | `master.key` unreadable (mode `0000`) as non-root | `encrypt` returns `KUMA_SEC_KEY_FILE_ACCESS` with prefix `File access error for master key: `; the file is NOT replaced. |
| DT-SEC-07 | 32 threads call `encrypt` simultaneously with no key file | Exactly one key is created; all payloads decrypt with the final key. Two processes racing: both end with the same key (link no-clobber). |
| DT-SEC-08 | Encrypt `"x"` twice | Payloads differ; each has 3 parts, nonce 12 bytes, tag 16 bytes. Empty plaintext round trips; multiline private key round trips. |
| DT-SEC-09 | `provider.add` SSH with password `SuperSecretSSHPassword123!` | Raw `provider.sshPassword` column is not the plaintext and has the 3-part format; `provider.list` (default) has `sshPasswordSet: true` and no `sshPassword` key. |
| DT-SEC-10 | Same for `ngrokAuthToken` | Column ciphertext; `ngrokAuthTokenSet: true`. |
| DT-SEC-11 | `provider.update` with `sshPassword` absent / `null` / `""` / new value | unchanged / NULL / NULL / new ciphertext; `sshPasswordSet` follows. |
| DT-SEC-12 | DB row with plaintext `legacyPass` in `sshPassword` (pre-vault) | Read yields `legacyPass`, `sshPasswordSet: true`; row not rewritten on read; rewritten encrypted on next provider update. |
| DT-SEC-13 | DB row with a ciphertext produced under a different key | Read yields unset (`sshPasswordSet: false`), WARN logged without the value; `service.preflight` reports `ssh.password` `SSH password is required.`; no askpass script is ever created from the ciphertext and ssh is never given the ciphertext as a password. |
| DT-SEC-14 | Make the vault fail (key file unreadable) then `service.create` with a provider holding a password | Call fails with `KUMA_SEC_KEY_FILE_ACCESS`; no service/provider rows were written; no plaintext anywhere on disk. |
| DT-SEC-15 | Service with SSH password; `data.export_service_json` and `data.export` | Output JSON does not contain the plaintext; `providers[].sshPassword` decrypts to it; two exports produce different ciphertext for the same password. |
| DT-SEC-16 | Kubeconfig `Prod` pasted YAML; provider references it; `data.export` scope service | `kubeConfigs[].encryptedConfigContent` equals the DB ciphertext byte-for-byte and does not contain `apiVersion:`; default kubeconfig never listed. |
| DT-SEC-17 | Import a backup with `kubeConfigs[]` entries: (cipher only), (path only), (neither), (default id) | stored `configContent` = cipher / `""` / skipped / skipped; `sourceFilePath` = NULL / path; `Imported` name default; existing row keeps `createdAt`. |
| DT-SEC-18 | Import a backup whose provider secrets are ciphertext from another key and a plaintext (hand-edited) one | ciphertext one is dropped with a warning in the import result; plaintext one is stored re-encrypted. |
| DT-SEC-19 | `kubeconfig.create` file mode with an existing path | `configContent` column decrypts to `""`, `sourceFilePath` is the raw trimmed path; `hasContent: false`. Pasted mode: decrypts to the trimmed YAML, `sourceFilePath` NULL, `hasContent: true`. |
| DT-SEC-20 | Start a service using a stored pasted kubeconfig | `<data dir>/kubeconfigs/<UPPERCASE UUID>.yaml` exists with mode `0600` in a `0700` dir; content equals trimmed YAML; after `kubeconfig.delete` the file is gone; an orphan file is removed at next daemon start; after `data.factory_reset` the dir is gone and `master.key` remains. |
| DT-SEC-21 | SSH password `p$a\b"c`d'e` | Askpass script run in `/bin/sh` prints exactly the password plus `\n`; dir `0700`, file `0700`; env has `SSH_ASKPASS`, `SSH_ASKPASS_REQUIRE=force`, `DISPLAY=kuma:0`; password absent from argv and from the environment variables other than via the script. |
| DT-SEC-22 | Start SSH service, then kill ssh externally (no `service.stop`); separately fail a start with a port conflict; separately shut the daemon down | In all three cases the askpass directory no longer exists afterwards. Leftover dir planted before daemon start is swept. |
| DT-SEC-23 | `kubeconfig.test_connection` with a stub kubectl | During the call a `kuma-chk-*.yaml` (`0600`) exists in `<runtime dir>/tmp`; after success, failure, spawn failure and cancellation it is gone. |
| DT-SEC-24 | Value `vault:abc` as SSH password, as ngrok token, and as key path | password and token used verbatim; key path -> `Execution failed: Failed to decrypt SSH key path: The encrypted payload format is invalid (expected nonce:tag:ciphertext).` |
| DT-SEC-25 | Start daemon with runtime dir `0755` and data dir `0755` | Both become `0700` with a WARN; socket mode `0600`; `kuma.sqlite`, `daemon-state.sqlite`, `master.key` end at `0600`. Runtime dir owned by another uid -> start refused with `KUMA_SEC_RUNTIME_DIR_INSECURE`. |
| DT-SEC-26 | Connect to the socket from a process with another uid (via `sudo -u` test user, or a mocked `peer_cred`) and as root | Connection closed with no reply bytes; audit entry `kind:"auth"`, `reason:"peer-uid"`. Same uid connects normally. |
| DT-SEC-27 | REST on `127.0.0.1`; configure bind `0.0.0.0` | Startup refused with `KUMA_SEC_REST_BIND_FORBIDDEN`. |
| DT-SEC-28 | REST requests: no header, wrong token, right token; token in `?token=`; `Host: evil.example`; `Host: localhost:<port>` OK; `Origin: http://evil.example`; `OPTIONS` | 401 `KUMA_SEC_TOKEN_MISSING`; 401 `KUMA_SEC_TOKEN_INVALID` after ~250 ms; 200; query token ignored (401); 403 `KUMA_SEC_HOST_FORBIDDEN` (before token check); 200; 403 `KUMA_SEC_ORIGIN_FORBIDDEN`; 403; no `Access-Control-*` header ever present; `Cache-Control: no-store` present. |
| DT-SEC-29 | `api-token` created at first REST start | 64 lowercase hex chars + `\n`, mode `0600`; loosening to `0644` is repaired; symlink or foreign owner refuses REST start; token string absent from every log, event and RPC result. |
| DT-SEC-30 | Rotate via `daemon.rotate_api_token` then via manual file replacement, with an open WebSocket | Old token -> 401 immediately after rotation; open WS closed with 1008; result has `tokenPath` and no token; audit `token.rotated`; manual replacement effective without restart. |
| DT-SEC-31 | `provider.list` with default params on socket, REST, MCP | No `sshPassword`/`ngrokAuthToken` keys; booleans present; `kubeconfig.get` has `hasContent` and no `configContent`. |
| DT-SEC-32 | `revealSecrets: true` on socket (kind cli), on socket (kind mcp), on REST, via MCP tool | plaintext fields present only in the first; `KUMA_SEC_REVEAL_FORBIDDEN` in the others; audit `reveal` true for the honored call. |
| DT-SEC-33 | MCP `data.export` tool result | `sshPassword`, `ngrokAuthToken`, `encryptedConfigContent` keys absent; masked booleans present. |
| DT-SEC-34 | Run the 3.12.1 example table through `redact(strict)`; run a second pass | Outputs match exactly; second pass is identity. A 5 MiB line without matches returns in linear time (< 200 ms). |
| DT-SEC-35 | Service with ngrok token started; read `runtime_process.argvJSON` and `daemon.status` | Persisted argv has `--authtoken` followed by `***`; no token anywhere in `daemon-state.sqlite` (scan the file bytes); adoption of the live process still matches via redacted comparison. |
| DT-SEC-36 | Provider with compose output containing the SSH password as a known value, and `Start failed:` error text containing the ngrok token | Activity log lines, `service.log_line` events and RPC error messages show `***`. Workload line `token=abc` (R7, strict only) stays as is under the `workload` profile, while a PEM block and a known value in workload output are redacted. |
| DT-SEC-37 | Perform each mutating call once, plus `provider.list` with reveal, plus one rejected peer | Exactly one audit line each; `refs` only whitelisted keys; scan `audit.log` bytes: no password, token, kubeconfig text, argv, free text; file `0600`; rotation at 5 MiB keeps `.1`..`.3`. |
| DT-SEC-38 | Entitlements parity check of the shipped daemon (if signed) | `codesign -d --entitlements -` shows none of the three `cs.*` exception entitlements; `codesign -d --verbose` shows `runtime` flag when distribution-signed. |
| DT-SEC-39 | Spool and ephemeral compose files | Spool files `0600` in `0700` dir; ephemeral compose file `0600`. |
| DT-SEC-40 | Daemon process | `RLIMIT_CORE` is 0 at runtime; children do not have `KUMA_API_TOKEN`-like variables; none exist in the daemon environment. |

---

## Proposed RPC additions

| Name | Params | Result | Rationale |
|------|--------|--------|-----------|
| `daemon.rotate_api_token` | `{}` (socket transport, kind `cli`/`app` only) | `{ "tokenPath": string, "rotatedAt": string (ISO-8601) }` | ADD-31 rotation without restart. The token is not returned; clients read the `0600` file. Refused on REST/MCP and on `mcp`/`rest` connection kinds with `KUMA_SEC_LOCAL_ONLY`. |
| `daemon.ping` (extension, not a new method) | optional param `clientKind`: `"cli"`, `"app"`, `"mcp"`, or `"rest"` | unchanged plus echo `clientKind` | Marks the connection kind used by the `revealSecrets` rules (3.11) and audit attribution. Default when absent: `cli`. A connection that has once declared `mcp` or `rest` cannot later change to a more privileged kind. |
| `revealSecrets` (parameter on existing methods) | boolean, default `false`, on `provider.list`, `provider.add`, `provider.update`, `service.get`, `service.list`, `kubeconfig.list`, `kubeconfig.get`, `kubeconfig.create`, `kubeconfig.update` | adds plaintext secret fields (3.11) | Spec 10 must add it to those schemas; no new method. |
| (response fields) `sshPasswordSet`, `ngrokAuthTokenSet`, `hasContent` | - | booleans (3.11) | Spec 10 must add them to Provider and KubeConfig wire schemas, and remove `sshPassword`, `ngrokAuthToken`, `configContent` from default results. |

---

## Open questions / residual risks

1. **Base64 leniency of `Data(base64Encoded:)`.** 1.x only emits padded standard base64, so decoding of 1.x output is fully specified. How Foundation treats unpadded or whitespace-containing components was not testable here; the daemon accepts unpadded input (superset) and rejects in-string whitespace. This cannot reject any payload 1.x produced.
2. **Nonce/tag size tolerance of CryptoKit.** 1.x always generates 12/16 bytes; the daemon requires exactly those and reports `payloadCorrupted` otherwise (1.x also maps any construction failure to `payloadCorrupted`). A hand-crafted payload with other sizes that CryptoKit might accept would be rejected by the daemon; no such payload can come from Kuma.
3. **Known-answer vectors were generated outside Swift** (independent AES-GCM implementation) because no Swift toolchain run was used; the primitive is standard, but acceptance step 3.2.6 B (real 1.x capture) remains the authoritative gate.
4. **ngrok token in argv is visible via `ps` to every local user** (parity, FEAT-SEC-16). Passing it by environment (`NGROK_AUTHTOKEN`) would hide it from other users but changes the argv contract tested in [06](06-execution-engine.md) and depends on ngrok agent versions; not changed. Same-uid processes can read it either way.
5. **Same-uid attackers are out of scope**: any process of the same user can read `master.key`, `kuma.sqlite`, the api token and the materialized kubeconfigs. The vault protects backups, copied databases and casual disclosure, not an attacker already running as the user. `connectionKind` is a safety rail, not a boundary.
6. **Plaintext-by-design fields** (compose YAML, scripts, URLs) remain unencrypted in DB and backups for compatibility (3.3). The redaction function covers echoing, not storage.
7. **Backups are machine-bound**: ciphertexts in a backup only decrypt on a machine with the same `master.key`. Cross-machine restore loses provider secrets (reported as warnings, DEV-37) and kubeconfig inline content (error at start). 1.x silently used the ciphertext as the password. No portable (passphrase) export format exists in 1.x or here.
8. **Hardened runtime of 1.x** is applied only by the optional signing script, not by the Xcode project; whether a given release was hardened depends on maintainer secrets. The daemon has no dependency on that.
9. **`sshKeyPath` `vault:` semantics** are inferred (no 1.x code writes such values); DEV-37(c) chooses "strip prefix then decrypt".
10. **Redaction heuristics** (R1-R7) are best-effort pattern matching; R8 (known values) is the only exact guarantee, and applies only to secrets the daemon has decrypted.
