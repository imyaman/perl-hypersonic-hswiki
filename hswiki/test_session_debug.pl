#!/usr/bin/env perl
use strict;
use warnings;


use lib 'lib';
use Hypersonic;
use Hypersonic::Response qw(res);
use HSWiki::Config;

my $server = Hypersonic->new();

# Configure sessions - this adds before and after middleware
my $session_config = HSWiki::Config->session;
$server->session_config(
    secret      => $session_config->{secret},
    cookie_name => $session_config->{cookie_name},
    max_age     => $session_config->{max_age},
    httponly    => $session_config->{httponly},
    secure      => $session_config->{secure},
    samesite    => $session_config->{samesite},
);

# Add debug middleware AFTER session middleware
$server->after(sub {
    my ($req, $res) = @_;
    warn "DEBUG AFTER: req=" . (defined $req ? 'defined' : 'undef') . " res=" . (defined $res ? ref($res) || 'scalar' : 'undef') . "\n";
    return $res;
});

$server->get('/health' => sub { 'OK' });

$server->get('/api/test' => sub {
    my ($req) = @_;
    warn "HANDLER: running\n";
    return res->json({ test => 'ok' });
}, { dynamic => 1 });

$server->compile();
$server->run(port => 5214, workers => 1);
