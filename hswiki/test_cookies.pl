#!/usr/bin/env perl
use strict;
use warnings;

use lib 'lib';
use Hypersonic;
use Hypersonic::Response qw(res);
use HSWiki::Auth;
use HSWiki::Session;
use HSWiki::Config;

my $server = Hypersonic->new();

$server->get('/health' => sub { 'OK' });

# Test with parse_cookies
$server->post('/api/login' => sub {
    my ($req) = @_;

    # Test session creation and cookie
    my ($session_id, $data) = HSWiki::Session->get_or_create($req);
    HSWiki::Session->set($session_id, user_id => 123);
    HSWiki::Session->set($session_id, username => 'testuser');

    my $response = res->json({
        success => 1,
        message => 'Logged in',
    });
    HSWiki::Session->set_cookie($response, $session_id);

    return $response->finalize;
}, { dynamic => 1, parse_json => 1, parse_cookies => 1 });

# Test reading session from cookie
$server->get('/api/me' => sub {
    my ($req) = @_;

    my ($session_id, $data) = HSWiki::Session->get($req);

    if ($session_id && $data->{user_id}) {
        return res->json({
            logged_in => 1,
            user_id   => $data->{user_id},
            username  => $data->{username},
        });
    }

    return res->json({ logged_in => 0 });
}, { dynamic => 1, parse_cookies => 1 });

$server->compile();
$server->run(port => 5216, workers => 1);
