package HSWiki::Middleware::RBAC;

use strict;
use warnings;


use HSWiki::Model::Role;
use HSWiki::Model::Space;
use HSWiki::Middleware::Auth;
use HSWiki::Auth;
use Hypersonic::Response qw(res);

our $VERSION = '0.01';

# Check if user has a specific permission (via role)
sub has_permission {
    my ($class, $req, $permission) = @_;

    my $role_id = HSWiki::Auth->get_session_value($req, 'role_id');
    return 0 unless $role_id;

    # Admin has all permissions
    if (HSWiki::Model::Role->is_admin($role_id)) {
        return 1;
    }

    return HSWiki::Model::Role->has_permission($role_id, $permission);
}

# Middleware that requires a specific permission
sub require_permission {
    my ($class, $permission) = @_;

    return sub {
        my ($req) = @_;

        # Must be authenticated
        unless (HSWiki::Auth->is_authenticated($req)) {
            return res->unauthorized('Authentication required')->finalize;
        }

        # Check permission
        unless ($class->has_permission($req, $permission)) {
            return res->forbidden("Permission '$permission' required")->finalize;
        }

        return;  # Continue to handler
    };
}

# Check if user can access a space
sub can_access_space {
    my ($class, $req, $space_id) = @_;

    my $user_id = HSWiki::Middleware::Auth->current_user_id($req);

    # Not logged in - can only access public spaces
    unless ($user_id) {
        my $space = HSWiki::Model::Space->find_by_id($space_id);
        return $space && $space->{is_public};
    }

    # Admin can access everything
    my $role_id = HSWiki::Auth->get_session_value($req, 'role_id');
    if ($role_id && HSWiki::Model::Role->is_admin($role_id)) {
        return 1;
    }

    return HSWiki::Model::Space->can_access($space_id, $user_id);
}

# Check if user can write to a space
sub can_write_space {
    my ($class, $req, $space_id) = @_;

    my $user_id = HSWiki::Middleware::Auth->current_user_id($req);
    return 0 unless $user_id;

    # Admin can write everywhere
    my $role_id = HSWiki::Auth->get_session_value($req, 'role_id');
    if ($role_id && HSWiki::Model::Role->is_admin($role_id)) {
        return 1;
    }

    # Check role permission
    return 0 unless $class->has_permission($req, 'page:write');

    # Check space-level permission
    return HSWiki::Model::Space->can_write($space_id, $user_id);
}

# Check if user is space admin
sub is_space_admin {
    my ($class, $req, $space_id) = @_;

    my $user_id = HSWiki::Middleware::Auth->current_user_id($req);
    return 0 unless $user_id;

    # System admin is always space admin
    my $role_id = HSWiki::Auth->get_session_value($req, 'role_id');
    if ($role_id && HSWiki::Model::Role->is_admin($role_id)) {
        return 1;
    }

    return HSWiki::Model::Space->is_admin($space_id, $user_id);
}

# Middleware that requires space read access
sub require_space_access {
    my ($class, $space_key_param) = @_;
    $space_key_param //= 'key';

    return sub {
        my ($req) = @_;

        my $space_key = $req->param($space_key_param);
        unless ($space_key) {
            return res->bad_request('Space key required')->finalize;
        }

        my $space = HSWiki::Model::Space->find_by_key($space_key);
        unless ($space) {
            return res->not_found('Space not found')->finalize;
        }

        unless ($class->can_access_space($req, $space->{space_id})) {
            return res->forbidden('Access denied to this space')->finalize;
        }

        return;
    };
}

# Middleware that requires space write access
sub require_space_write {
    my ($class, $space_key_param) = @_;
    $space_key_param //= 'key';

    return sub {
        my ($req) = @_;

        my $space_key = $req->param($space_key_param);
        unless ($space_key) {
            return res->bad_request('Space key required')->finalize;
        }

        my $space = HSWiki::Model::Space->find_by_key($space_key);
        unless ($space) {
            return res->not_found('Space not found')->finalize;
        }

        unless ($class->can_write_space($req, $space->{space_id})) {
            return res->forbidden('Write access denied to this space')->finalize;
        }

        return;
    };
}

# Middleware that requires space admin access
sub require_space_admin {
    my ($class, $space_key_param) = @_;
    $space_key_param //= 'key';

    return sub {
        my ($req) = @_;

        my $space_key = $req->param($space_key_param);
        unless ($space_key) {
            return res->bad_request('Space key required')->finalize;
        }

        my $space = HSWiki::Model::Space->find_by_key($space_key);
        unless ($space) {
            return res->not_found('Space not found')->finalize;
        }

        unless ($class->is_space_admin($req, $space->{space_id})) {
            return res->forbidden('Admin access denied to this space')->finalize;
        }

        return;
    };
}

# Note: Space info should be looked up from URL params by handlers directly

# Wrap handler with permission check
sub wrap {
    my ($class, $handler, %opts) = @_;

    my @middlewares;

    # Add permission check if specified
    if ($opts{permission}) {
        push @middlewares, $class->require_permission($opts{permission});
    }

    # Add space access check if specified
    if ($opts{space_access}) {
        push @middlewares, $class->require_space_access($opts{space_param});
    }
    if ($opts{space_write}) {
        push @middlewares, $class->require_space_write($opts{space_param});
    }
    if ($opts{space_admin}) {
        push @middlewares, $class->require_space_admin($opts{space_param});
    }

    return sub {
        my ($req) = @_;

        # Run all middlewares
        for my $mw (@middlewares) {
            my $result = $mw->($req);
            return $result if $result;  # Return if middleware failed
        }

        # Continue to handler
        return $handler->($req);
    };
}

1;

__END__

=head1 NAME

HSWiki::Middleware::RBAC - Role-based access control middleware for HSWiki

=head1 SYNOPSIS

    use HSWiki::Middleware::RBAC;

    # Check permissions in handler
    if (HSWiki::Middleware::RBAC->has_permission($req, 'page:write')) {
        # User can write pages
    }

    # Space access checks
    if (HSWiki::Middleware::RBAC->can_access_space($req, $space_id)) { ... }
    if (HSWiki::Middleware::RBAC->can_write_space($req, $space_id)) { ... }
    if (HSWiki::Middleware::RBAC->is_space_admin($req, $space_id)) { ... }

    # Middleware usage
    $server->post('/api/spaces/:key/pages' => HSWiki::Middleware::RBAC->wrap(sub {
        my ($req) = @_;
        my $space_id = HSWiki::Middleware::RBAC->current_space_id($req);
        # Create page...
    }, space_write => 1, space_param => 'key'), { dynamic => 1, parse_json => 1 });

=head1 PERMISSIONS

    user:read    - View user profiles
    user:write   - Edit user profiles
    user:delete  - Deactivate users
    role:manage  - Manage roles
    space:read   - View spaces
    space:write  - Create/edit spaces
    space:delete - Delete spaces
    space:admin  - Manage space permissions
    page:read    - View pages
    page:write   - Create/edit pages
    page:delete  - Delete pages

=cut
