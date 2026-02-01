package HSWiki::Controller::OpenAPI;

use strict;
use warnings;


use HSWiki::Model::Page;
use HSWiki::Model::Space;
use HSWiki::Model::User;
use HSWiki::Wiki;
use HSWiki::Middleware::Auth;
use Hypersonic::Response qw(res);

our $VERSION = '0.01';

# Register routes with the server
sub register {
    my ($class, $server) = @_;

    # API key authentication wrapper
    my $api_wrap = sub {
        my $handler = shift;
        return HSWiki::Middleware::Auth->wrap($handler, api_key => 1);
    };

    # GET /openapi/spaces - List accessible spaces
    $server->get('/openapi/spaces' => $api_wrap->(sub {
        my ($req) = @_;
        return $class->list_spaces($req);
    }), { dynamic => 1 });

    # GET /openapi/spaces/:key - Get space info
    $server->get('/openapi/spaces/:key' => $api_wrap->(sub {
        my ($req) = @_;
        return $class->get_space($req);
    }), { dynamic => 1 });

    # GET /openapi/spaces/:key/pages - List pages in space
    $server->get('/openapi/spaces/:key/pages' => $api_wrap->(sub {
        my ($req) = @_;
        return $class->list_pages($req);
    }), { dynamic => 1 });

    # GET /openapi/spaces/:key/pages/:slug - Get page content
    $server->get('/openapi/spaces/:key/pages/:slug' => $api_wrap->(sub {
        my ($req) = @_;
        return $class->get_page($req);
    }), { dynamic => 1 });

    # POST /openapi/pages/render - Render wiki markup
    $server->post('/openapi/pages/render' => $api_wrap->(sub {
        my ($req) = @_;
        return $class->render_markup($req);
    }), { dynamic => 1, parse_json => 1 });

    # GET /openapi/search - Search pages
    $server->get('/openapi/search' => $api_wrap->(sub {
        my ($req) = @_;
        return $class->search($req);
    }), { dynamic => 1 });

    # POST /openapi/spaces/:key/pages - Create page via API
    $server->post('/openapi/spaces/:key/pages' => $api_wrap->(sub {
        my ($req) = @_;
        return $class->create_page($req);
    }), { dynamic => 1, parse_json => 1 });

    # PUT /openapi/spaces/:key/pages/:slug - Update page via API
    $server->put('/openapi/spaces/:key/pages/:slug' => $api_wrap->(sub {
        my ($req) = @_;
        return $class->update_page($req);
    }), { dynamic => 1, parse_json => 1 });
}

# Helper to get API user ID
sub _api_user_id {
    my ($req) = @_;
    return $req->session('api_user_id');
}

# List accessible spaces
sub list_spaces {
    my ($class, $req) = @_;

    my $user_id = _api_user_id($req);

    # Get user's spaces and public spaces
    my @spaces;

    my $public = HSWiki::Model::Space->list_public;
    push @spaces, @$public;

    if ($user_id) {
        my $user_spaces = HSWiki::Model::Space->list_for_user($user_id);
        for my $us (@$user_spaces) {
            my $found = grep { $_->{space_id} eq $us->{space_id} } @spaces;
            unless ($found) {
                my $space = HSWiki::Model::Space->find_by_id($us->{space_id});
                push @spaces, $space if $space;
            }
        }
    }

    # Simplify response for API
    my @result = map {{
        space_key   => $_->{space_key},
        name        => $_->{name},
        description => $_->{description},
        is_public   => $_->{is_public},
    }} @spaces;

    return res->json({
        spaces => \@result,
    })->finalize;
}

# Get space info
sub get_space {
    my ($class, $req) = @_;

    my $space_key = $req->param('key');
    my $space = HSWiki::Model::Space->find_by_key($space_key);

    unless ($space) {
        return res->not_found('Space not found')->finalize;
    }

    my $user_id = _api_user_id($req);
    unless ($space->{is_public} || HSWiki::Model::Space->can_access($space->{space_id}, $user_id)) {
        return res->forbidden('Access denied')->finalize;
    }

    return res->json({
        space_key   => $space->{space_key},
        name        => $space->{name},
        description => $space->{description},
        is_public   => $space->{is_public},
    })->finalize;
}

# List pages in space
sub list_pages {
    my ($class, $req) = @_;

    my $space_key = $req->param('key');
    my $space = HSWiki::Model::Space->find_by_key($space_key);

    unless ($space) {
        return res->not_found('Space not found')->finalize;
    }

    my $user_id = _api_user_id($req);
    unless ($space->{is_public} || HSWiki::Model::Space->can_access($space->{space_id}, $user_id)) {
        return res->forbidden('Access denied')->finalize;
    }

    my $pages = HSWiki::Model::Page->list_by_space($space->{space_id});

    my @result = map {{
        slug       => $_->{slug},
        title      => $_->{title},
        version    => $_->{version},
        updated_at => $_->{updated_at},
    }} @$pages;

    return res->json({
        space_key => $space_key,
        pages     => \@result,
    })->finalize;
}

# Get page content
sub get_page {
    my ($class, $req) = @_;

    my $space_key = $req->param('key');
    my $slug = $req->param('slug');

    my $space = HSWiki::Model::Space->find_by_key($space_key);
    unless ($space) {
        return res->not_found('Space not found')->finalize;
    }

    my $user_id = _api_user_id($req);
    unless ($space->{is_public} || HSWiki::Model::Space->can_access($space->{space_id}, $user_id)) {
        return res->forbidden('Access denied')->finalize;
    }

    my $page = HSWiki::Model::Page->find_by_slug($space->{space_id}, $slug);
    unless ($page) {
        return res->not_found('Page not found')->finalize;
    }

    # Check format preference
    my $format = $req->query_param('format') // 'html';

    my $response = {
        space_key  => $space_key,
        slug       => $page->{slug},
        title      => $page->{title},
        version    => $page->{version},
        updated_at => $page->{updated_at},
    };

    if ($format eq 'raw' || $format eq 'wiki') {
        $response->{content} = $page->{content};
    } elsif ($format eq 'both') {
        $response->{content} = $page->{content};
        $response->{html} = $page->{content_html};
    } else {
        $response->{html} = $page->{content_html};
    }

    return res->json($response)->finalize;}

# Render wiki markup
sub render_markup {
    my ($class, $req) = @_;

    my $data = $req->json;

    unless (defined $data->{content}) {
        return res->bad_request('content is required')->finalize;
    }

    my $html = HSWiki::Wiki->render_safe($data->{content});

    return res->json({
        html => $html,
    })->finalize;
}

# Search pages
sub search {
    my ($class, $req) = @_;

    my $query = $req->query_param('q');
    my $space_key = $req->query_param('space');

    unless ($query) {
        return res->bad_request('Query parameter q is required')->finalize;
    }

    my $user_id = _api_user_id($req);
    my @results;

    if ($space_key) {
        # Search in specific space
        my $space = HSWiki::Model::Space->find_by_key($space_key);
        if ($space && ($space->{is_public} || HSWiki::Model::Space->can_access($space->{space_id}, $user_id))) {
            my $pages = HSWiki::Model::Page->search($space->{space_id}, $query);
            for my $page (@$pages) {
                push @results, {
                    space_key => $space_key,
                    slug      => $page->{slug},
                    title     => $page->{title},
                };
            }
        }
    } else {
        # Search across accessible spaces
        my $public = HSWiki::Model::Space->list_public;
        for my $space (@$public) {
            my $pages = HSWiki::Model::Page->search($space->{space_id}, $query);
            for my $page (@$pages) {
                push @results, {
                    space_key => $space->{space_key},
                    slug      => $page->{slug},
                    title     => $page->{title},
                };
            }
        }
    }

    return res->json({
        query   => $query,
        results => \@results,
        count   => scalar @results,
    })->finalize;
}

# Create page via API
sub create_page {
    my ($class, $req) = @_;

    my $space_key = $req->param('key');
    my $data = $req->json;

    my $space = HSWiki::Model::Space->find_by_key($space_key);
    unless ($space) {
        return res->not_found('Space not found')->finalize;
    }

    my $user_id = _api_user_id($req);
    unless (HSWiki::Model::Space->can_write($space->{space_id}, $user_id)) {
        return res->forbidden('Write access denied')->finalize;
    }

    unless ($data->{title}) {
        return res->bad_request('title is required')->finalize;
    }

    my $slug = $data->{slug} // HSWiki::Wiki->slugify($data->{title});

    if (HSWiki::Model::Page->slug_exists($space->{space_id}, $slug)) {
        return res->conflict('Page already exists')->finalize;
    }

    my $page = HSWiki::Model::Page->create(
        space_id  => $space->{space_id},
        space_key => $space_key,
        title     => $data->{title},
        slug      => $slug,
        content   => $data->{content} // '',
        author_id => $user_id,
    );

    return res->status(201)->json({
        success   => 1,
        space_key => $space_key,
        slug      => $page->{slug},
        title     => $page->{title},
        version   => $page->{version},
    })->finalize;
}

# Update page via API
sub update_page {
    my ($class, $req) = @_;

    my $space_key = $req->param('key');
    my $slug = $req->param('slug');
    my $data = $req->json;

    my $space = HSWiki::Model::Space->find_by_key($space_key);
    unless ($space) {
        return res->not_found('Space not found')->finalize;
    }

    my $user_id = _api_user_id($req);
    unless (HSWiki::Model::Space->can_write($space->{space_id}, $user_id)) {
        return res->forbidden('Write access denied')->finalize;
    }

    my $page = HSWiki::Model::Page->find_by_slug($space->{space_id}, $slug);
    unless ($page) {
        return res->not_found('Page not found')->finalize;
    }

    my %updates;
    $updates{title} = $data->{title} if exists $data->{title};
    $updates{content} = $data->{content} if exists $data->{content};
    $updates{author_id} = $user_id;
    $updates{change_summary} = $data->{change_summary} // 'Updated via API';

    my $updated = HSWiki::Model::Page->update(
        $space->{space_id},
        $page->{page_id},
        %updates
    );

    return res->json({
        success   => 1,
        space_key => $space_key,
        slug      => $updated->{slug},
        title     => $updated->{title},
        version   => $updated->{version},
    })->finalize;
}

1;

__END__

=head1 NAME

HSWiki::Controller::OpenAPI - External API controller for HSWiki

=head1 DESCRIPTION

This controller provides an external API for integrating HSWiki with other systems.
All routes require authentication via the X-API-Key header.

=head1 AUTHENTICATION

Include the API key in the request header:

    X-API-Key: your-api-key-here

=head1 ROUTES

    GET /openapi/spaces - List accessible spaces
        Returns: { spaces }

    GET /openapi/spaces/:key - Get space info
        Returns: { space_key, name, description, is_public }

    GET /openapi/spaces/:key/pages - List pages in space
        Returns: { space_key, pages }

    GET /openapi/spaces/:key/pages/:slug - Get page content
        Query: ?format=html|raw|both (default: html)
        Returns: { space_key, slug, title, version, html/content }

    POST /openapi/pages/render - Render wiki markup
        Body: { content }
        Returns: { html }

    GET /openapi/search - Search pages
        Query: ?q=search_term&space=optional_space_key
        Returns: { query, results, count }

    POST /openapi/spaces/:key/pages - Create page
        Body: { title, content?, slug? }
        Returns: { success, space_key, slug, title, version }

    PUT /openapi/spaces/:key/pages/:slug - Update page
        Body: { title?, content?, change_summary? }
        Returns: { success, space_key, slug, title, version }

=head1 EXAMPLE USAGE

    # Get page as HTML
    curl -H "X-API-Key: abc123" \
         http://localhost:5207/openapi/spaces/docs/pages/getting-started

    # Get page as wiki markup
    curl -H "X-API-Key: abc123" \
         "http://localhost:5207/openapi/spaces/docs/pages/getting-started?format=raw"

    # Render markup
    curl -H "X-API-Key: abc123" \
         -H "Content-Type: application/json" \
         -d '{"content":"= Hello =\n\nWorld"}' \
         http://localhost:5207/openapi/pages/render

    # Search
    curl -H "X-API-Key: abc123" \
         "http://localhost:5207/openapi/search?q=getting&space=docs"

=cut
