package HSWiki::Controller::Space;

use strict;
use warnings;


use HSWiki::Model::Space;
use HSWiki::Model::Page;
use HSWiki::Model::User;
use HSWiki::Wiki;
use HSWiki::Middleware::Auth;
use HSWiki::Middleware::RBAC;
use Hypersonic::Response qw(res);

our $VERSION = '0.01';

# Register routes with the server
sub register {
    my ($class, $server) = @_;

    # GET /api/spaces - List spaces
    $server->get('/api/spaces' => HSWiki::Middleware::Auth->wrap(sub {
        my ($req) = @_;
        return $class->list($req);
    }, optional => 1), { dynamic => 1 });

    # POST /api/spaces - Create space
    $server->post('/api/spaces' => HSWiki::Middleware::Auth->wrap(sub {
        my ($req) = @_;
        return $class->create($req);
    }), { dynamic => 1, parse_json => 1 });

    # GET /api/spaces/:key - Get space
    $server->get('/api/spaces/:key' => HSWiki::Middleware::Auth->wrap(sub {
        my ($req) = @_;
        return $class->get($req);
    }, optional => 1), { dynamic => 1 });

    # PUT /api/spaces/:key - Update space
    $server->put('/api/spaces/:key' => HSWiki::Middleware::Auth->wrap(sub {
        my ($req) = @_;
        return $class->update($req);
    }), { dynamic => 1, parse_json => 1 });

    # DELETE /api/spaces/:key - Delete space
    $server->del('/api/spaces/:key' => HSWiki::Middleware::Auth->wrap(sub {
        my ($req) = @_;
        return $class->delete($req);
    }), { dynamic => 1 });

    # POST /api/spaces/:key/permissions - Grant permission
    $server->post('/api/spaces/:key/permissions' => HSWiki::Middleware::Auth->wrap(sub {
        my ($req) = @_;
        return $class->grant_permission($req);
    }), { dynamic => 1, parse_json => 1 });

    # DELETE /api/spaces/:key/permissions/:user_id - Revoke permission
    $server->del('/api/spaces/:key/permissions/:user_id' => HSWiki::Middleware::Auth->wrap(sub {
        my ($req) = @_;
        return $class->revoke_permission($req);
    }), { dynamic => 1 });

    # GET /api/spaces/:key/permissions - List permissions
    $server->get('/api/spaces/:key/permissions' => HSWiki::Middleware::Auth->wrap(sub {
        my ($req) = @_;
        return $class->list_permissions($req);
    }), { dynamic => 1 });
}

# List spaces
sub list {
    my ($class, $req) = @_;

    my $user_id = HSWiki::Middleware::Auth->current_user_id($req);

    my @spaces;

    # Get public spaces
    my $public = HSWiki::Model::Space->list_public;
    push @spaces, @$public;

    # If logged in, also get user's spaces
    if ($user_id) {
        my $user_spaces = HSWiki::Model::Space->list_for_user($user_id);
        for my $us (@$user_spaces) {
            # Avoid duplicates (public spaces user also has permission to)
            my $found = grep { $_->{space_id} eq $us->{space_id} } @spaces;
            unless ($found) {
                my $space = HSWiki::Model::Space->find_by_id($us->{space_id});
                push @spaces, $space if $space;
            }
        }
    }

    return res->json({
        spaces => \@spaces,
        count  => scalar @spaces,
    })->finalize;
}

# Create space
sub create {
    my ($class, $req) = @_;

    my $data = $req->json;
    my $user_id = HSWiki::Middleware::Auth->current_user_id($req);

    # Check permission
    unless (HSWiki::Middleware::RBAC->has_permission($req, 'space:write')) {
        return res->forbidden('Permission denied to create spaces')->finalize;
    }

    # Validate required fields
    unless ($data->{name}) {
        return res->bad_request('Space name is required')->finalize;
    }

    # Generate or validate space_key
    my $space_key = $data->{space_key};
    if ($space_key) {
        # Validate provided key
        unless ($space_key =~ /^[a-z0-9-]+$/) {
            return res->bad_request('Space key can only contain lowercase letters, numbers, and hyphens')->finalize;
        }
    }

    # Check if key exists
    $space_key //= HSWiki::Wiki->slugify($data->{name});
    if (HSWiki::Model::Space->key_exists($space_key)) {
        return res->conflict('Space key already exists')->finalize;
    }

    # Create space
    my $space = HSWiki::Model::Space->create(
        name        => $data->{name},
        space_key   => $space_key,
        description => $data->{description},
        is_public   => $data->{is_public} // 0,
        owner_id    => $user_id,
    );

    return res->status(201)->json({
        success => 1,
        message => 'Space created',
        space   => $space,
    })->finalize;
}

# Get space
sub get {
    my ($class, $req) = @_;

    my $space_key = $req->param('key');
    my $space = HSWiki::Model::Space->find_by_key($space_key);

    unless ($space) {
        return res->not_found('Space not found')->finalize;
    }

    # Check access
    unless (HSWiki::Middleware::RBAC->can_access_space($req, $space->{space_id})) {
        return res->forbidden('Access denied to this space')->finalize;
    }

    # Get page count
    my $page_count = HSWiki::Model::Page->count_by_space($space->{space_id});

    return res->json({
        space      => $space,
        page_count => $page_count,
    })->finalize;
}

# Update space
sub update {
    my ($class, $req) = @_;

    my $space_key = $req->param('key');
    my $data = $req->json;

    my $space = HSWiki::Model::Space->find_by_key($space_key);
    unless ($space) {
        return res->not_found('Space not found')->finalize;
    }

    # Check admin access
    unless (HSWiki::Middleware::RBAC->is_space_admin($req, $space->{space_id})) {
        return res->forbidden('Admin access required to update space')->finalize;
    }

    # Build updates
    my %updates;
    $updates{name} = $data->{name} if exists $data->{name};
    $updates{description} = $data->{description} if exists $data->{description};
    $updates{is_public} = $data->{is_public} if exists $data->{is_public};

    # Update space
    my $updated = HSWiki::Model::Space->update($space->{space_id}, %updates);

    return res->json({
        success => 1,
        message => 'Space updated',
        space   => $updated,
    })->finalize;
}

# Delete space
sub delete {
    my ($class, $req) = @_;

    my $space_key = $req->param('key');

    my $space = HSWiki::Model::Space->find_by_key($space_key);
    unless ($space) {
        return res->not_found('Space not found')->finalize;
    }

    # Check admin access or delete permission
    my $is_admin = HSWiki::Middleware::RBAC->is_space_admin($req, $space->{space_id});
    my $can_delete = HSWiki::Middleware::RBAC->has_permission($req, 'space:delete');

    unless ($is_admin || $can_delete) {
        return res->forbidden('Permission denied to delete space')->finalize;
    }

    # Delete space
    HSWiki::Model::Space->delete($space->{space_id});

    return res->json({
        success => 1,
        message => 'Space deleted',
    })->finalize;
}

# Grant permission to user
sub grant_permission {
    my ($class, $req) = @_;

    my $space_key = $req->param('key');
    my $data = $req->json;

    my $space = HSWiki::Model::Space->find_by_key($space_key);
    unless ($space) {
        return res->not_found('Space not found')->finalize;
    }

    # Check space admin access
    unless (HSWiki::Middleware::RBAC->is_space_admin($req, $space->{space_id})) {
        return res->forbidden('Admin access required')->finalize;
    }

    # Validate input
    unless ($data->{user_id} && $data->{permission}) {
        return res->bad_request('user_id and permission required')->finalize;
    }

    unless ($data->{permission} =~ /^(read|write|admin)$/) {
        return res->bad_request('Permission must be: read, write, or admin')->finalize;
    }

    # Check user exists
    my $user = HSWiki::Model::User->find_by_id($data->{user_id});
    unless ($user) {
        return res->not_found('User not found')->finalize;
    }

    # Grant permission
    HSWiki::Model::Space->grant_permission(
        $space->{space_id},
        $data->{user_id},
        $data->{permission}
    );

    return res->status(201)->json({
        success    => 1,
        message    => 'Permission granted',
        user_id    => $data->{user_id},
        permission => $data->{permission},
    })->finalize;
}

# Revoke permission
sub revoke_permission {
    my ($class, $req) = @_;

    my $space_key = $req->param('key');
    my $user_id = $req->param('user_id');

    my $space = HSWiki::Model::Space->find_by_key($space_key);
    unless ($space) {
        return res->not_found('Space not found')->finalize;
    }

    # Check space admin access
    unless (HSWiki::Middleware::RBAC->is_space_admin($req, $space->{space_id})) {
        return res->forbidden('Admin access required')->finalize;
    }

    # Cannot revoke owner's permission
    if ($space->{owner_id} && $space->{owner_id} eq $user_id) {
        return res->bad_request('Cannot revoke owner permission')->finalize;
    }

    # Revoke permission
    HSWiki::Model::Space->revoke_permission($space->{space_id}, $user_id);

    return res->json({
        success => 1,
        message => 'Permission revoked',
    })->finalize;
}

# List permissions
sub list_permissions {
    my ($class, $req) = @_;

    my $space_key = $req->param('key');

    my $space = HSWiki::Model::Space->find_by_key($space_key);
    unless ($space) {
        return res->not_found('Space not found')->finalize;
    }

    # Check space admin access
    unless (HSWiki::Middleware::RBAC->is_space_admin($req, $space->{space_id})) {
        return res->forbidden('Admin access required')->finalize;
    }

    my $permissions = HSWiki::Model::Space->list_permissions($space->{space_id});

    return res->json({
        space_id    => $space->{space_id},
        owner_id    => $space->{owner_id},
        permissions => $permissions,
    })->finalize;
}

1;

__END__

=head1 NAME

HSWiki::Controller::Space - Space controller for HSWiki

=head1 ROUTES

    GET /api/spaces - List accessible spaces
        Returns: { spaces, count }

    POST /api/spaces - Create space (requires auth + space:write)
        Body: { name, description?, space_key?, is_public? }
        Returns: { success, message, space }

    GET /api/spaces/:key - Get space details
        Returns: { space, page_count }

    PUT /api/spaces/:key - Update space (requires space admin)
        Body: { name?, description?, is_public? }
        Returns: { success, message, space }

    DELETE /api/spaces/:key - Delete space (requires space admin or space:delete)
        Returns: { success, message }

    POST /api/spaces/:key/permissions - Grant permission (requires space admin)
        Body: { user_id, permission: "read"|"write"|"admin" }
        Returns: { success, message, user_id, permission }

    DELETE /api/spaces/:key/permissions/:user_id - Revoke permission
        Returns: { success, message }

    GET /api/spaces/:key/permissions - List permissions
        Returns: { space_id, owner_id, permissions }

=cut
