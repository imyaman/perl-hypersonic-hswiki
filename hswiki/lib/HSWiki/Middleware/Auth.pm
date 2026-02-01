package HSWiki::Middleware::Auth;

use strict;
use warnings;


use HSWiki::Auth;
use HSWiki::Session;
use HSWiki::Model::User;
use HSWiki::Model::Role;
use Hypersonic::Response qw(res);

our $VERSION = '0.01';

# Middleware that requires authentication
# Returns a sub that can be used in route options
sub require_auth {
    my ($class) = @_;

    return sub {
        my ($req) = @_;

        unless (HSWiki::Auth->is_authenticated($req)) {
            return res->unauthorized('Authentication required')->finalize;
        }

        # Load user data if not already in session
        my $user_id = HSWiki::Auth->get_session_value($req, 'user_id');
        unless (HSWiki::Auth->get_session_value($req, 'username')) {
            my $user = HSWiki::Model::User->find_by_id($user_id);
            if ($user && $user->{is_active}) {
                HSWiki::Auth->set_session_user($req, $user);
            } else {
                HSWiki::Auth->clear_session($req);
                return res->unauthorized('Session expired')->finalize;
            }
        }

        return;  # Continue to handler
    };
}

# Middleware for optional authentication
# Loads user if authenticated but doesn't require it
sub optional_auth {
    my ($class) = @_;

    return sub {
        my ($req) = @_;

        if (HSWiki::Auth->is_authenticated($req)) {
            my $user_id = HSWiki::Auth->get_session_value($req, 'user_id');
            unless (HSWiki::Auth->get_session_value($req, 'username')) {
                my $user = HSWiki::Model::User->find_by_id($user_id);
                if ($user && $user->{is_active}) {
                    HSWiki::Auth->set_session_user($req, $user);
                } else {
                    HSWiki::Auth->clear_session($req);
                }
            }
        }

        return;  # Always continue
    };
}

# Middleware that requires admin role
sub require_admin {
    my ($class) = @_;

    return sub {
        my ($req) = @_;

        # First check authentication
        unless (HSWiki::Auth->is_authenticated($req)) {
            return res->unauthorized('Authentication required')->finalize;
        }

        # Check admin role
        unless (HSWiki::Auth->has_role($req, 'admin')) {
            return res->forbidden('Admin access required')->finalize;
        }

        return;  # Continue to handler
    };
}

# Middleware that requires a specific role
sub require_role {
    my ($class, $role_name) = @_;

    return sub {
        my ($req) = @_;

        unless (HSWiki::Auth->is_authenticated($req)) {
            return res->unauthorized('Authentication required')->finalize;
        }

        unless (HSWiki::Auth->has_role($req, $role_name)) {
            return res->forbidden("Role '$role_name' required")->finalize;
        }

        return;
    };
}

# Middleware for API key authentication (OpenAPI)
sub require_api_key {
    my ($class) = @_;

    return sub {
        my ($req) = @_;

        # Check for API key in header
        my $api_key = $req->header('X-API-Key');

        unless ($api_key) {
            return res->unauthorized('API key required')->finalize;
        }

        # Look up user by API key
        my $user = HSWiki::Model::User->find_by_api_key($api_key);

        unless ($user && $user->{is_active}) {
            return res->unauthorized('Invalid API key')->finalize;
        }

        # Store user info in session for handler access
        my ($session_id, $data) = HSWiki::Session->get_or_create($req);
        HSWiki::Session->set($session_id, api_user_id  => $user->{user_id});
        HSWiki::Session->set($session_id, api_username => $user->{username});
        HSWiki::Session->set($session_id, api_role_id  => $user->{role_id});

        return;  # Continue to handler
    };
}

# Helper to get current user from request
sub current_user {
    my ($class, $req) = @_;
    return HSWiki::Auth->get_session_user($req);
}

# Helper to get current user ID
sub current_user_id {
    my ($class, $req) = @_;
    return HSWiki::Auth->get_session_value($req, 'user_id')
        // HSWiki::Auth->get_session_value($req, 'api_user_id');
}

# Wrap handler with authentication middleware
sub wrap {
    my ($class, $handler, %opts) = @_;

    my $middleware;
    if ($opts{admin}) {
        $middleware = $class->require_admin;
    } elsif ($opts{role}) {
        $middleware = $class->require_role($opts{role});
    } elsif ($opts{api_key}) {
        $middleware = $class->require_api_key;
    } elsif ($opts{optional}) {
        $middleware = $class->optional_auth;
    } else {
        $middleware = $class->require_auth;
    }

    return sub {
        my ($req) = @_;

        # Run middleware
        my $result = $middleware->($req);

        # If middleware returned a response, return it (auth failed)
        return $result if $result;

        # Otherwise, continue to handler
        return $handler->($req);
    };
}

1;

__END__

=head1 NAME

HSWiki::Middleware::Auth - Authentication middleware for HSWiki

=head1 SYNOPSIS

    use HSWiki::Middleware::Auth;

    # In controller registration
    $server->get('/api/protected' => HSWiki::Middleware::Auth->wrap(sub {
        my ($req) = @_;
        my $user = HSWiki::Middleware::Auth->current_user($req);
        return res->json({ user => $user->{username} });
    }), { dynamic => 1 });

    # With admin requirement
    $server->get('/api/admin/users' => HSWiki::Middleware::Auth->wrap(sub {
        my ($req) = @_;
        # Only admins can access
    }, admin => 1), { dynamic => 1 });

    # With specific role
    $server->post('/api/pages' => HSWiki::Middleware::Auth->wrap(sub {
        my ($req) = @_;
        # Only editors can access
    }, role => 'editor'), { dynamic => 1 });

    # Optional auth (loads user if available)
    $server->get('/api/spaces' => HSWiki::Middleware::Auth->wrap(sub {
        my ($req) = @_;
        my $user = HSWiki::Middleware::Auth->current_user($req);
        # $user may be undef
    }, optional => 1), { dynamic => 1 });

    # API key auth (for OpenAPI)
    $server->get('/openapi/page' => HSWiki::Middleware::Auth->wrap(sub {
        my ($req) = @_;
        # Authenticated via X-API-Key header
    }, api_key => 1), { dynamic => 1 });

=cut
