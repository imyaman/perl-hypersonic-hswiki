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

# Test with just res->text
$server->post('/api/test1' => sub {
    my ($req) = @_;
    return res->text('hello');
}, { dynamic => 1 });

# Test with res->ok
$server->get('/api/test2' => sub {
    my ($req) = @_;
    return res->ok('hello');
}, { dynamic => 1 });

# Test just returning res object
$server->get('/api/test3' => sub {
    my ($req) = @_;
    my $r = res;
    $r->status(200);
    $r->body('hello');
    return $r;
}, { dynamic => 1 });

$server->compile();
$server->run(port => 5212, workers => 1);
