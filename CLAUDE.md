1. Project Overview
   - Build a wiki system using Perl + Hypersonic, with Cassandra as the backend.
   - Core features: user registration/login, role‑based access, space/page management, admin controls.

2. Initial Setup Steps
   - Create ./hswiki directory if it doesn't exist.
   - Copy hs_hello.pl to ./hswiki/app.pl

3. Directory & File Planning
   - Create structure.md documenting the intended file layout (controllers, models, views, config).
   - Define DB schema in schema.md for Cassandra keyspace `claude-hswiki`.

4. Key Development Areas
   - Authentication – routes for login, logout, registration; password hashing; session handling.
   - Roles & Permissions – admin role, role‑based page/space access control.
   - Space & Page Management – CRUD operations, wiki markup rendering via Text::WikiFormat.
   - Cassandra Integration – wrapper module using Cassandra::Client for all data persistence.
   - API for web client will be under /api
   - API for other system will be under /openapi

5. Testing & Validation
   - Write unit tests for each controller/model.
   - Verify Cassandra queries with the sample scripts (sample/cassandra_example_execute.pl, sample/cassandra_example_eachpage.pl).
   - Local development: `http://localhost:5207`
   - Production: `https://hswiki.sys5.co`
   - Example: `http://localhost:5207/api/hello` becomes `https://hswiki.sys5.co/api/hello` in production.

6. Running the App
   - Start with: `perl app.pl` inside the hswiki directory.
   - For local testing with single worker: `HSWIKI_WORKERS=1 perl app.pl`

7. Web Frontend
   - Static files located in `hswiki-web/` directory
   - Files map to production URLs:
     - `hswiki-web/index.html` → `https://hswiki.sys5.co/index.html`
     - `hswiki-web/css/style.css` → `https://hswiki.sys5.co/css/style.css`
     - `hswiki-web/js/app.js` → `https://hswiki.sys5.co/js/app.js`
   - API calls use relative paths (`/api/*`) so frontend works in both local and production

8. URL Routing (SPA)
   - Every page has a unique, permanent, bookmarkable URL
   - URL structure:
     - `/` – Spaces list (home)
     - `/login` – Login page
     - `/register` – Register page
     - `/:space_key` – Space detail (list of pages)
     - `/:space_key/new` – Create new page
     - `/:space_key/:slug` – View page
     - `/:space_key/:slug/edit` – Edit page
     - `/:space_key/:slug/versions` – Version history
   - Web server must serve `index.html` for all routes (SPA fallback)
   - Browser back/forward navigation supported via History API
