#!/usr/bin/env perl
use strict;
use warnings;

use lib 'lib';
use Hypersonic;
use Hypersonic::Response qw(res);
use HSWiki::Auth;
use HSWiki::Session;
use HSWiki::Model::User;
use HSWiki::Model::Role;
use HSWiki::DB;

my $server = Hypersonic->new();

$server->get('/health' => sub { 'OK' });

$server->post('/api/register' => sub {
    my ($req) = @_;

    warn "=== Register handler called ===\n";

    my $data = $req->json;
    warn "JSON data: " . (defined $data ? "got it" : "undef") . "\n";

    unless ($data && $data->{username}) {
        warn "Missing data\n";
        return res->bad_request('Username required')->finalize;
    }

    warn "Username: $data->{username}\n";

    # Validate
    my $err = HSWiki::Auth->validate_username($data->{username});
    if ($err) {
        warn "Validation error: $err\n";
        return res->bad_request($err)->finalize;
    }

    # Check exists
    warn "Checking if username exists...\n";
    if (HSWiki::Model::User->username_exists($data->{username})) {
        warn "Username exists\n";
        return res->conflict('Username taken')->finalize;
    }

    # Get role
    warn "Getting default role...\n";
    my $role_id = HSWiki::Model::Role->default_role_id;
    warn "Role ID: " . ($role_id // "undef") . "\n";

    unless ($role_id) {
        warn "No role, initializing defaults...\n";
        HSWiki::Model::Role->init_defaults;
        $role_id = HSWiki::Model::Role->default_role_id;
    }

    # Create user
    warn "Creating user...\n";
    my $user = HSWiki::Model::User->create(
        username => $data->{username},
        email    => $data->{email} // 'test@test.com',
        password => $data->{password} // 'test123',
        role_id  => $role_id,
    );

    warn "User created: " . ($user->{user_id} // "unknown") . "\n";

    # Create session
    my $session_id = HSWiki::Auth->set_session_user($req, {
        user_id   => $user->{user_id},
        username  => $user->{username},
        role_id   => $user->{role_id},
        role_name => 'viewer',
    });

    my $response = res->status(201)->json({
        success => 1,
        message => 'Registered',
        user_id => $user->{user_id},
    });
    HSWiki::Session->set_cookie($response, $session_id);

    warn "Returning response\n";
    return $response->finalize;
}, { dynamic => 1, parse_json => 1 });

$server->compile();
$server->run(port => 5217, workers => 1);
