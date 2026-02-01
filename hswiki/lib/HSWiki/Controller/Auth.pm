package HSWiki::Controller::Auth;

use strict;
use warnings;


use HSWiki::Auth;
use HSWiki::Session;
use HSWiki::Model::User;
use HSWiki::Model::Role;
use HSWiki::Middleware::Auth;
use Hypersonic::Response qw(res);

our $VERSION = '0.01';

# Register routes with the server
sub register {
    my ($class, $server) = @_;

    # POST /api/auth/register - User registration
    $server->post('/api/auth/register' => sub {
        my ($req) = @_;
        return $class->register_user($req);
    }, { dynamic => 1, parse_json => 1 });

    # POST /api/auth/login - User login
    $server->post('/api/auth/login' => sub {
        my ($req) = @_;
        return $class->login($req);
    }, { dynamic => 1, parse_json => 1 });

    # POST /api/auth/logout - User logout
    $server->post('/api/auth/logout' => HSWiki::Middleware::Auth->wrap(sub {
        my ($req) = @_;
        return $class->logout($req);
    }), { dynamic => 1, parse_cookies => 1 });

    # GET /api/auth/me - Current user info
    $server->get('/api/auth/me' => HSWiki::Middleware::Auth->wrap(sub {
        my ($req) = @_;
        return $class->me($req);
    }), { dynamic => 1, parse_cookies => 1 });

    # PUT /api/auth/password - Change password
    $server->put('/api/auth/password' => HSWiki::Middleware::Auth->wrap(sub {
        my ($req) = @_;
        return $class->change_password($req);
    }), { dynamic => 1, parse_json => 1, parse_cookies => 1 });

    # POST /api/auth/api-key - Regenerate API key
    $server->post('/api/auth/api-key' => HSWiki::Middleware::Auth->wrap(sub {
        my ($req) = @_;
        return $class->regenerate_api_key($req);
    }), { dynamic => 1, parse_cookies => 1 });
}

# User registration
sub register_user {
    my ($class, $req) = @_;

    my $data = $req->json;

    # Validate required fields
    for my $field (qw(username email password)) {
        unless ($data->{$field}) {
            return res->bad_request("$field is required")->finalize;
        }
    }

    # Validate username
    my $username_error = HSWiki::Auth->validate_username($data->{username});
    return res->bad_request($username_error)->finalize if $username_error;

    # Validate email
    my $email_error = HSWiki::Auth->validate_email($data->{email});
    return res->bad_request($email_error)->finalize if $email_error;

    # Validate password
    my $password_errors = HSWiki::Auth->validate_password($data->{password});
    return res->bad_request($password_errors->[0])->finalize if $password_errors;
    # Check if username exists
    if (HSWiki::Model::User->username_exists($data->{username})) {
        return res->conflict('Username already taken')->finalize;
    }

    # Check if email exists
    if (HSWiki::Model::User->email_exists($data->{email})) {
        return res->conflict('Email already registered')->finalize;
    }

    # Get default role (viewer)
    my $role_id = HSWiki::Model::Role->default_role_id;
    unless ($role_id) {
        # Initialize default roles if not exists
        HSWiki::Model::Role->init_defaults;
        $role_id = HSWiki::Model::Role->default_role_id;
    }

    # Create user
    my $user = HSWiki::Model::User->create(
        username => $data->{username},
        email    => $data->{email},
        password => $data->{password},
        role_id  => $role_id,
    );

    # Get role name for session
    my $role = HSWiki::Model::Role->find_by_id($role_id);

    # Log user in automatically
    $user->{role_name} = $role ? $role->{role_name} : 'viewer';
    my $session_id = HSWiki::Auth->set_session_user($req, $user);

    # Build response with session cookie
    my $response = res->status(201)->json({
        success => 1,
        message => 'Registration successful',
        user    => HSWiki::Model::User->to_safe($user),
    });
    HSWiki::Session->set_cookie($response, $session_id);

    return $response->finalize;
}

# User login
sub login {
    my ($class, $req) = @_;

    my $data = $req->json;

    unless ($data->{username} && $data->{password}) {
        return res->bad_request('Username and password required')->finalize;
    }

    # Authenticate
    my $user = HSWiki::Model::User->authenticate(
        $data->{username},
        $data->{password}
    );

    unless ($user) {
        return res->unauthorized('Invalid username or password')->finalize;
    }

    # Get role name
    my $role = HSWiki::Model::Role->find_by_id($user->{role_id});
    $user->{role_name} = $role ? $role->{role_name} : 'viewer';

    # Set session
    my $session_id = HSWiki::Auth->set_session_user($req, $user);

    # Build response with session cookie
    my $response = res->json({
        success => 1,
        message => 'Login successful',
        user    => HSWiki::Model::User->to_safe($user),
    });
    HSWiki::Session->set_cookie($response, $session_id);

    return $response->finalize;
}

# User logout
sub logout {
    my ($class, $req) = @_;

    HSWiki::Auth->clear_session($req);

    my $response = res->json({
        success => 1,
        message => 'Logout successful',
    });
    HSWiki::Session->clear_cookie($response);

    return $response->finalize;
}

# Get current user info
sub me {
    my ($class, $req) = @_;

    my $user_id = HSWiki::Auth->get_session_value($req, 'user_id');
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

# Change password
sub change_password {
    my ($class, $req) = @_;

    my $data = $req->json;

    unless ($data->{current_password} && $data->{new_password}) {
        return res->bad_request('Current and new password required')->finalize;
    }

    my $user_id = HSWiki::Auth->get_session_value($req, 'user_id');
    my $user = HSWiki::Model::User->find_by_id($user_id);

    # Verify current password
    unless (HSWiki::Auth->verify_password($data->{current_password}, $user->{password_hash})) {
        return res->unauthorized('Current password is incorrect')->finalize;
    }

    # Validate new password
    my $password_errors = HSWiki::Auth->validate_password($data->{new_password});
    return res->bad_request($password_errors->[0])->finalize if $password_errors;

    # Update password
    HSWiki::Model::User->change_password($user_id, $data->{new_password});

    return res->json({
        success => 1,
        message => 'Password changed successfully',
    })->finalize;
}

# Regenerate API key
sub regenerate_api_key {
    my ($class, $req) = @_;

    my $user_id = HSWiki::Auth->get_session_value($req, 'user_id');
    my $new_key = HSWiki::Model::User->regenerate_api_key($user_id);

    return res->json({
        success => 1,
        api_key => $new_key,
        message => 'API key regenerated. Save this key, it will not be shown again.',
    })->finalize;
}

1;

__END__

=head1 NAME

HSWiki::Controller::Auth - Authentication controller for HSWiki

=head1 ROUTES

    POST /api/auth/register - Register new user
        Body: { username, email, password }
        Returns: { success, message, user }

    POST /api/auth/login - User login
        Body: { username, password }
        Returns: { success, message, user }

    POST /api/auth/logout - User logout (requires auth)
        Returns: { success, message }

    GET /api/auth/me - Get current user info (requires auth)
        Returns: { user, role }

    PUT /api/auth/password - Change password (requires auth)
        Body: { current_password, new_password }
        Returns: { success, message }

    POST /api/auth/api-key - Regenerate API key (requires auth)
        Returns: { success, api_key, message }

=cut
