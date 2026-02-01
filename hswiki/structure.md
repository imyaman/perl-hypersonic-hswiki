# HSWiki Directory Structure

```
hswiki/
├── app.pl                          # Main application entry point
├── structure.md                    # This file - directory layout documentation
├── schema.md                       # Cassandra schema definitions
│
├── lib/HSWiki/
│   ├── Config.pm                   # Application configuration
│   ├── DB.pm                       # Cassandra::Client wrapper
│   ├── Auth.pm                     # Password hashing, token generation
│   ├── Wiki.pm                     # Text::WikiFormat rendering
│   │
│   ├── Controller/
│   │   ├── Auth.pm                 # /api/auth/* routes
│   │   ├── Space.pm                # /api/spaces/* routes
│   │   ├── Page.pm                 # /api/spaces/:key/pages/* routes
│   │   ├── Admin.pm                # /api/admin/* routes
│   │   └── OpenAPI.pm              # /openapi/* routes (external API)
│   │
│   ├── Model/
│   │   ├── User.pm                 # User entity operations
│   │   ├── Role.pm                 # Role entity operations
│   │   ├── Space.pm                # Space entity operations
│   │   └── Page.pm                 # Page entity operations
│   │
│   └── Middleware/
│       ├── Auth.pm                 # Session validation middleware
│       └── RBAC.pm                 # Role-based access control middleware
│
└── t/                              # Unit tests
    ├── 00-config.t
    ├── 01-db.t
    ├── 02-auth.t
    ├── 03-model-user.t
    ├── 04-model-role.t
    ├── 05-model-space.t
    ├── 06-model-page.t
    ├── 10-controller-auth.t
    ├── 11-controller-space.t
    ├── 12-controller-page.t
    ├── 13-controller-admin.t
    └── 14-controller-openapi.t
```

## Module Responsibilities

### Core Modules

- **Config.pm**: Centralizes all configuration (Cassandra hosts, session secrets, etc.)
- **DB.pm**: Wraps Cassandra::Client with connection management and helper methods
- **Auth.pm**: Handles password hashing (Argon2) and session token management
- **Wiki.pm**: Renders wiki markup to HTML using Text::WikiFormat

### Controllers

- **Controller::Auth**: User registration, login, logout, session management
- **Controller::Space**: Wiki space CRUD operations
- **Controller::Page**: Wiki page CRUD, version history
- **Controller::Admin**: User management, role assignment (admin only)
- **Controller::OpenAPI**: External API with API key authentication

### Models

- **Model::User**: User CRUD, lookup by username/email
- **Model::Role**: Role management, default roles (admin, editor, viewer)
- **Model::Space**: Space CRUD, permission management
- **Model::Page**: Page CRUD, version control

### Middleware

- **Middleware::Auth**: Validates session, populates $req with user info
- **Middleware::RBAC**: Checks permissions for protected routes
