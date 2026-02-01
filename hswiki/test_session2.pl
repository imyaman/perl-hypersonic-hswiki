#!/usr/bin/env perl
use strict;
use warnings;


use lib 'lib';
use Hypersonic;
use Hypersonic::Response qw(res);
use HSWiki::Config;

my $server = Hypersonic->new();

# Configure sessions
my $session_config = HSWiki::Config->session;
$server->session_config(
    secret      => $session_config->{secret},
    cookie_name => $session_config->{cookie_name},
    max_age     => $session_config->{max_age},
    httponly    => $session_config->{httponly},
    secure      => $session_config->{secure},
    samesite    => $session_config->{samesite},
);

$server->get('/health' => sub { 'OK' });

$server->post('/api/test' => sub {
    my ($req) = @_;
    return res->json({ test => 'ok' });
}, { dynamic => 1 });

$server->compile();
$server->run(port => 5211, workers => 1);
