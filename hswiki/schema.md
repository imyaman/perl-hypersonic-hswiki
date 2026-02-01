# HSWiki Cassandra Schema

**Keyspace:** `claude_hswiki`

## Keyspace Creation

```cql
CREATE KEYSPACE IF NOT EXISTS claude_hswiki
WITH replication = {
    'class': 'NetworkTopologyStrategy',
    'datacenter1': 3
};

USE claude_hswiki;
```

## Tables

### Users

```cql
-- Primary user table
CREATE TABLE IF NOT EXISTS users (
    user_id UUID PRIMARY KEY,
    username TEXT,
    email TEXT,
    password_hash TEXT,
    role_id UUID,
    api_key TEXT,
    is_active BOOLEAN,
    created_at TIMESTAMP,
    updated_at TIMESTAMP
);

-- Lookup by username (for login)
CREATE TABLE IF NOT EXISTS users_by_username (
    username TEXT PRIMARY KEY,
    user_id UUID,
    password_hash TEXT,
    role_id UUID,
    is_active BOOLEAN
);

-- Lookup by email (for registration check)
CREATE TABLE IF NOT EXISTS users_by_email (
    email TEXT PRIMARY KEY,
    user_id UUID
);

-- Lookup by API key (for OpenAPI auth)
CREATE TABLE IF NOT EXISTS users_by_api_key (
    api_key TEXT PRIMARY KEY,
    user_id UUID,
    is_active BOOLEAN
);
```

### Roles

```cql
-- Role definitions
CREATE TABLE IF NOT EXISTS roles (
    role_id UUID PRIMARY KEY,
    role_name TEXT,
    permissions SET<TEXT>,
    description TEXT,
    created_at TIMESTAMP
);

-- Lookup by name
CREATE TABLE IF NOT EXISTS roles_by_name (
    role_name TEXT PRIMARY KEY,
    role_id UUID,
    permissions SET<TEXT>
);
```

### Spaces

```cql
-- Wiki spaces
CREATE TABLE IF NOT EXISTS spaces (
    space_id UUID PRIMARY KEY,
    space_key TEXT,
    name TEXT,
    description TEXT,
    is_public BOOLEAN,
    owner_id UUID,
    created_at TIMESTAMP,
    updated_at TIMESTAMP
);

-- Lookup by key
CREATE TABLE IF NOT EXISTS spaces_by_key (
    space_key TEXT PRIMARY KEY,
    space_id UUID,
    name TEXT,
    description TEXT,
    is_public BOOLEAN,
    owner_id UUID
);

-- Space permissions (who can access what)
CREATE TABLE IF NOT EXISTS space_permissions (
    space_id UUID,
    user_id UUID,
    permission TEXT,  -- 'read', 'write', 'admin'
    granted_at TIMESTAMP,
    PRIMARY KEY (space_id, user_id)
);

-- User's spaces (for listing user's spaces)
CREATE TABLE IF NOT EXISTS user_spaces (
    user_id UUID,
    space_id UUID,
    permission TEXT,
    space_key TEXT,
    space_name TEXT,
    PRIMARY KEY (user_id, space_id)
);
```

### Pages

```cql
-- Wiki pages
CREATE TABLE IF NOT EXISTS pages (
    space_id UUID,
    page_id UUID,
    slug TEXT,
    title TEXT,
    content TEXT,
    content_html TEXT,
    author_id UUID,
    version INT,
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    PRIMARY KEY (space_id, page_id)
);

-- Lookup by slug within space
CREATE TABLE IF NOT EXISTS pages_by_slug (
    space_id UUID,
    page_slug TEXT,
    page_id UUID,
    title TEXT,
    version INT,
    updated_at TIMESTAMP,
    PRIMARY KEY (space_id, page_slug)
);

-- Page version history
CREATE TABLE IF NOT EXISTS page_versions (
    page_id UUID,
    version INT,
    title TEXT,
    content TEXT,
    content_html TEXT,
    author_id UUID,
    created_at TIMESTAMP,
    change_summary TEXT,
    PRIMARY KEY (page_id, version)
) WITH CLUSTERING ORDER BY (version DESC);
```

### Sessions (optional - for server-side session storage)

```cql
-- Session store (alternative to in-memory)
CREATE TABLE IF NOT EXISTS sessions (
    session_id TEXT PRIMARY KEY,
    user_id UUID,
    data TEXT,  -- JSON serialized session data
    created_at TIMESTAMP,
    expires_at TIMESTAMP
) WITH default_time_to_live = 86400;  -- 1 day TTL
```

## Default Data

### Default Roles

```cql
-- Admin role (full access)
INSERT INTO roles (role_id, role_name, permissions, description, created_at)
VALUES (
    uuid(),
    'admin',
    {'user:read', 'user:write', 'user:delete', 'role:manage',
     'space:read', 'space:write', 'space:delete', 'space:admin',
     'page:read', 'page:write', 'page:delete'},
    'Administrator with full system access',
    toTimestamp(now())
);

INSERT INTO roles_by_name (role_name, role_id, permissions)
VALUES (
    'admin',
    <admin_role_id>,
    {'user:read', 'user:write', 'user:delete', 'role:manage',
     'space:read', 'space:write', 'space:delete', 'space:admin',
     'page:read', 'page:write', 'page:delete'}
);

-- Editor role (can edit pages)
INSERT INTO roles (role_id, role_name, permissions, description, created_at)
VALUES (
    uuid(),
    'editor',
    {'space:read', 'page:read', 'page:write'},
    'Can read spaces and edit pages',
    toTimestamp(now())
);

INSERT INTO roles_by_name (role_name, role_id, permissions)
VALUES (
    'editor',
    <editor_role_id>,
    {'space:read', 'page:read', 'page:write'}
);

-- Viewer role (read-only)
INSERT INTO roles (role_id, role_name, permissions, description, created_at)
VALUES (
    uuid(),
    'viewer',
    {'space:read', 'page:read'},
    'Read-only access to spaces and pages',
    toTimestamp(now())
);

INSERT INTO roles_by_name (role_name, role_id, permissions)
VALUES (
    'viewer',
    <viewer_role_id>,
    {'space:read', 'page:read'}
);
```

## Indexes (if needed)

```cql
-- Secondary index for finding active users
CREATE INDEX IF NOT EXISTS idx_users_active ON users (is_active);

-- Secondary index for public spaces
CREATE INDEX IF NOT EXISTS idx_spaces_public ON spaces (is_public);
```

## Permission Model

### Role Permissions

| Permission | Description |
|------------|-------------|
| `user:read` | View user profiles |
| `user:write` | Edit user profiles |
| `user:delete` | Deactivate users |
| `role:manage` | Manage roles |
| `space:read` | View spaces |
| `space:write` | Create/edit spaces |
| `space:delete` | Delete spaces |
| `space:admin` | Manage space permissions |
| `page:read` | View pages |
| `page:write` | Create/edit pages |
| `page:delete` | Delete pages |

### Space Permissions

Per-space permissions override role permissions:
- `read` - Can view space and its pages
- `write` - Can edit pages in the space
- `admin` - Can manage space settings and permissions
