#!/usr/bin/env perl
use strict;
use warnings;

use lib 'lib';
use Hypersonic;
use Hypersonic::Response qw(res);
use HSWiki::Auth;
use HSWiki::Session;

my $server = Hypersonic->new();

$server->get('/health' => sub { 'OK' });

$server->post('/api/test' => sub {
    my ($req) = @_;

    # Simple test - just return JSON
    return res->json({ test => 'ok' });
}, { dynamic => 1, parse_json => 1 });

$server->post('/api/session-test' => sub {
    my ($req) = @_;

    # Test session creation
    my ($session_id, $data) = HSWiki::Session->get_or_create($req);

    my $response = res->json({
        success => 1,
        session_id => $session_id,
    });
    HSWiki::Session->set_cookie($response, $session_id);

    return $response;
}, { dynamic => 1, parse_json => 1 });

$server->compile();
$server->run(port => 5215, workers => 1);
