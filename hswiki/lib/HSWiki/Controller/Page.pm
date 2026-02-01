package HSWiki::Controller::Page;

use strict;
use warnings;


use Cpanel::JSON::XS ();
use HSWiki::Model::Page;
use HSWiki::Model::Space;
use HSWiki::Wiki;
use HSWiki::Middleware::Auth;
use HSWiki::Middleware::RBAC;
use Hypersonic::Response qw(res);

our $VERSION = '0.01';

# Register routes with the server
sub register {
    my ($class, $server) = @_;

    # NOTE: For Hypersonic, POST routes with same prefix need shorter paths first

    # POST /api/render - Render wiki markup (preview)
    $server->post('/api/render' => sub {
        my ($req) = @_;
        return $class->render_preview($req);
    }, { dynamic => 1, parse_json => 1 });

    # POST /api/spaces/:key/pages - Create page (MUST be before restore route)
    $server->post('/api/spaces/:key/pages' => HSWiki::Middleware::Auth->wrap(sub {
        my ($req) = @_;
        return $class->create($req);
    }), { dynamic => 1, parse_json => 1 });

    # POST /api/spaces/:key/pages/:slug/restore - Restore page to version
    $server->post('/api/spaces/:key/pages/:slug/restore' => HSWiki::Middleware::Auth->wrap(sub {
        my ($req) = @_;
        return $class->restore($req);
    }), { dynamic => 1, parse_json => 1 });

    # GET routes - SHORTER paths first for Hypersonic routing
    # GET /api/spaces/:key/pages - List pages in space (MUST be first)
    $server->get('/api/spaces/:key/pages' => HSWiki::Middleware::Auth->wrap(sub {
        my ($req) = @_;
        return $class->list($req);
    }, optional => 1), { dynamic => 1 });

    # GET /api/spaces/:key/pages/:slug - Get page
    $server->get('/api/spaces/:key/pages/:slug' => HSWiki::Middleware::Auth->wrap(sub {
        my ($req) = @_;
        return $class->get($req);
    }, optional => 1), { dynamic => 1 });

    # GET /api/spaces/:key/pages/:slug/versions - Get page version history
    $server->get('/api/spaces/:key/pages/:slug/versions' => HSWiki::Middleware::Auth->wrap(sub {
        my ($req) = @_;
        return $class->versions($req);
    }, optional => 1), { dynamic => 1 });

    # GET /api/spaces/:key/pages/:slug/versions/:version - Get specific version
    $server->get('/api/spaces/:key/pages/:slug/versions/:version' => HSWiki::Middleware::Auth->wrap(sub {
        my ($req) = @_;
        return $class->get_version($req);
    }, optional => 1), { dynamic => 1 });

    # PUT /api/spaces/:key/pages/:slug - Update page
    $server->put('/api/spaces/:key/pages/:slug' => HSWiki::Middleware::Auth->wrap(sub {
        my ($req) = @_;
        return $class->update($req);
    }), { dynamic => 1, parse_json => 1 });

    # DELETE /api/spaces/:key/pages/:slug - Delete page
    $server->del('/api/spaces/:key/pages/:slug' => HSWiki::Middleware::Auth->wrap(sub {
        my ($req) = @_;
        return $class->delete($req);
    }), { dynamic => 1 });
}

# Helper to get space and check access
sub _get_space {
    my ($class, $req) = @_;

    # Support both 'space_key' (new routes) and 'key' (legacy routes)
    my $space_key = $req->param('space_key') // $req->param('key');
    my $space = HSWiki::Model::Space->find_by_key($space_key);

    return (undef, res->not_found('Space not found')) unless $space;

    unless (HSWiki::Middleware::RBAC->can_access_space($req, $space->{space_id})) {
        return (undef, res->forbidden('Access denied to this space'));
    }

    return ($space, undef);
}

# List pages in space
sub list {
    my ($class, $req) = @_;

    my ($space, $error) = $class->_get_space($req);
    return $error if $error;

    my $pages = HSWiki::Model::Page->list_by_space($space->{space_id});

    return res->json({
        space_key => $space->{space_key},
        pages     => $pages,
        count     => scalar @$pages,
    })->finalize;
}

# Create page
sub create {
    my ($class, $req) = @_;

    my ($space, $error) = $class->_get_space($req);
    return $error if $error;

    # Check write permission
    unless (HSWiki::Middleware::RBAC->can_write_space($req, $space->{space_id})) {
        return res->forbidden('Write access denied to this space')->finalize;
    }

    my $data = $req->json;
    my $user_id = HSWiki::Middleware::Auth->current_user_id($req);

    # Validate required fields
    unless ($data->{title}) {
        return res->bad_request('Page title is required')->finalize;
    }

    # Generate or validate slug
    my $slug = $data->{slug} // HSWiki::Wiki->slugify($data->{title});
    unless ($slug =~ /^[a-z0-9-]+$/) {
        return res->bad_request('Invalid page slug')->finalize;
    }

    # Check if slug exists
    if (HSWiki::Model::Page->slug_exists($space->{space_id}, $slug)) {
        return res->conflict('Page with this slug already exists')->finalize;
    }

    # Create page
    my $page = HSWiki::Model::Page->create(
        space_id  => $space->{space_id},
        space_key => $space->{space_key},
        title     => $data->{title},
        slug      => $slug,
        content   => $data->{content} // '',
        author_id => $user_id,
    );

    return res->status(201)->json({
        success => 1,
        message => 'Page created',
        page    => HSWiki::Model::Page->to_response($page, include_html => 1),
    })->finalize;
}

# Get page
sub get {
    my ($class, $req) = @_;

    my ($space, $error) = $class->_get_space($req);
    return $error if $error;

    my $slug = $req->param('slug');
    my $page = HSWiki::Model::Page->find_by_slug($space->{space_id}, $slug);

    unless ($page) {
        return res->not_found('Page not found')->finalize;
    }

    return res->json({
        page => HSWiki::Model::Page->to_response($page,
            include_content => 1,
            include_html    => 1,
        ),
    })->finalize;
}

# Update page
sub update {
    my ($class, $req) = @_;

    my ($space, $error) = $class->_get_space($req);
    return $error if $error;

    # Check write permission
    unless (HSWiki::Middleware::RBAC->can_write_space($req, $space->{space_id})) {
        return res->forbidden('Write access denied to this space')->finalize;
    }

    my $slug = $req->param('slug');
    my $page = HSWiki::Model::Page->find_by_slug($space->{space_id}, $slug);

    unless ($page) {
        return res->not_found('Page not found')->finalize;
    }

    my $data = $req->json;
    my $user_id = HSWiki::Middleware::Auth->current_user_id($req);

    # Build updates
    my %updates;
    $updates{title} = $data->{title} if exists $data->{title};
    $updates{content} = $data->{content} if exists $data->{content};
    $updates{author_id} = $user_id;
    $updates{change_summary} = $data->{change_summary} if $data->{change_summary};

    # Update page
    my $updated = HSWiki::Model::Page->update(
        $space->{space_id},
        $page->{page_id},
        %updates
    );

    return res->json({
        success => 1,
        message => 'Page updated',
        page    => HSWiki::Model::Page->to_response($updated, include_html => 1),
    })->finalize;
}

# Delete page
sub delete {
    my ($class, $req) = @_;

    my ($space, $error) = $class->_get_space($req);
    return $error if $error;

    # Check write permission and page:delete
    unless (HSWiki::Middleware::RBAC->can_write_space($req, $space->{space_id})) {
        return res->forbidden('Write access denied')->finalize;
    }
    unless (HSWiki::Middleware::RBAC->has_permission($req, 'page:delete')) {
        return res->forbidden('Delete permission required')->finalize;
    }

    my $slug = $req->param('slug');
    my $page = HSWiki::Model::Page->find_by_slug($space->{space_id}, $slug);

    unless ($page) {
        return res->not_found('Page not found')->finalize;
    }

    HSWiki::Model::Page->delete($space->{space_id}, $page->{page_id});

    return res->json({
        success => 1,
        message => 'Page deleted',
    })->finalize;
}

# Get page version history
sub versions {
    my ($class, $req) = @_;

    my ($space, $error) = $class->_get_space($req);
    return $error if $error;

    my $slug = $req->param('slug');
    my $page = HSWiki::Model::Page->find_by_slug($space->{space_id}, $slug);

    unless ($page) {
        return res->not_found('Page not found')->finalize;
    }

    my $versions = HSWiki::Model::Page->get_versions($page->{page_id});

    return res->json({
        page_id  => $page->{page_id},
        slug     => $page->{slug},
        versions => $versions,
    })->finalize;
}

# Get specific version
sub get_version {
    my ($class, $req) = @_;

    my ($space, $error) = $class->_get_space($req);
    return $error if $error;

    my $slug = $req->param('slug');
    my $version_num = $req->param('version');

    my $page = HSWiki::Model::Page->find_by_slug($space->{space_id}, $slug);
    unless ($page) {
        return res->not_found('Page not found')->finalize;
    }

    my $version = HSWiki::Model::Page->get_version($page->{page_id}, $version_num);
    unless ($version) {
        return res->not_found('Version not found')->finalize;
    }

    return res->json({
        page_id => $page->{page_id},
        slug    => $page->{slug},
        version => $version,
    })->finalize;
}

# Restore page to specific version
sub restore {
    my ($class, $req) = @_;

    my ($space, $error) = $class->_get_space($req);
    return $error if $error;

    unless (HSWiki::Middleware::RBAC->can_write_space($req, $space->{space_id})) {
        return res->forbidden('Write access denied')->finalize;
    }

    my $slug = $req->param('slug');
    my $data = $req->json;

    unless ($data->{version}) {
        return res->bad_request('version is required')->finalize;
    }

    my $page = HSWiki::Model::Page->find_by_slug($space->{space_id}, $slug);
    unless ($page) {
        return res->not_found('Page not found')->finalize;
    }

    my $user_id = HSWiki::Middleware::Auth->current_user_id($req);

    my $restored = HSWiki::Model::Page->restore_version(
        $space->{space_id},
        $page->{page_id},
        $data->{version},
        $user_id
    );

    unless ($restored) {
        return res->not_found('Version not found')->finalize;
    }

    return res->json({
        success => 1,
        message => "Page restored to version $data->{version}",
        page    => HSWiki::Model::Page->to_response($restored, include_html => 1),
    })->finalize;
}

# Render wiki markup preview
sub render_preview {
    my ($class, $req) = @_;

    my $data;

    # Try to get JSON data
    eval {
        $data = $req->json;
        unless ($data && ref($data) eq 'HASH') {
            my $body = $req->body // '';
            $data = Cpanel::JSON::XS::decode_json($body) if $body;
        }
    };

    if ($@ || !$data || ref($data) ne 'HASH') {
        return res->bad_request('Invalid JSON: ' . ($@ // 'empty body'))->finalize;
    }

    unless (defined $data->{content}) {
        return res->bad_request('content is required')->finalize;
    }

    my $html;
    eval {
        $html = HSWiki::Wiki->render_safe($data->{content});
    };

    if ($@) {
        return res->server_error('Render failed: ' . $@)->finalize;
    }

    return res->json({ html => $html })->finalize;
}

1;

__END__

=head1 NAME

HSWiki::Controller::Page - Page controller for HSWiki

=head1 ROUTES

    GET /api/spaces/:key/pages - List pages in space
        Returns: { space_key, pages, count }

    POST /api/spaces/:key/pages - Create page (requires write access)
        Body: { title, content?, slug? }
        Returns: { success, message, page }

    GET /api/spaces/:key/pages/:slug - Get page
        Returns: { page }

    PUT /api/spaces/:key/pages/:slug - Update page (requires write access)
        Body: { title?, content?, change_summary? }
        Returns: { success, message, page }

    DELETE /api/spaces/:key/pages/:slug - Delete page (requires write + page:delete)
        Returns: { success, message }

    GET /api/spaces/:key/pages/:slug/versions - Get version history
        Returns: { page_id, slug, versions }

    GET /api/spaces/:key/pages/:slug/versions/:version - Get specific version
        Returns: { page_id, slug, version }

    POST /api/spaces/:key/pages/:slug/restore - Restore to version
        Body: { version }
        Returns: { success, message, page }

    POST /api/render - Render wiki markup preview
        Body: { content }
        Returns: { html }

=cut
