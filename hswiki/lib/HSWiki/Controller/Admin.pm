package HSWiki::Controller::Admin;

use strict;
use warnings;


use HSWiki::Model::User;
use HSWiki::Model::Role;
use HSWiki::Middleware::Auth;
use Hypersonic::Response qw(res);

our $VERSION = '0.01';

# Register routes with the server
sub register {
    my ($class, $server) = @_;

    # All admin routes require admin role
    my $admin_wrap = sub {
        my $handler = shift;
        return HSWiki::Middleware::Auth->wrap($handler, admin => 1);
    };

    # GET /api/admin/users - List all users
    $server->get('/api/admin/users' => $admin_wrap->(sub {
        my ($req) = @_;
        return $class->list_users($req);
    }), { dynamic => 1 });

    # GET /api/admin/users/:id - Get user details
    $server->get('/api/admin/users/:id' => $admin_wrap->(sub {
        my ($req) = @_;
        return $class->get_user($req);
    }), { dynamic => 1 });

    # PUT /api/admin/users/:id - Update user (role, active status)
    $server->put('/api/admin/users/:id' => $admin_wrap->(sub {
        my ($req) = @_;
        return $class->update_user($req);
    }), { dynamic => 1, parse_json => 1 });

    # DELETE /api/admin/users/:id - Deactivate user
    $server->del('/api/admin/users/:id' => $admin_wrap->(sub {
        my ($req) = @_;
        return $class->deactivate_user($req);
    }), { dynamic => 1 });

    # POST /api/admin/users/:id/reactivate - Reactivate user
    $server->post('/api/admin/users/:id/reactivate' => $admin_wrap->(sub {
        my ($req) = @_;
        return $class->reactivate_user($req);
    }), { dynamic => 1 });

    # GET /api/admin/roles - List all roles
    $server->get('/api/admin/roles' => $admin_wrap->(sub {
        my ($req) = @_;
        return $class->list_roles($req);
    }), { dynamic => 1 });

    # POST /api/admin/roles - Create role
    $server->post('/api/admin/roles' => $admin_wrap->(sub {
        my ($req) = @_;
        return $class->create_role($req);
    }), { dynamic => 1, parse_json => 1 });

    # PUT /api/admin/roles/:id - Update role
    $server->put('/api/admin/roles/:id' => $admin_wrap->(sub {
        my ($req) = @_;
        return $class->update_role($req);
    }), { dynamic => 1, parse_json => 1 });

    # DELETE /api/admin/roles/:id - Delete role
    $server->del('/api/admin/roles/:id' => $admin_wrap->(sub {
        my ($req) = @_;
        return $class->delete_role($req);
    }), { dynamic => 1 });

    # POST /api/admin/init - Initialize default data
    $server->post('/api/admin/init' => $admin_wrap->(sub {
        my ($req) = @_;
        return $class->init_defaults($req);
    }), { dynamic => 1 });

    # GET /api/admin/stats - System statistics
    $server->get('/api/admin/stats' => $admin_wrap->(sub {
        my ($req) = @_;
        return $class->stats($req);
    }), { dynamic => 1 });
}

# List all users
sub list_users {
    my ($class, $req) = @_;

    my $users = HSWiki::Model::User->list_all;

    # Remove sensitive data
    my @safe_users = map { HSWiki::Model::User->to_safe($_) } @$users;

    return res->json({
        users => \@safe_users,
        count => scalar @safe_users,
    })->finalize;
}

# Get user details
sub get_user {
    my ($class, $req) = @_;

    my $user_id = $req->param('id');
    my $user = HSWiki::Model::User->find_by_id($user_id);

    unless ($user) {
        return res->not_found('User not found')->finalize;
    }

    # Get role info
    my $role = HSWiki::Model::Role->find_by_id($user->{role_id});

    return res->json({
        user => HSWiki::Model::User->to_safe($user),
        role => $role ? {
            role_id     => $role->{role_id},
            role_name   => $role->{role_name},
            permissions => $role->{permissions},
        } : undef,
    })->finalize;
}

# Update user
sub update_user {
    my ($class, $req) = @_;

    my $user_id = $req->param('id');
    my $data = $req->json;

    my $user = HSWiki::Model::User->find_by_id($user_id);
    unless ($user) {
        return res->not_found('User not found')->finalize;
    }

    # Prevent modifying self
    my $current_user_id = $req->session('user_id');
    if ($user_id eq $current_user_id) {
        return res->bad_request('Cannot modify your own account via admin API')->finalize;
    }

    my %updates;

    # Update role if provided
    if ($data->{role_id}) {
        my $role = HSWiki::Model::Role->find_by_id($data->{role_id});
        unless ($role) {
            return res->bad_request('Invalid role_id')->finalize;
    }
        $updates{role_id} = $data->{role_id};
    }

    # Update active status if provided
    if (exists $data->{is_active}) {
        $updates{is_active} = $data->{is_active} ? 1 : 0;
    }

    if (%updates) {
        HSWiki::Model::User->update($user_id, %updates);
    }

    my $updated = HSWiki::Model::User->find_by_id($user_id);

    return res->json({
        success => 1,
        message => 'User updated',
        user    => HSWiki::Model::User->to_safe($updated),
    })->finalize;
}

# Deactivate user
sub deactivate_user {
    my ($class, $req) = @_;

    my $user_id = $req->param('id');

    my $user = HSWiki::Model::User->find_by_id($user_id);
    unless ($user) {
        return res->not_found('User not found')->finalize;
    }

    # Prevent self-deactivation
    my $current_user_id = $req->session('user_id');
    if ($user_id eq $current_user_id) {
        return res->bad_request('Cannot deactivate your own account')->finalize;
    }

    HSWiki::Model::User->deactivate($user_id);

    return res->json({
        success => 1,
        message => 'User deactivated',
    })->finalize;
}

# Reactivate user
sub reactivate_user {
    my ($class, $req) = @_;

    my $user_id = $req->param('id');

    my $user = HSWiki::Model::User->find_by_id($user_id);
    unless ($user) {
        return res->not_found('User not found')->finalize;
    }

    HSWiki::Model::User->reactivate($user_id);

    return res->json({
        success => 1,
        message => 'User reactivated',
    })->finalize;
}

# List all roles
sub list_roles {
    my ($class, $req) = @_;

    my $roles = HSWiki::Model::Role->list_all;

    return res->json({
        roles => $roles,
        count => scalar @$roles,
    })->finalize;
}

# Create role
sub create_role {
    my ($class, $req) = @_;

    my $data = $req->json;

    unless ($data->{role_name}) {
        return res->bad_request('role_name is required')->finalize;
    }

    # Check if role exists
    if (HSWiki::Model::Role->exists($data->{role_name})) {
        return res->conflict('Role already exists')->finalize;
    }

    my $role = HSWiki::Model::Role->create(
        role_name   => $data->{role_name},
        permissions => $data->{permissions} // [],
        description => $data->{description} // '',
    );

    return res->status(201)->json({
        success => 1,
        message => 'Role created',
        role    => $role,
    })->finalize;
}

# Update role
sub update_role {
    my ($class, $req) = @_;

    my $role_id = $req->param('id');
    my $data = $req->json;

    my $role = HSWiki::Model::Role->find_by_id($role_id);
    unless ($role) {
        return res->not_found('Role not found')->finalize;
    }

    # Don't allow modifying built-in roles
    if ($role->{role_name} =~ /^(admin|editor|viewer)$/) {
        return res->bad_request('Cannot modify built-in roles')->finalize;
    }

    if ($data->{permissions}) {
        HSWiki::Model::Role->update_permissions($role_id, $data->{permissions});
    }

    my $updated = HSWiki::Model::Role->find_by_id($role_id);

    return res->json({
        success => 1,
        message => 'Role updated',
        role    => $updated,
    })->finalize;
}

# Delete role
sub delete_role {
    my ($class, $req) = @_;

    my $role_id = $req->param('id');

    my $role = HSWiki::Model::Role->find_by_id($role_id);
    unless ($role) {
        return res->not_found('Role not found')->finalize;
    }

    # Don't allow deleting built-in roles
    if ($role->{role_name} =~ /^(admin|editor|viewer)$/) {
        return res->bad_request('Cannot delete built-in roles')->finalize;
    }

    HSWiki::Model::Role->delete($role_id);

    return res->json({
        success => 1,
        message => 'Role deleted',
    })->finalize;
}

# Initialize default data
sub init_defaults {
    my ($class, $req) = @_;

    # Initialize roles
    HSWiki::Model::Role->init_defaults;

    # Initialize schema
    eval {
        HSWiki::DB->init_schema;
    };

    return res->json({
        success => 1,
        message => 'Default data initialized',
    })->finalize;
}

# System statistics
sub stats {
    my ($class, $req) = @_;

    # Note: These counts would need proper implementation
    # Simplified here for demonstration
    my $users = HSWiki::Model::User->list_all;
    my $roles = HSWiki::Model::Role->list_all;

    return res->json({
        users_count  => scalar @$users,
        roles_count  => scalar @$roles,
        active_users => scalar grep { $_->{is_active} } @$users,
    })->finalize;
}

1;

__END__

=head1 NAME

HSWiki::Controller::Admin - Admin controller for HSWiki

=head1 ROUTES

All routes require admin role.

    GET /api/admin/users - List all users
        Returns: { users, count }

    GET /api/admin/users/:id - Get user details
        Returns: { user, role }

    PUT /api/admin/users/:id - Update user
        Body: { role_id?, is_active? }
        Returns: { success, message, user }

    DELETE /api/admin/users/:id - Deactivate user
        Returns: { success, message }

    POST /api/admin/users/:id/reactivate - Reactivate user
        Returns: { success, message }

    GET /api/admin/roles - List all roles
        Returns: { roles, count }

    POST /api/admin/roles - Create role
        Body: { role_name, permissions?, description? }
        Returns: { success, message, role }

    PUT /api/admin/roles/:id - Update role permissions
        Body: { permissions }
        Returns: { success, message, role }

    DELETE /api/admin/roles/:id - Delete role
        Returns: { success, message }

    POST /api/admin/init - Initialize default data
        Returns: { success, message }

    GET /api/admin/stats - System statistics
        Returns: { users_count, roles_count, active_users }

=cut
