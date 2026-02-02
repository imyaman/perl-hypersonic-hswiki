const app = {
    // API base URL - change for production
    apiBase: '/api',

    // Current state
    currentUser: null,
    currentSpace: null,
    currentPage: null,
    editingPage: null,

    // Initialize
    init() {
        this.checkAuth().then(() => {
            // Handle initial route based on URL
            this.handleRoute();
        });

        // Handle browser back/forward
        window.addEventListener('popstate', () => this.handleRoute());
    },

    // URL Routing
    navigate(path, pushState = true) {
        if (pushState) {
            history.pushState(null, '', path);
        }
        this.handleRoute();
    },

    handleRoute() {
        const path = window.location.pathname;
        const parts = path.split('/').filter(p => p);

        // Route: / - Spaces list
        if (parts.length === 0) {
            this.showSpaces(false);
            return;
        }

        // Route: /login
        if (parts[0] === 'login') {
            this.showLogin(false);
            return;
        }

        // Route: /register
        if (parts[0] === 'register') {
            this.showRegister(false);
            return;
        }

        // Route: /:space_key
        if (parts.length === 1) {
            this.showSpace(parts[0], false);
            return;
        }

        // Route: /:space_key/new - Create page
        if (parts.length === 2 && parts[1] === 'new') {
            this.currentSpace = parts[0];
            this.showCreatePage(null, false);
            return;
        }

        // Route: /:space_key/:slug
        if (parts.length === 2) {
            this.currentSpace = parts[0];
            this.showPage(parts[1], false);
            return;
        }

        // Route: /:space_key/:slug/edit
        if (parts.length === 3 && parts[2] === 'edit') {
            this.currentSpace = parts[0];
            this.currentPage = parts[1];
            this.editPageByUrl();
            return;
        }

        // Route: /:space_key/:slug/versions
        if (parts.length === 3 && parts[2] === 'versions') {
            this.currentSpace = parts[0];
            this.currentPage = parts[1];
            this.showVersions(false);
            return;
        }

        // Default: show spaces
        this.showSpaces(false);
    },

    // API Helper
    async api(endpoint, options = {}) {
        const url = this.apiBase + endpoint;
        const config = {
            credentials: 'include',
            headers: {
                'Content-Type': 'application/json',
                ...options.headers
            },
            ...options
        };

        if (options.body && typeof options.body === 'object') {
            config.body = JSON.stringify(options.body);
        }

        try {
            const response = await fetch(url, config);
            const data = await response.json();

            if (!response.ok) {
                throw new Error(data.error || data.message || 'Request failed');
            }

            return data;
        } catch (error) {
            if (error.message === 'Failed to fetch') {
                throw new Error('Network error - please check your connection');
            }
            throw error;
        }
    },

    // UI Helpers
    showSection(sectionId) {
        const sections = document.querySelectorAll('main > section');
        sections.forEach(s => s.style.display = 'none');

        const section = document.getElementById(sectionId);
        if (section) {
            section.style.display = 'block';
        }
    },

    showError(message) {
        const el = document.getElementById('error-message');
        el.textContent = message;
        el.style.display = 'block';
        setTimeout(() => el.style.display = 'none', 5000);
    },

    showSuccess(message) {
        const el = document.getElementById('success-message');
        el.textContent = message;
        el.style.display = 'block';
        setTimeout(() => el.style.display = 'none', 3000);
    },

    showLoading(show) {
        document.getElementById('loading').style.display = show ? 'block' : 'none';
    },

    updateNav() {
        const navUser = document.getElementById('nav-user');
        const navGuest = document.getElementById('nav-guest');
        const usernameDisplay = document.getElementById('username-display');

        if (this.currentUser) {
            navUser.style.display = 'inline';
            navGuest.style.display = 'none';
            usernameDisplay.textContent = this.currentUser.username;
        } else {
            navUser.style.display = 'none';
            navGuest.style.display = 'inline';
        }
    },

    // Auth
    async checkAuth() {
        try {
            const data = await this.api('/auth/me');
            this.currentUser = data.user;
            this.updateNav();
        } catch (error) {
            this.currentUser = null;
            this.updateNav();
        }
    },

    showLogin(updateUrl = true) {
        if (updateUrl) this.navigate('/login', true);
        else {
            this.showSection('login-section');
            document.getElementById('login-form').reset();
        }
    },

    showRegister(updateUrl = true) {
        if (updateUrl) this.navigate('/register', true);
        else {
            this.showSection('register-section');
            document.getElementById('register-form').reset();
        }
    },

    async login(event) {
        event.preventDefault();

        const username = document.getElementById('login-username').value;
        const password = document.getElementById('login-password').value;

        try {
            const data = await this.api('/auth/login', {
                method: 'POST',
                body: { username, password }
            });

            this.currentUser = data.user;
            this.updateNav();
            this.showSuccess('Login successful!');
            this.navigate('/');
        } catch (error) {
            this.showError(error.message);
        }

        return false;
    },

    async register(event) {
        event.preventDefault();

        const username = document.getElementById('reg-username').value;
        const email = document.getElementById('reg-email').value;
        const password = document.getElementById('reg-password').value;

        try {
            const data = await this.api('/auth/register', {
                method: 'POST',
                body: { username, email, password }
            });

            this.currentUser = data.user;
            this.updateNav();
            this.showSuccess('Registration successful!');
            this.navigate('/');
        } catch (error) {
            this.showError(error.message);
        }

        return false;
    },

    async logout() {
        try {
            await this.api('/auth/logout', { method: 'POST' });
        } catch (error) {
            // Ignore errors
        }

        this.currentUser = null;
        this.updateNav();
        this.navigate('/');
    },

    // Spaces
    async showSpaces(updateUrl = true) {
        if (updateUrl) {
            this.navigate('/', true);
            return;
        }

        this.currentSpace = null;
        this.currentPage = null;
        this.showSection('spaces-section');
        this.showLoading(true);

        const createBtn = document.getElementById('create-space-btn');
        createBtn.style.display = this.currentUser ? 'inline-block' : 'none';

        try {
            const data = await this.api('/spaces');
            this.renderSpacesList(data.spaces);
        } catch (error) {
            this.showError(error.message);
        } finally {
            this.showLoading(false);
        }
    },

    renderSpacesList(spaces) {
        const container = document.getElementById('spaces-list');

        if (!spaces || spaces.length === 0) {
            container.innerHTML = `
                <div class="empty-state">
                    <p>No spaces found.</p>
                    ${this.currentUser ? '<p>Create your first space to get started!</p>' : '<p>Login to create spaces.</p>'}
                </div>
            `;
            return;
        }

        container.innerHTML = spaces.map(space => `
            <div class="card">
                <h3><a href="/${space.space_key}">${this.escapeHtml(space.name)}</a></h3>
                <p>${this.escapeHtml(space.description || '')}</p>
                <div class="card-meta">
                    ${space.is_public ? 'Public' : 'Private'}
                </div>
            </div>
        `).join('');
    },

    showCreateSpace() {
        if (!this.currentUser) {
            this.showLogin();
            return;
        }
        this.showSection('create-space-section');
        document.getElementById('create-space-form').reset();
    },

    async createSpace(event) {
        event.preventDefault();

        const name = document.getElementById('space-name').value;
        const description = document.getElementById('space-description').value;
        const is_public = document.getElementById('space-public').checked;

        try {
            const data = await this.api('/spaces', {
                method: 'POST',
                body: { name, description, is_public }
            });

            this.showSuccess('Space created!');
            this.navigate(`/${data.space.space_key}`);
        } catch (error) {
            this.showError(error.message);
        }

        return false;
    },

    async showSpace(spaceKey, updateUrl = true) {
        if (updateUrl) {
            this.navigate(`/${spaceKey}`, true);
            return;
        }

        this.currentSpace = spaceKey;
        this.currentPage = null;
        this.showSection('space-section');
        this.showLoading(true);

        const createBtn = document.getElementById('create-page-btn');
        createBtn.style.display = this.currentUser ? 'inline-block' : 'none';

        try {
            const spaceData = await this.api(`/spaces/${spaceKey}`);
            const pagesData = await this.api(`/pages/list/${spaceKey}`);

            document.getElementById('space-name-breadcrumb').textContent = spaceData.space.name;
            document.getElementById('space-title').textContent = spaceData.space.name;
            document.getElementById('space-description-text').textContent = spaceData.space.description || '';

            this.renderPagesList(pagesData.pages);
        } catch (error) {
            this.showError(error.message);
        } finally {
            this.showLoading(false);
        }
    },

    renderPagesList(pages) {
        const container = document.getElementById('pages-list');

        if (!pages || pages.length === 0) {
            container.innerHTML = `
                <div class="empty-state">
                    <p>No pages in this space yet.</p>
                    ${this.currentUser ? '<p>Create your first page!</p>' : ''}
                </div>
            `;
            return;
        }

        container.innerHTML = pages.map(page => `
            <div class="card">
                <h3><a href="/${this.currentSpace}/${page.slug}">${this.escapeHtml(page.title)}</a></h3>
                <div class="card-meta">
                    Version ${page.version} &bull; Updated ${this.formatDate(page.updated_at)}
                </div>
            </div>
        `).join('');
    },

    // Pages
    showCreatePage(prefillTitle = null, updateUrl = true) {
        if (!this.currentUser) {
            this.showLogin();
            return;
        }

        if (updateUrl) {
            this.navigate(`/${this.currentSpace}/new`, true);
            return;
        }

        this.editingPage = null;
        this.showSection('edit-page-section');

        document.getElementById('edit-space-breadcrumb').textContent = this.currentSpace;
        document.getElementById('edit-page-breadcrumb').textContent = 'New Page';
        document.getElementById('edit-page-title').textContent = 'Create Page';
        document.getElementById('edit-page-form').reset();
        document.getElementById('preview-area').style.display = 'none';

        // Pre-fill title if provided (e.g., from clicking a missing wiki link)
        if (prefillTitle) {
            document.getElementById('page-title').value = prefillTitle;
        }
    },

    async showPage(slug, updateUrl = true) {
        if (updateUrl) {
            this.navigate(`/${this.currentSpace}/${slug}`, true);
            return;
        }

        this.currentPage = slug;
        this.showSection('page-section');
        this.showLoading(true);

        const actionsEl = document.getElementById('page-actions');
        actionsEl.style.display = this.currentUser ? 'flex' : 'none';

        try {
            const data = await this.api(`/pages/view/${this.currentSpace}/${slug}`);
            const page = data.page;

            document.getElementById('page-space-breadcrumb').textContent = this.currentSpace;
            document.getElementById('page-title-breadcrumb').textContent = page.title;
            document.getElementById('page-title-display').textContent = page.title;
            document.getElementById('page-version').textContent = page.version;
            document.getElementById('page-updated').textContent = this.formatDate(page.updated_at);
            document.getElementById('page-content-display').innerHTML = page.content_html || '<p>No content</p>';
        } catch (error) {
            this.showError(error.message);
        } finally {
            this.showLoading(false);
        }
    },

    editPage() {
        if (!this.currentUser) {
            this.showLogin();
            return;
        }
        this.navigate(`/${this.currentSpace}/${this.currentPage}/edit`);
    },

    async editPageByUrl() {
        this.showLoading(true);

        try {
            const data = await this.api(`/pages/view/${this.currentSpace}/${this.currentPage}`);
            const page = data.page;

            this.editingPage = page;
            this.showSection('edit-page-section');

            document.getElementById('edit-space-breadcrumb').textContent = this.currentSpace;
            document.getElementById('edit-page-breadcrumb').textContent = page.title;
            document.getElementById('edit-page-title').textContent = 'Edit Page';
            document.getElementById('page-title').value = page.title;
            document.getElementById('page-content').value = page.content || '';
            document.getElementById('preview-area').style.display = 'none';
        } catch (error) {
            this.showError(error.message);
        } finally {
            this.showLoading(false);
        }
    },

    async savePage(event) {
        event.preventDefault();

        const title = document.getElementById('page-title').value;
        const content = document.getElementById('page-content').value;

        try {
            if (this.editingPage) {
                // Update existing page
                await this.api(`/pages/edit/${this.currentSpace}/${this.editingPage.slug}`, {
                    method: 'PUT',
                    body: { title, content }
                });
                this.showSuccess('Page updated!');
                this.navigate(`/${this.currentSpace}/${this.editingPage.slug}`);
            } else {
                // Create new page
                const data = await this.api(`/pages/create/${this.currentSpace}`, {
                    method: 'POST',
                    body: { title, content }
                });
                this.showSuccess('Page created!');
                this.navigate(`/${this.currentSpace}/${data.page.slug}`);
            }
        } catch (error) {
            this.showError(error.message);
        }

        return false;
    },

    async previewPage() {
        const content = document.getElementById('page-content').value;
        const previewArea = document.getElementById('preview-area');
        const previewContent = document.getElementById('preview-content');

        try {
            const data = await this.api('/render', {
                method: 'POST',
                body: { content }
            });
            previewContent.innerHTML = data.html || '<p>No content</p>';
            previewArea.style.display = 'block';
        } catch (error) {
            this.showError(error.message);
        }
    },

    cancelEdit() {
        if (this.editingPage) {
            this.navigate(`/${this.currentSpace}/${this.editingPage.slug}`);
        } else {
            this.navigate(`/${this.currentSpace}`);
        }
    },

    // Versions
    async showVersions(updateUrl = true) {
        if (updateUrl) {
            this.navigate(`/${this.currentSpace}/${this.currentPage}/versions`, true);
            return;
        }

        this.showSection('versions-section');
        this.showLoading(true);

        try {
            const data = await this.api(`/pages/versions/${this.currentSpace}/${this.currentPage}`);

            document.getElementById('versions-space-breadcrumb').textContent = this.currentSpace;
            document.getElementById('versions-page-breadcrumb').textContent = this.currentPage;

            this.renderVersionsList(data.versions);
        } catch (error) {
            this.showError(error.message);
        } finally {
            this.showLoading(false);
        }
    },

    renderVersionsList(versions) {
        const container = document.getElementById('versions-list');

        if (!versions || versions.length === 0) {
            container.innerHTML = '<div class="empty-state"><p>No version history available.</p></div>';
            return;
        }

        container.innerHTML = versions.map(v => `
            <div class="version-item">
                <div class="version-info">
                    <span class="version-number">Version ${v.version}</span>
                    <span class="version-date">${this.formatDate(v.created_at)}</span>
                    ${v.change_summary ? `<div class="version-summary">${this.escapeHtml(v.change_summary)}</div>` : ''}
                </div>
                <button class="btn" onclick="app.viewVersion(${v.version})">View</button>
            </div>
        `).join('');
    },

    async viewVersion(version) {
        try {
            const data = await this.api(`/pages/version/${this.currentSpace}/${this.currentPage}/${version}`);
            // For now, just show in the page view
            document.getElementById('page-content-display').innerHTML = data.version.content_html || data.version.content || '<p>No content</p>';
            document.getElementById('page-version').textContent = version + ' (historical)';
            this.showSection('page-section');
        } catch (error) {
            this.showError(error.message);
        }
    },

    // Helpers
    escapeHtml(text) {
        if (!text) return '';
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    },

    formatDate(timestamp) {
        if (!timestamp) return 'Unknown';
        const date = new Date(typeof timestamp === 'number' ? timestamp : parseInt(timestamp));
        return date.toLocaleDateString() + ' ' + date.toLocaleTimeString();
    }
};

// Initialize on load
document.addEventListener('DOMContentLoaded', () => {
    app.init();

    // Handle all link clicks for SPA navigation
    document.addEventListener('click', (e) => {
        const link = e.target.closest('a');
        if (!link) return;

        // Handle wiki links (missing pages go to create)
        if (link.classList.contains('wiki-link')) {
            e.preventDefault();
            if (link.classList.contains('wiki-link-missing')) {
                const suggestedTitle = link.textContent;
                // Navigate to create page with title in URL
                app.navigate(`/${app.currentSpace}/new`);
                // Set title after navigation
                setTimeout(() => {
                    document.getElementById('page-title').value = suggestedTitle;
                }, 100);
            } else {
                app.navigate(`/${app.currentSpace}/${link.dataset.slug}`);
            }
            return;
        }

        // Handle internal links (same origin, not external)
        const href = link.getAttribute('href');
        if (href && href.startsWith('/') && !href.startsWith('//')) {
            e.preventDefault();
            app.navigate(href);
        }
    });
});
